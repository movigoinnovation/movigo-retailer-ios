import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show EagerGestureRecognizer, OneSequenceGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:movigo/Controller/get_vehicle_list_provider.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/fare_calculator.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/helper/geocoding_utils.dart';
import 'package:movigo/helper/places_session_token.dart';
import 'package:movigo/helper/map_picker.dart';
import 'new_confirm_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PRICING BUG FIX — Root cause was a race condition:
//
//   1. initState set _rawDistanceKm = haversine distance (immediate, ~7.8 km)
//   2. Consumer rebuilt → _ensureBackendEstimates() fired API call with 7.8 km
//   3. _fetchRoute() completed → _rawDistanceKm updated to Google distance (~9.1 km)
//   4. Consumer rebuilt again → _ensureBackendEstimates() saw cache hit → skipped new call
//   5. Old API (7.8 km) responded → wrote stale fare → flickered to wrong price
//
// FIX STRATEGY:
//   • Never fetch estimates until Google Directions route is resolved.
//   • If _rawDistanceKm changes significantly (>0.3 km) after estimates loaded,
//     clear the cache and re-fetch with the correct distance.
//   • Show loading skeleton for fares while estimates are in-flight.
//   • _fareFor() never falls back to local calc while estimates are loading.
//   • Single source of truth: ONLY backend total_with_platform_fee is displayed.
// ═══════════════════════════════════════════════════════════════════════════════

class _ExtraStop {
  final String address;
  final LatLng latLng;
  String contactName;
  String contactPhone;
  _ExtraStop({required this.address, required this.latLng, this.contactName = '', this.contactPhone = ''});
}

class RouteVehicleScreen extends StatefulWidget {
  // Pickup/drop are optional — when drop is not supplied, the screen opens
  // in the location-search phase (ported from the old LocationSelectionScreen)
  // instead of jumping straight to the map + vehicle-selection phase.
  final LatLng? pickupLatLng;
  final String? pickupAddress;
  final String pickupContactName;
  final String pickupContactPhone;
  final LatLng? dropLatLng;
  final String? dropAddress;
  final String? preSelectedVehicleName;
  final String dropContactName;
  final String dropContactPhone;
  // When provided, selecting a vehicle calls this callback and pops instead
  // of navigating forward — used by the "Change Vehicle" flow on RetailerConfirmScreen.
  final void Function(Map<String, dynamic>)? onVehicleSelected;
  // When both pickup & drop are already known and no review/edit of the
  // locations is wanted, jump straight to the map + vehicle booking phase
  // (used by "Change Vehicle" and the previous-drop quick-select flow).
  // Ignored when dropLatLng is null — the location phase is always shown
  // in that case since there's nothing to book yet.
  final bool skipLocationPhase;
  // Pre-existing intermediate stops (multidrop) to seed _extraStops with —
  // used by "Book Again" on a past multi-drop booking so the retailer lands
  // straight on vehicle selection with every original stop + contact already
  // in place instead of having to re-add them. Each entry: {address, lat,
  // lng, contactName, contactPhone}. Only consumed when skipLocationPhase is
  // also true (drop must already be known too); ignored otherwise.
  final List<Map<String, dynamic>> initialExtraStops;

  const RouteVehicleScreen({
    super.key,
    this.pickupLatLng,
    this.pickupAddress,
    this.pickupContactName  = '',
    this.pickupContactPhone = '',
    this.dropLatLng,
    this.dropAddress,
    this.preSelectedVehicleName,
    this.dropContactName  = '',
    this.dropContactPhone = '',
    this.onVehicleSelected,
    this.skipLocationPhase = false,
    this.initialExtraStops = const [],
  });

  @override
  State<RouteVehicleScreen> createState() => _RouteVehicleScreenState();
}

enum _Phase { location, booking }

class _RouteVehicleScreenState extends State<RouteVehicleScreen> {
  VehicleTypeController? _vcRef;

  // ── Phase: location search vs vehicle booking ──────────────────────────────
  late _Phase _phase;

  // True while the vehicle list has more cards below the visible area at the
  // sheet's current height — shows a "scroll for more" hint so people don't
  // miss vehicles sitting below the fold.
  bool _hasMoreVehiclesBelow = false;

  // ── Location-phase fields (ported from the old LocationSelectionScreen) ─────
  final TextEditingController _pickupCtrl = TextEditingController();
  final TextEditingController _dropCtrl = TextEditingController();
  final FocusNode _pickupFocus = FocusNode();
  final FocusNode _dropFocus = FocusNode();
  String _locActiveField = "drop";
  List<Map<String, dynamic>> _locSuggestions = [];
  List<Map<String, dynamic>> _recentDrops = [];
  List<Map<String, dynamic>> _recentPickups = [];
  Timer? _locDebounce;
  bool _isLoadingSuggestions = false;
  bool _isFetchingCurrentLocation = false;
  // Bundles an Autocomplete typing sequence + its terminating Details call
  // into one billed Places session instead of billing every request alone.
  String? _locSessionToken;

  // ── Inline "drag to pin-point" map on the Choose Location screen ────────────
  // Lets the user nudge the pickup/drop to the exact spot after searching,
  // without leaving the screen. The map edits whichever field is active.
  final GlobalKey<_DraggableMapPinState> _locMapKey =
      GlobalKey<_DraggableMapPinState>();
  bool _locMapGeocoding = false;

  // ── Distance state ──────────────────────────────────────────────────────────
  double _rawDistanceKm = 0;        // authoritative km (from Google Directions)
  double _haversineKm   = 0;        // haversine fallback (used only if Directions fails)
  bool _isLoadingRoute  = true;
  bool _routeResolved   = false;    // true once Directions API responded (ok or fail)
  int  _routeRequestId  = 0;        // guards against a stale in-flight fetch overwriting a newer one

  // ── Fare state ──────────────────────────────────────────────────────────────
  String? _selectedKey;

  /// Stores the backend-calculated total payable per vehicle key.
  /// NEVER written until the route is resolved with the correct km.
  final Map<String, int>  _backendFareByKey   = {};
  final Set<String>       _backendFareLoading = {};

  /// Priority Pickup eligibility/preview per vehicle key, from the same
  /// price_estimate response as the fare above — never charged from here,
  /// just shown. Cleared alongside the fare cache so it never goes stale.
  final Map<String, Map<String, dynamic>> _priorityPickupByKey = {};

  /// Coins the retailer earns once the booking is Delivered, per vehicle key —
  /// from `price_breakup.estimated_coins` in the same price_estimate response.
  final Map<String, int> _coinsByKey = {};

  /// First-Ride Discount preview per vehicle key — {percent, amount,
  /// pre_discount_total} from the same price_estimate response. Only
  /// non-empty when the retailer is actually eligible (backend decides, this
  /// just displays it).
  final Map<String, Map<String, dynamic>> _discountByKey = {};

  /// The km value that was used to request the currently-cached fares.
  /// If _rawDistanceKm differs from this by >0.3 km, we invalidate the cache.
  double _fareRequestedAtKm = 0;

  /// True once _ensureBackendEstimates has been called at least once after
  /// route resolved. Prevents _fareFor from showing local-calc fallback during
  /// the one-frame window between route resolution and first API call.
  bool _estimatesEverStarted = false;

  // ── Multi-drop stops ────────────────────────────────────────────────────────
  final List<_ExtraStop> _extraStops = [];
  List<Map<String, dynamic>> _savedAddresses = [];
  bool _savedAddressesLoaded = false;
  bool _isBookingMultiDrop = false;

  // Effective pickup/drop — can be reordered by the user in the location bar.
  // Contact info travels WITH the address (not the role), so swapping a drop
  // into the pickup slot carries its own contact along, not the old pickup's.
  late String _effectivePickupAddress;
  late LatLng  _effectivePickupLatLng;
  late String  _effectivePickupContactName;
  late String  _effectivePickupContactPhone;
  late String  _effectiveDropAddress;
  late LatLng  _effectiveDropLatLng;
  late String  _effectiveDropContactName;
  late String  _effectiveDropContactPhone;

  // True only once the location phase has actually populated its working
  // fields this session — if we started directly in the booking phase
  // (skipLocationPhase, e.g. "Change Vehicle"), there is nothing to go back
  // to, so the back button should pop the route instead.
  bool _canReturnToLocationPhase = false;

  void _handleBack() {
    if (_phase == _Phase.booking && _canReturnToLocationPhase) {
      setState(() => _phase = _Phase.location);
    } else {
      Navigator.maybePop(context);
    }
  }

  @override
  void initState() {
    super.initState();
    final bool hasDrop        = widget.dropLatLng != null;
    final bool startInBooking = hasDrop && widget.skipLocationPhase;
    _phase = startInBooking ? _Phase.booking : _Phase.location;
    _canReturnToLocationPhase = !startInBooking;

    _pickupFocus.addListener(() {
      if (_pickupFocus.hasFocus && mounted) {
        setState(() => _locActiveField = "pickup");
        _recenterLocationMapSoon();
      }
    });
    _dropFocus.addListener(() {
      if (_dropFocus.hasFocus && mounted) {
        setState(() => _locActiveField = "drop");
        _fetchRecentDrops();
        _recenterLocationMapSoon();
      }
    });

    if (startInBooking) {
      _effectivePickupAddress      = widget.pickupAddress ?? '';
      _effectivePickupLatLng       = widget.pickupLatLng!;
      _effectivePickupContactName  = widget.pickupContactName;
      _effectivePickupContactPhone = widget.pickupContactPhone;
      _effectiveDropAddress        = widget.dropAddress ?? '';
      _effectiveDropLatLng         = widget.dropLatLng!;
      _effectiveDropContactName    = widget.dropContactName;
      _effectiveDropContactPhone   = widget.dropContactPhone;
      for (final s in widget.initialExtraStops) {
        final lat = s['lat'];
        final lng = s['lng'];
        if (lat == null || lng == null) continue;
        _extraStops.add(_ExtraStop(
          address:      (s['address'] ?? '').toString(),
          latLng:       LatLng((lat as num).toDouble(), (lng as num).toDouble()),
          contactName:  (s['contactName']  ?? s['contact_name']  ?? '').toString(),
          contactPhone: (s['contactPhone'] ?? s['contact_phone'] ?? '').toString(),
        ));
      }

      // Mirror the effective values into the location-phase working fields
      // too (and allow returning to that phase) — without this, "Edit
      // Locations" either did nothing (_canReturnToLocationPhase stayed
      // false) or, if enabled, would have flipped to _Phase.location with
      // every working field still at its unset default (null/''), showing
      // blank search boxes instead of the real pickup/drop/stops.
      _wkPickupLatLng       = _effectivePickupLatLng;
      _wkPickupAddress      = _effectivePickupAddress;
      _pickupCtrl.text      = _effectivePickupAddress;
      _wkPickupContactName  = _effectivePickupContactName;
      _wkPickupContactPhone = _effectivePickupContactPhone;
      _wkDropLatLng         = _effectiveDropLatLng;
      _wkDropAddress        = _effectiveDropAddress;
      _dropCtrl.text        = _effectiveDropAddress;
      _wkDropContactName    = _effectiveDropContactName;
      _wkDropContactPhone   = _effectiveDropContactPhone;
      _canReturnToLocationPhase = true;

      _initRouteAndMarkers();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _initVehicleListing();
        _loadSavedAddresses();
        _fetchRecentPickups();
      });
      return;
    }

    // ── Location phase bootstrap (ported from the old LocationSelectionScreen) ──
    _wkPickupLatLng  = widget.pickupLatLng;
    _wkPickupAddress = widget.pickupAddress ?? '';
    _pickupCtrl.text = _wkPickupAddress;
    final bool dropPreFilled = hasDrop;
    _wkPickupContactName  = widget.pickupContactName;
    _wkPickupContactPhone = widget.pickupContactPhone;
    if (dropPreFilled) {
      _wkDropLatLng       = widget.dropLatLng;
      _wkDropAddress       = widget.dropAddress ?? '';
      _dropCtrl.text        = _wkDropAddress;
      _wkDropContactName   = widget.dropContactName;
      _wkDropContactPhone  = widget.dropContactPhone;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final bool isFallback = _wkPickupAddress == "Indore, Madhya Pradesh" ||
          _wkPickupAddress == "Fetching location..." ||
          _wkPickupAddress.trim().isEmpty;
      if (_wkPickupLatLng == null || isFallback) {
        await _useCurrentLocation();
      } else if (_looksLikeLatLngText(_wkPickupAddress)) {
        final address = await _addressFromLatLng(_wkPickupLatLng!);
        if (mounted) {
          setState(() {
            _wkPickupAddress = address;
            _pickupCtrl.text = address;
          });
        }
      }
      if (!mounted) return;
      // Focus pickup when drop is already filled, otherwise focus drop.
      // Focusing drop already triggers _fetchRecentDrops via the focus
      // listener above, so only fetch it explicitly here in the pickup case.
      if (dropPreFilled) {
        _pickupFocus.requestFocus();
        _fetchRecentDrops();
      } else {
        _dropFocus.requestFocus();
      }
      _loadSavedAddresses();
      _fetchRecentPickups();
    });
  }

  void _initRouteAndMarkers() {
    _haversineKm   = _haversineDistanceKm(_effectivePickupLatLng, _effectiveDropLatLng);
    _rawDistanceKm = _haversineKm;         // initial estimate only, until Directions responds
    _fetchRoute();                          // async — updates _rawDistanceKm when done
  }

  void _initVehicleListing() {
    final vc = Provider.of<VehicleTypeController>(context, listen: false);
    _vcRef = vc;
    if (vc.vehicleTypes.isEmpty) {
      vc.getVehicleTypeList(context);
    } else {
      // Vehicles already loaded — kick off fare estimates immediately
      _triggerEstimatesAndAutoSelect();
    }
    // Listen for future vehicle list changes to start estimates
    vc.addListener(_onVehicleTypesChanged);
  }

  // ── Location phase: working pickup/drop (unconfirmed) ───────────────────────
  LatLng? _wkPickupLatLng;
  String _wkPickupAddress      = "";
  String _wkPickupContactName  = "";
  String _wkPickupContactPhone = "";
  LatLng? _wkDropLatLng;
  String _wkDropAddress        = "";
  String _wkDropContactName    = "";
  String _wkDropContactPhone   = "";

  bool get _canConfirmLocation =>
      _wkPickupLatLng != null &&
      _wkDropLatLng != null &&
      _wkPickupAddress.isNotEmpty &&
      _wkDropAddress.isNotEmpty;

  void _confirmLocation() {
    if (!_canConfirmLocation) return;
    setState(() {
      _effectivePickupAddress      = _wkPickupAddress;
      _effectivePickupLatLng       = _wkPickupLatLng!;
      _effectivePickupContactName  = _wkPickupContactName;
      _effectivePickupContactPhone = _wkPickupContactPhone;
      _effectiveDropAddress        = _wkDropAddress;
      _effectiveDropLatLng         = _wkDropLatLng!;
      _effectiveDropContactName    = _wkDropContactName;
      _effectiveDropContactPhone   = _wkDropContactPhone;
      _phase = _Phase.booking;
      _canReturnToLocationPhase = true;
    });
    _initRouteAndMarkers();
    _initVehicleListing();
  }

  void _onVehicleTypesChanged() {
    if (mounted) _triggerEstimatesAndAutoSelect();
  }

  void _triggerEstimatesAndAutoSelect() {
    final vc = Provider.of<VehicleTypeController>(context, listen: false);
    final choices = _buildVehicleChoices(vc.vehicleTypes);
    if (choices.isEmpty) return;
    _ensureBackendEstimates(choices);
    _autoSelect(choices);
  }

  @override
  void dispose() {
    _vcRef?.removeListener(_onVehicleTypesChanged);
    _locDebounce?.cancel();
    _pickupCtrl.dispose();
    _dropCtrl.dispose();
    _pickupFocus.dispose();
    _dropFocus.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Location phase — ported from the old LocationSelectionScreen
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _fetchRecentDrops() async {
    try {
      final data = await getData('user/recent_drops', context, headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
      });
      if (!mounted) return;
      if (data != null && data['success'] == true) {
        setState(() => _recentDrops =
            List<Map<String, dynamic>>.from(data['data'] ?? []));
      }
    } catch (e) {
      debugPrint('fetchRecentDrops error: $e');
    }
  }

  Future<void> _fetchRecentPickups() async {
    try {
      final data = await getData('user/recent_pickups', context, headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
      });
      if (!mounted) return;
      if (data != null && data['success'] == true) {
        setState(() => _recentPickups =
            List<Map<String, dynamic>>.from(data['data'] ?? []));
      }
      _applyLastUsedPickupContact();
    } catch (e) {
      debugPrint('fetchRecentPickups error: $e');
    }
  }

  // Prefills the pickup contact with whoever was actually reached last time
  // at (or near) this pickup point, instead of defaulting to the retailer's
  // own profile — the shop counter contact is usually who a driver needs to
  // call, not the account holder. Falls back to the most recently used
  // pickup contact overall when no address match is close enough, since
  // retailers typically ship from the same one or two places.
  void _applyLastUsedPickupContact() {
    if (!mounted || _recentPickups.isEmpty) return;
    if (_wkPickupContactName.isNotEmpty && _wkPickupContactPhone.isNotEmpty) return;
    if (_wkPickupLatLng == null) return;

    Map<String, dynamic>? nearest;
    double bestKm = double.infinity;
    for (final r in _recentPickups) {
      final lat = r['lat'];
      final lng = r['lng'];
      if (lat == null || lng == null) continue;
      final km = _haversineDistanceKm(
        _wkPickupLatLng!,
        LatLng((lat as num).toDouble(), (lng as num).toDouble()),
      );
      if (km < bestKm) { bestKm = km; nearest = r; }
    }
    final chosen = (nearest != null && bestKm <= 0.3) ? nearest : _recentPickups.first;
    final name  = (chosen['contact_name']  ?? '').toString();
    final phone = (chosen['contact_phone'] ?? '').toString();
    if (name.isEmpty && phone.isEmpty) return;
    setState(() {
      _wkPickupContactName  = name;
      _wkPickupContactPhone = phone;
    });
  }

  bool _isAddressSaved(String address) =>
      _savedAddresses.any((a) => (a['address'] ?? '').toString() == address);

  // One-tap save, matching the "fast" ask — no sheet, no typing a label.
  Future<void> _quickSaveRecent(Map<String, dynamic> recent) async {
    final lat = recent['lat'];
    final lng = recent['lng'];
    final address = (recent['address'] ?? '').toString();
    if (lat == null || lng == null || address.isEmpty) return;
    final label = address.split(',').first.trim();
    try {
      final data = await postJsonData(
        'user/save_address',
        {
          'label':         label.isEmpty ? 'Saved' : label,
          'address':       address,
          'lat':           lat,
          'lng':           lng,
          'contact_name':  (recent['contact_name']  ?? '').toString(),
          'contact_phone': (recent['contact_phone'] ?? '').toString(),
        },
        context,
        headers: {'Authorization': 'Bearer ${AppConstant.token}'},
      );
      if (!mounted) return;
      if (data != null && data['success'] == true) {
        SnackBarToastMessage.showSnackBar(context, 'Saved as "$label"');
        setState(() {});
        _loadSavedAddresses(force: true);
      }
    } catch (e) {
      debugPrint('quickSaveRecent error: $e');
    }
  }

  Future<void> _selectRecentLocation(Map<String, dynamic> recent) async {
    final lat = recent['lat'];
    final lng = recent['lng'];
    if (lat == null || lng == null) return;
    final latLng = LatLng((lat as num).toDouble(), (lng as num).toDouble());
    var address = (recent['address'] ?? '').toString();
    if (address.isEmpty || _looksLikeLatLngText(address)) {
      address = await _addressFromLatLng(latLng);
    }
    final contactName  = (recent['contact_name']  ?? '').toString();
    final contactPhone = (recent['contact_phone'] ?? '').toString();
    if (!mounted) return;
    setState(() {
      if (_locActiveField == 'pickup') {
        _wkPickupLatLng       = latLng;
        _wkPickupAddress      = address;
        _pickupCtrl.text      = address;
        _wkPickupContactName  = contactName;
        _wkPickupContactPhone = contactPhone;
      } else {
        _wkDropLatLng        = latLng;
        _wkDropAddress       = address;
        _dropCtrl.text       = address;
        _wkDropContactName   = contactName;
        _wkDropContactPhone  = contactPhone;
      }
      _locSuggestions = [];
    });
    if (_canConfirmLocation && _extraStops.isEmpty) _confirmLocation();
  }

  Future<void> _openMapForActiveField() async {
    final isPickup = _locActiveField == 'pickup';
    final initial = isPickup ? _wkPickupLatLng : _wkDropLatLng;
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLocation: initial,
          isDropLocation: !isPickup,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final ll   = result['location'] as LatLng?;
    final addr = result['address']?.toString() ?? '';
    if (ll == null || addr.isEmpty) return;
    setState(() {
      if (isPickup) {
        _wkPickupLatLng  = ll;
        _wkPickupAddress = addr;
        _pickupCtrl.text = addr;
        _wkPickupContactName  = '';
        _wkPickupContactPhone = '';
      } else {
        _wkDropLatLng  = ll;
        _wkDropAddress = addr;
        _dropCtrl.text = addr;
        _wkDropContactName  = '';
        _wkDropContactPhone = '';
      }
      _locSuggestions = [];
    });
    if (isPickup) _applyLastUsedPickupContact();
  }

  Future<void> _showLocationSavedAddressSheet() async {
    final selected = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => _SavedAddressesPage(
          addresses: _savedAddresses,
          addressIconFor: _savedAddressIcon,
        ),
      ),
    );
    if (selected == null || !mounted) return;

    final lat = selected['lat'];
    final lng = selected['lng'];
    if (lat == null || lng == null) return;
    final latLng = LatLng((lat as num).toDouble(), (lng as num).toDouble());
    var addr = (selected['address'] ?? '').toString();
    if (addr.isEmpty || _looksLikeLatLngText(addr)) {
      addr = await _addressFromLatLng(latLng);
    }
    final contactName  = (selected['contact_name']  ?? '').toString();
    final contactPhone = (selected['contact_phone'] ?? '').toString();
    if (!mounted) return;
    setState(() {
      if (_locActiveField == 'pickup') {
        _wkPickupLatLng       = latLng;
        _wkPickupAddress      = addr;
        _pickupCtrl.text      = addr;
        _wkPickupContactName  = contactName;
        _wkPickupContactPhone = contactPhone;
      } else {
        _wkDropLatLng        = latLng;
        _wkDropAddress       = addr;
        _dropCtrl.text       = addr;
        _wkDropContactName   = contactName;
        _wkDropContactPhone  = contactPhone;
      }
      _locSuggestions = [];
    });
    // Skip auto-confirm when stops exist — give the user a chance to
    // review/reorder the route first.
    if (_canConfirmLocation && _extraStops.isEmpty) _confirmLocation();
  }

  void _swapLocations() {
    setState(() {
      final tmpText          = _pickupCtrl.text;
      final tmpAddress       = _wkPickupAddress;
      final tmpLatLng        = _wkPickupLatLng;
      final tmpContactName   = _wkPickupContactName;
      final tmpContactPhone  = _wkPickupContactPhone;

      _pickupCtrl.text       = _dropCtrl.text;
      _wkPickupAddress       = _wkDropAddress;
      _wkPickupLatLng        = _wkDropLatLng;
      _wkPickupContactName   = _wkDropContactName;
      _wkPickupContactPhone  = _wkDropContactPhone;

      _dropCtrl.text         = tmpText;
      _wkDropAddress         = tmpAddress;
      _wkDropLatLng          = tmpLatLng;
      _wkDropContactName     = tmpContactName;
      _wkDropContactPhone    = tmpContactPhone;

      _locSuggestions = [];
    });
  }

  Widget? _currentLocationTrailingButton(String target) {
    if (_pickupCtrl.text.isNotEmpty || _dropCtrl.text.isNotEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _useCurrentLocationFor(target),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColor.themeColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _isFetchingCurrentLocation
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColor.themeColor),
                )
              : const Icon(Icons.my_location_rounded,
                  color: AppColor.themeColor, size: 18),
        ),
      ),
    );
  }

  Future<void> _useCurrentLocation() => _useCurrentLocationFor("pickup");

  Future<void> _useCurrentLocationFor(String target) async {
    if (_isFetchingCurrentLocation) return;
    setState(() => _isFetchingCurrentLocation = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 8));
      final latLng = LatLng(pos.latitude, pos.longitude);
      final address = await _addressFromLatLng(latLng);

      if (mounted) {
        setState(() {
          if (target == "pickup") {
            _wkPickupLatLng  = latLng;
            _wkPickupAddress = address;
            _pickupCtrl.text = address;
            _wkPickupContactName  = '';
            _wkPickupContactPhone = '';
            _locActiveField  = "drop";
          } else {
            _wkDropLatLng    = latLng;
            _wkDropAddress   = address;
            _dropCtrl.text   = address;
            _wkDropContactName  = '';
            _wkDropContactPhone = '';
            _locActiveField  = "pickup";
          }
          _isFetchingCurrentLocation = false;
        });
        if (target == "pickup") {
          _applyLastUsedPickupContact();
          _dropFocus.requestFocus();
        } else {
          _pickupFocus.requestFocus();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isFetchingCurrentLocation = false);
    }
  }

  IconData _savedAddressIcon(String label) {
    final l = label.toLowerCase();
    if (l == 'home') return Icons.home_outlined;
    if (l == 'work') return Icons.work_outline;
    return Icons.place_outlined; // Other
  }

  bool _looksLikeLatLngText(String value) {
    return RegExp(r'^-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?$')
        .hasMatch(value.trim());
  }

  String _buildAddressFromPlacemark(Placemark p, LatLng fallback) {
    final parts = <String?>[
      p.name,
      p.street,
      p.subLocality,
      p.locality,
      p.subAdministrativeArea,
      p.administrativeArea,
      p.postalCode,
    ]
        .where((part) => part != null && part.trim().isNotEmpty)
        .map((part) => part!.trim())
        .toList();

    final uniqueParts = <String>[];
    for (final part in parts) {
      if (!uniqueParts.any((saved) => saved.toLowerCase() == part.toLowerCase())) {
        uniqueParts.add(part);
      }
    }

    final address = uniqueParts.join(', ').trim();
    if (address.isNotEmpty) return address;
    return '${fallback.latitude.toStringAsFixed(6)}, ${fallback.longitude.toStringAsFixed(6)}';
  }

  // ── Inline map helpers ────────────────────────────────────────────────────
  // Point the inline map at the active field's current coordinate. Called
  // after a suggestion/recent/saved pick and whenever the active field flips.
  void _recenterLocationMap() {
    final ll = _locActiveField == 'pickup' ? _wkPickupLatLng : _wkDropLatLng;
    if (ll == null) return;
    _locMapKey.currentState?.moveCameraTo(ll, zoom: 16);
  }

  void _recenterLocationMapSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recenterLocationMap();
    });
  }

  // Fired when the user finishes panning the inline map. Writes the new
  // centre into the active field and reverse-geocodes it. Settles from a
  // programmatic recenter land within ~30 m of the value we just set, so
  // the proximity check below makes them no-ops (and saves a geocode call).
  Future<void> _onLocationMapIdle(LatLng target) async {
    final active = _locActiveField;
    final currentLl = active == 'pickup' ? _wkPickupLatLng : _wkDropLatLng;
    if (currentLl != null &&
        _haversineDistanceKm(target, currentLl) < 0.03) {
      return;
    }

    setState(() {
      _locMapGeocoding = true;
      if (active == 'pickup') {
        _wkPickupLatLng = target;
        _wkPickupContactName = '';
        _wkPickupContactPhone = '';
      } else {
        _wkDropLatLng = target;
        _wkDropContactName = '';
        _wkDropContactPhone = '';
      }
    });

    final addr = await _addressFromLatLng(target);
    if (!mounted || _locActiveField != active) {
      if (mounted) setState(() => _locMapGeocoding = false);
      return;
    }
    setState(() {
      _locMapGeocoding = false;
      if (active == 'pickup') {
        _wkPickupAddress = addr;
        _pickupCtrl.text = addr;
      } else {
        _wkDropAddress = addr;
        _dropCtrl.text = addr;
      }
    });
  }

  Future<String> _addressFromLatLng(LatLng latLng) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${latLng.latitude},${latLng.longitude}'
        '&key=${AppConstant.googleApiKey}'
        '&language=en',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List? ?? [];
        if (data['status'] == 'OK' && results.isNotEmpty) {
          final addr = bestAddressFromGeoResults(results);
          if (addr.isNotEmpty) return addr;
        }
      }
    } catch (_) {}

    return '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}';
  }

  void _onLocationSearchChanged(String query) {
    _locDebounce?.cancel();
    if (query.trim().isEmpty) {
      _locSessionToken = null;
      if (mounted) setState(() => _locSuggestions = []);
      return;
    }
    _locDebounce = Timer(const Duration(milliseconds: 300), () {
      _fetchLocationSuggestions(query.trim());
    });
  }

  Future<void> _fetchLocationSuggestions(String input) async {
    if (mounted) setState(() => _isLoadingSuggestions = true);
    _locSessionToken ??= PlacesSessionToken.generate();
    try {
      final double lat = _wkPickupLatLng?.latitude  ?? 22.7196;
      final double lng = _wkPickupLatLng?.longitude ?? 75.8577;
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(input)}'
        '&location=$lat,$lng'
        '&radius=50000'
        '&components=country:in'
        '&region=in'
        '&sessiontoken=$_locSessionToken'
        '&key=${AppConstant.googleApiKey}',
      );
      final response = await http.get(url);
      if (!mounted) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final predictions = data['predictions'] as List? ?? [];
      setState(() {
        _locSuggestions = predictions
            .map<Map<String, dynamic>>((p) => {
                  'place_id': p['place_id'],
                  'description': p['description'],
                  'main_text': (p['structured_formatting']?['main_text']) ?? '',
                  'secondary_text':
                      (p['structured_formatting']?['secondary_text']) ?? '',
                })
            .toList();
      });
    } catch (_) {
      if (mounted) setState(() => _locSuggestions = []);
    } finally {
      if (mounted) setState(() => _isLoadingSuggestions = false);
    }
  }

  Future<Map<String, dynamic>?> _getDetailsFromPlaceId(String placeId, {String? fallbackAddress}) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$placeId'
        '&fields=geometry,formatted_address,name'
        '&sessiontoken=$_locSessionToken'
        '&key=${AppConstant.googleApiKey}',
      );
      // Details call ends the session — next search starts a fresh one.
      _locSessionToken = null;
      final res = await http.get(url);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final result = data['result'];
      final loc = result?['geometry']?['location'];
      final formattedAddress = result?['formatted_address']?.toString() ?? '';
      if (loc != null) {
        return {
          'latLng': LatLng(
            (loc['lat'] as num).toDouble(),
            (loc['lng'] as num).toDouble(),
          ),
          'formatted_address': formattedAddress,
        };
      }
    } catch (_) {}

    try {
      if (fallbackAddress != null && fallbackAddress.trim().isNotEmpty) {
        final locations = await locationFromAddress(fallbackAddress);
        if (locations.isNotEmpty) {
          return {
            'latLng': LatLng(locations.first.latitude, locations.first.longitude),
            'formatted_address': fallbackAddress,
          };
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _onLocationSuggestionTap(Map<String, dynamic> suggestion) async {
    final desc = suggestion['description'] as String;
    final placeId = suggestion['place_id'] as String;

    FocusManager.instance.primaryFocus?.unfocus();
    if (mounted) setState(() => _locSuggestions = []);

    final details = await _getDetailsFromPlaceId(placeId, fallbackAddress: desc);
    final latLng = details?['latLng'] as LatLng?;
    final formattedAddress = details?['formatted_address'] as String? ?? desc;

    if (!mounted) return;

    if (_locActiveField == "pickup") {
      _pickupCtrl.text = formattedAddress;
      _wkPickupAddress = formattedAddress;
      _wkPickupLatLng  = latLng;
      _wkPickupContactName  = '';
      _wkPickupContactPhone = '';
    } else {
      _dropCtrl.text  = formattedAddress;
      _wkDropAddress  = formattedAddress;
      _wkDropLatLng   = latLng;
      _wkDropContactName  = '';
      _wkDropContactPhone = '';
    }

    setState(() {});
    if (_locActiveField == "pickup") _applyLastUsedPickupContact();

    // Don't auto-advance from a typed search any more — drop the user onto
    // the inline map centred on the picked place so they can nudge the pin
    // to the exact spot, then tap "Confirm Locations" themselves.
    _recenterLocationMapSoon();
  }

  // ── Google Directions route fetch ───────────────────────────────────────────
  Future<void> _fetchRoute() async {
    final requestId = ++_routeRequestId;
    if (mounted) setState(() => _isLoadingRoute = true);
    try {
      final origin      = _effectivePickupLatLng;
      final destination = _effectiveDropLatLng;
      final waypointsParam = _extraStops.isEmpty
          ? ''
          : '&waypoints=${_extraStops.map((s) => '${s.latLng.latitude},${s.latLng.longitude}').join('|')}';
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '$waypointsParam'
        '&mode=driving&alternatives=false&key=${AppConstant.googleApiKey}',
      );
      final res = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Directions API timeout'),
      );
      if (!mounted || requestId != _routeRequestId) return;

      final data   = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;

      if (routes != null && routes.isNotEmpty) {
        final route = routes.first as Map<String, dynamic>;
        final legs  = (route['legs'] as List).cast<Map<String, dynamic>>();
        final totalMeters  = legs.fold<double>(0, (sum, leg) => sum + ((leg['distance']?['value'] as num?)?.toDouble() ?? 0));

        final fallbackKm = _extraStops.isEmpty ? _haversineKm : _totalWaypointKm();
        final newKm  = totalMeters > 0 ? totalMeters / 1000.0 : fallbackKm;

        setState(() {
          _rawDistanceKm = newKm;
          _isLoadingRoute = false;
          _routeResolved  = true;
          // ── KEY FIX: Clear any stale fares from haversine-distance calls ──
          // If _ensureBackendEstimates already fired (edge case where vehicle
          // list loaded before route), invalidate so we re-fetch with true km.
          _invalidateFareCache(reason: 'route resolved');
        });
        _triggerEstimatesAndAutoSelect();
      } else {
        // Directions failed — use haversine as authoritative distance
        setState(() {
          _rawDistanceKm = _extraStops.isEmpty ? _haversineKm : _totalWaypointKm();
          _isLoadingRoute = false;
          _routeResolved  = true;
        });
        _triggerEstimatesAndAutoSelect();
      }
    } catch (_) {
      if (mounted && requestId == _routeRequestId) {
        setState(() {
          _rawDistanceKm = _extraStops.isEmpty ? _haversineKm : _totalWaypointKm();
          _isLoadingRoute = false;
          _routeResolved  = true;
        });
        _triggerEstimatesAndAutoSelect();
      }
    }
  }

  // ── Fare cache invalidation ─────────────────────────────────────────────────
  /// Clears cached fares so _ensureBackendEstimates will re-fetch.
  void _invalidateFareCache({String reason = ''}) {
    if (_backendFareByKey.isEmpty && _backendFareLoading.isEmpty) return;
    debugPrint('🔄 Fare cache invalidated: $reason');
    _backendFareByKey.clear();
    _backendFareLoading.clear();
    _priorityPickupByKey.clear();
    _coinsByKey.clear();
    _discountByKey.clear();
    _fareRequestedAtKm = 0;
    _estimatesEverStarted = false; // reset so skeleton shows while re-fetching
  }

  // ── Backend price estimates ─────────────────────────────────────────────────
  /// Called from Consumer<VehicleTypeController> build.
  /// Only fires after route is resolved. Invalidates cache if km changed.
  void _ensureBackendEstimates(List<_VehicleChoice> choices) {
    if (!mounted) return;
    if (!_routeResolved) return;          // wait for true km
    if (_rawDistanceKm <= 0) return;
    if (AppConstant.token.isEmpty) return;

    // Invalidate if km changed significantly since last fetch (>0.3 km diff)
    if (_fareRequestedAtKm > 0 &&
        (_rawDistanceKm - _fareRequestedAtKm).abs() > 0.3) {
      _invalidateFareCache(reason: 'km changed from $_fareRequestedAtKm to $_rawDistanceKm');
    }

    // Mark that estimates have been started (even before HTTP fires)
    // so _fareFor never prematurely shows local fallback
    if (!_estimatesEverStarted) {
      // Only set if there are actually vehicles to estimate for
      final hasVehicles = choices.any((c) => c.backendVehicle != null);
      if (hasVehicles) _estimatesEverStarted = true;
    }

    for (final c in choices) {
      final backend = c.backendVehicle;
      if (backend == null) continue;
      if (_backendFareByKey.containsKey(c.key)) continue;    // already loaded
      if (_backendFareLoading.contains(c.key)) continue;      // in-flight

      _backendFareLoading.add(c.key);
      if (_fareRequestedAtKm == 0) _fareRequestedAtKm = _rawDistanceKm;

      final vehicleTypeId = (backend['_id'] ?? '').toString();
      final subTypes = (backend['sub_types'] as List?) ?? [];
      final subId = subTypes.isNotEmpty ? (subTypes.first['_id'] ?? '').toString() : '';

      final capturedKm = _rawDistanceKm; // capture value for closure
      final body = {
        'vehicleType_id':   vehicleTypeId,
        'subVehicleType_id': subId,
        'pickup_lat':  _effectivePickupLatLng.latitude.toString(),
        'pickup_lng':  _effectivePickupLatLng.longitude.toString(),
        'drop_lat':    _effectiveDropLatLng.latitude.toString(),
        'drop_lng':    _effectiveDropLatLng.longitude.toString(),
        'requested_vehicle_name': c.label,
        'vehicle_key':  c.key,
        'required_tag': c.key,
        'raw_distance_km': capturedKm.toStringAsFixed(3),
      };

      http.post(
        Uri.parse('${AppConstant.apiBaseUrl}booking/price_estimate'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer ${AppConstant.token}',
        },
        body: jsonEncode(body),
      ).then((response) {
        if (!mounted) return;

        // ── KEY FIX: Discard stale response if km changed while in-flight ──
        if ((capturedKm - _rawDistanceKm).abs() > 0.3) {
          debugPrint('⚠️ Discarding stale fare for ${c.key} '
              '(requested at ${capturedKm}km, current ${_rawDistanceKm}km)');
          setState(() => _backendFareLoading.remove(c.key));
          return;
        }

        int total = 0;
        int coins = 0;
        if (response.statusCode >= 200 && response.statusCode < 300) {
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is Map && decoded['success'] == true) {
              final apiData = Map<String, dynamic>.from(decoded['data'] ?? {});
              final pp = apiData['priority_pickup'];
              if (pp is Map) {
                _priorityPickupByKey[c.key] = Map<String, dynamic>.from(pp);
              }
              final pb = apiData['price_breakup'];
              if (pb is Map && pb['estimated_coins'] != null) {
                coins = num.tryParse(pb['estimated_coins'].toString())?.round() ?? 0;
              }
              if (pb is Map) {
                final discountPercent = num.tryParse(pb['discount_percent']?.toString() ?? '') ?? 0;
                final discountAmount = num.tryParse(pb['discount_amount']?.toString() ?? '') ?? 0;
                if (discountPercent > 0 && discountAmount > 0) {
                  _discountByKey[c.key] = {
                    'percent': discountPercent.round(),
                    'amount': discountAmount.round(),
                  };
                } else {
                  _discountByKey.remove(c.key);
                }
              }
              // Prefer total_with_platform_fee (includes GST+platform fee, exact match)
              if (pb is Map && pb['total_with_platform_fee'] != null) {
                total = num.tryParse(pb['total_with_platform_fee'].toString())?.ceil() ?? 0;
              } else {
                // Fallback: delivery fare + platform fee
                final deliveryFare = _extractBackendDeliveryFare(apiData);
                final pf = PlatformFee.forTag(c.key, wheelCount: c.wheelCount);
                total = deliveryFare > 0 ? deliveryFare + pf : 0;
              }
            }
          } catch (e) {
            debugPrint('⚠️ Fare parse error for ${c.key}: $e');
          }
        }

        if (!mounted) return;
        // Batch the state update — mark loaded and store fare in one setState
        setState(() {
          _backendFareLoading.remove(c.key);
          if (total > 0) {
            _backendFareByKey[c.key] = total;
            debugPrint('✅ Backend fare ${c.key}: ₹$total (${capturedKm.toStringAsFixed(2)} km)');
          }
          if (coins > 0) _coinsByKey[c.key] = coins;
        });
      }).catchError((e) {
        debugPrint('⚠️ Fare API error for ${c.key}: $e');
        if (!mounted) return;
        setState(() => _backendFareLoading.remove(c.key));
      });
    }
  }

  /// Extract delivery fare (before platform fee) from API response.
  int _extractBackendDeliveryFare(Map<String, dynamic>? data) {
    if (data == null) return 0;
    final pb = data['price_breakup'];
    for (final v in [
      pb is Map ? pb['total_amount'] : null,
      pb is Map ? pb['subtotal']     : null,
      data['total_amount'],
      data['booking_price'],
    ]) {
      final n = num.tryParse(v?.toString() ?? '');
      if (n != null && n > 0) return n.ceil();
    }
    return 0;
  }

  // ── Fare display logic ──────────────────────────────────────────────────────
  /// Returns the fare to display for a vehicle choice.
  ///
  /// Returns null while the estimate is loading (caller shows skeleton).
  /// Returns backend fare once loaded.
  /// Falls back to local calc ONLY after route resolved AND API failed/timed out.
  int? _fareFor(_VehicleChoice choice) {
    if (choice.backendVehicle == null) return null;

    // Backend fare loaded — use it (SINGLE SOURCE OF TRUTH)
    final backend = _backendFareByKey[choice.key];
    if (backend != null) return backend;

    // Route not resolved yet — no price at all
    if (!_routeResolved) return null;

    // Estimates haven't started yet (brief post-route-resolve window)
    // Return null so skeleton shows instead of local-calc flash
    if (!_estimatesEverStarted) return null;

    // Actively in-flight → skeleton
    if (_backendFareLoading.contains(choice.key)) return null;

    // ── EMERGENCY FALLBACK ONLY ──────────────────────────────────────────
    // API permanently failed (network error, server down, not-in-flight)
    // Use local calc as last resort. This matches backend formula exactly
    // (same slabs, same ceil). Should show ≡ backend if GST=0.
    if (_rawDistanceKm > 0) {
      return FareCalculator.calculate(
        wheelCount:    choice.wheelCount,
        rawDistanceKm: _rawDistanceKm,
        requiredTag:   choice.key,
      ).totalPayable;
    }

    return null;
  }

  /// Returns true while fare is being fetched — shows skeleton instead of price.
  /// Stays true until route is resolved AND all estimates have been attempted.
  bool _isFareLoading(_VehicleChoice choice) {
    if (!_routeResolved) return true;
    // If estimates haven't started yet (brief window between route resolution
    // and first Consumer rebuild), treat as loading to prevent local-calc flash.
    if (!_estimatesEverStarted && choice.backendVehicle != null) return true;
    // Actively in-flight
    if (_backendFareLoading.contains(choice.key)) return true;
    return false;
  }

  double _haversineDistanceKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _degToRad(b.latitude  - a.latitude);
    final dLng = _degToRad(b.longitude - a.longitude);
    final h = math.sin(dLat/2)*math.sin(dLat/2) +
        math.cos(_degToRad(a.latitude))*math.cos(_degToRad(b.latitude))*
        math.sin(dLng/2)*math.sin(dLng/2);
    return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1-h));
  }

  double _degToRad(double d) => d * math.pi / 180.0;

  // ── Multi-drop helpers ──────────────────────────────────────────────────────
  double _totalWaypointKm() {
    final points = [
      _effectivePickupLatLng,
      ..._extraStops.map((s) => s.latLng),
      _effectiveDropLatLng,
    ];
    double total = 0;
    for (int i = 0; i < points.length - 1; i++) {
      total += _haversineDistanceKm(points[i], points[i + 1]);
    }
    return total;
  }

  void _recalcWithStops() {
    // Immediate haversine estimate so the UI updates instantly, then fetch
    // the real driving route through all stops (via _fetchRoute) for the
    // accurate distance the fare is priced on.
    final km = _totalWaypointKm();
    _invalidateFareCache(reason: 'stop added/removed');
    setState(() {
      _rawDistanceKm = km;
      _routeResolved = true;
    });
    _triggerEstimatesAndAutoSelect();
    _fetchRoute();
  }

  /// Removes a stop (by index within `_extraStops`) added on the location
  /// phase. The final drop itself is never removable here — editing it means
  /// just typing a new address in the drop field.
  void _removeStop(int index) {
    setState(() => _extraStops.removeAt(index));
    if (_phase == _Phase.booking) {
      _recalcWithStops();
    }
  }

  Future<void> _showAddStopSheet() async {
    await _loadSavedAddresses(); // pre-load so saved list is ready inside the sheet
    if (!mounted) return;
    final biasLatLng = _phase == _Phase.location
        ? (_wkPickupLatLng ?? widget.pickupLatLng)
        : _effectivePickupLatLng;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddStopSheet(
        pickupLatLng: biasLatLng ?? const LatLng(22.7196, 75.8577),
        savedAddresses: _savedAddresses,
        onStopSelected: (address, latLng) {
          _appendNewStop(address, latLng);
        },
      ),
    );
  }

  /// Appends a newly added stop right before the final drop. Stops are only
  /// editable from the location phase (add/remove, insertion order — no
  /// drag-reorder); once confirmed into the booking phase they're locked in
  /// for the route/fare calc, so the map/marker refresh only fires there.
  void _appendNewStop(String address, LatLng latLng) {
    setState(() {
      _extraStops.add(_ExtraStop(address: address, latLng: latLng));
    });
    if (_phase == _Phase.booking) {
      _recalcWithStops();
    }
  }

  Future<void> _loadSavedAddresses({bool force = false}) async {
    if (_savedAddressesLoaded && !force) return;
    try {
      final data = await getData('user/saved_addresses', context, headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
      });
      if (data != null && data['success'] == true && mounted) {
        setState(() {
          _savedAddresses = List<Map<String, dynamic>>.from(data['data'] ?? []);
          _savedAddressesLoaded = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _doMultiDropBooking(_VehicleChoice choice, int fare, String resolvedSubId) async {
    if (_isBookingMultiDrop) return;
    setState(() => _isBookingMultiDrop = true);
    try {
      final backend = choice.backendVehicle!;
      final allDrops = [
        ..._extraStops.map((s) => {
          'address':       s.address,
          'latitude':      s.latLng.latitude,
          'longitude':     s.latLng.longitude,
          'contact_name':  s.contactName,
          'contact_phone': s.contactPhone,
        }),
        {
          'address':       _effectiveDropAddress,
          'latitude':      _effectiveDropLatLng.latitude,
          'longitude':     _effectiveDropLatLng.longitude,
          'contact_name':  _effectiveDropContactName,
          'contact_phone': _effectiveDropContactPhone,
        },
      ];
      final body = <String, dynamic>{
        'vehicleType_id':         (backend['_id'] ?? '').toString(),
        'subVehicleType_id':      resolvedSubId,
        'pickup_address':         _effectivePickupAddress,
        'pickup_lat':             _effectivePickupLatLng.latitude,
        'pickup_lng':             _effectivePickupLatLng.longitude,
        'drop_address':           _effectiveDropAddress,
        'drop_lat':               _effectiveDropLatLng.latitude,
        'drop_lng':               _effectiveDropLatLng.longitude,
        'sender_name':            _effectivePickupContactName,
        'sender_phone':           _effectivePickupContactPhone,
        'receiver_name':          _effectiveDropContactName,
        'receiver_phone':         _effectiveDropContactPhone,
        'booking_type':           'Now',
        'payment_mode':           'Cash',
        'required_tag':           choice.key,
        'vehicle_key':            choice.key,
        'requested_vehicle_name': choice.label,
        'display_vehicle_name':   choice.label,
        'vehicle_category':       choice.category,
        'raw_distance_km':        double.parse(_rawDistanceKm.toStringAsFixed(3)),
        'is_multidrop':           true,
        'extra_drops':            allDrops,
      };

      final res = await http.post(
        Uri.parse('${AppConstant.apiBaseUrl}booking/create'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${AppConstant.token}'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 20));

      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        final booking = data['data'] as Map<String, dynamic>? ?? {};
        _showMultiDropSuccess(booking, fare, choice);
      } else {
        final msg = (data['message'] is List ? (data['message'] as List).first?.toString() : data['message']?.toString()) ?? 'Booking failed.';
        SnackBarToastMessage.showSnackBar(context, msg);
      }
    } catch (_) {
      if (mounted) SnackBarToastMessage.showSnackBar(context, 'Booking failed. Check connection.');
    } finally {
      if (mounted) setState(() => _isBookingMultiDrop = false);
    }
  }

  void _showMultiDropSuccess(Map<String, dynamic> booking, int fare, _VehicleChoice choice) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60, height: 60,
              decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Color(0xFF2E7D32), size: 32),
            ),
            const SizedBox(height: 14),
            const Text('Booking Confirmed!',
                style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 20, color: AppColor.blackColor)),
            const SizedBox(height: 6),
            Text('Multi-stop delivery booked  •  ${_extraStops.length + 1} drop${_extraStops.length + 1 > 1 ? 's' : ''}',
                style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, color: AppColor.hintTextColor)),
            const SizedBox(height: 4),
            Text('#${(booking['booking_code'] ?? '—').toString()}',
                style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 14, color: AppColor.themeColor)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  int count = 3;
                  Navigator.of(context)
                    ..pop()
                    ..popUntil((route) { count--; return count <= 0 || route.isFirst; });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColor.themeColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Done', style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Vehicle choice builder ──────────────────────────────────────────────────
  Map<String, dynamic>? _findBackendVehicle(List<dynamic> vehicles, int wheelCount, {bool pickup = false}) {
    if (vehicles.isEmpty) return null;
    final clean = vehicles.whereType<Map>()
        .map((v) => Map<String, dynamic>.from(v))
        .where((v) {
          final n = (v['name'] ?? '').toString().toLowerCase();
          return !n.contains('large') && !n.contains('truck');
        }).toList();
    if (clean.isEmpty) {
      final maps = vehicles.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList();
      return maps.isNotEmpty ? maps.first : null;
    }
    final exact = clean.where((v) => _wheelCount((v['name'] ?? '').toString()) == wheelCount).toList();
    if (exact.isNotEmpty) {
      if (pickup) {
        final pickupMatch = exact.where((v) {
          final n = (v['name'] ?? '').toString().toLowerCase();
          return n.contains('pickup') || n.contains('ace') || n.contains('tata') || n.contains('4');
        }).toList();
        if (pickupMatch.isNotEmpty) return pickupMatch.first;
      }
      return exact.first;
    }
    return clean.first;
  }

  int _wheelCount(String name) {
    final n = name.toLowerCase();
    if (n.contains('2') || n.contains('two')  || n.contains('bike') || n.contains('scooter')) return 2;
    if (n.contains('3') || n.contains('three') || n.contains('auto') || n.contains('rickshaw') ||
        n.contains('loader') || n.contains('cng')  || n.contains('electric')) return 3;
    if (n.contains('4') || n.contains('four')  || n.contains('car')  || n.contains('pickup') ||
        n.contains('tata') || n.contains('ace')) return 4;
    return 2;
  }

  List<_VehicleChoice> _buildVehicleChoices(List<dynamic> backendVehicles) {
    if (backendVehicles.isEmpty) return [];

    _VehicleChoice choice({
      required String key,
      required String label,
      required int wheelCount,
      required String category,
      required IconData icon,
      required String imagePath,
      required String dimImagePath,
      required String dimSummary,
      required String dimDesc,
      required String suitableFor,
      String? badge,
      required String eta,
      required String capacity,
      bool pickup = false,
    }) {
      final backend  = _findBackendVehicle(backendVehicles, wheelCount, pickup: pickup);
      final subTypes = (backend?['sub_types'] as List?) ?? [];
      final subId    = subTypes.isNotEmpty ? (subTypes.first['_id'] ?? '').toString() : '';
      return _VehicleChoice(
        key: key,
        label: label,
        backendVehicle: backend,
        subVehicleTypeId: subId,
        wheelCount: wheelCount,
        category: category,
        icon: icon,
        imagePath: imagePath,
        dimImagePath: dimImagePath,
        dimSummary: dimSummary,
        dimDesc: dimDesc,
        suitableFor: suitableFor,
        badge: badge,
        eta: eta,
        capacity: capacity,
      );
    }

    return [
      choice(
        key: 'R_SCOOTER',
        label: 'Scooter',
        wheelCount: 2,
        category: '2-Wheelers',
        icon: Icons.electric_scooter,
        imagePath: AppImage.twowheel,
        dimImagePath: AppImage.dimScooter,
        dimSummary: '40 CM Box • 170 CM',
        dimDesc: 'Box: 40 cm (L) × 40 cm (W) × 40 cm (H), Length: 170 cm',
        suitableFor: 'Documents, food, medicines, parcels up to 20 kg',
        badge: null,
        eta: '11 mins',
        capacity: '20 Kg',
      ),
      choice(
        key: 'R_2W',
        label: 'Bike',
        wheelCount: 2,
        category: '2-Wheelers',
        icon: Icons.two_wheeler,
        imagePath: AppImage.bike,
        dimImagePath: AppImage.dim2Wheeler,
        dimSummary: '40 CM Box • 180 CM',
        dimDesc: 'Box: 40 cm (L) × 45 cm (H), Length: 180 cm',
        suitableFor: 'Documents, food delivery, express packages',
        badge: null,
        eta: '3 mins',
        capacity: '20 kg',
      ),
      choice(
        key: 'R_MINI_3W',
        label: 'Mini 3W',
        wheelCount: 3,
        category: 'Trucks',
        icon: Icons.electric_rickshaw,
        imagePath: AppImage.mini3w,
        dimImagePath: AppImage.dimMini3W,
        dimSummary: '4 FT (H) × 3.5 M × 1.5 M • 5 M',
        dimDesc: 'Cargo: 3.5 m (L) × 1.5 m (W) × 4.0 ft (H), Length: 5.0 m',
        suitableFor: 'Medium boxes, retail parcels, groceries, appliances',
        badge: null,
        eta: '9 mins',
        capacity: '90 Kg',
      ),
      choice(
        key: 'R_E_LOADER',
        label: 'E Loader',
        wheelCount: 3,
        category: 'Trucks',
        icon: Icons.electric_car,
        imagePath: AppImage.eloader,
        dimImagePath: AppImage.dimELoader,
        dimSummary: '4.2 FT × 3 FT × 1 FT',
        dimDesc: 'Cargo: 4.2 ft (L) × 3.0 ft (W) × 1.0 ft (H)',
        suitableFor: 'Electric, eco-friendly cargo, retail cartons, crates',
        badge: null,
        eta: '12 mins',
        capacity: '300 Kg',
      ),
      choice(
        key: 'R_3W',
        label: '3 Wheeler',
        wheelCount: 3,
        category: 'Trucks',
        icon: Icons.airport_shuttle,
        imagePath: AppImage.threewheeler,
        dimImagePath: AppImage.dim3Wheeler,
        dimSummary: '5 FT (H) × 5.5 FT × 4.5 FT',
        dimDesc: 'Cargo: 5.5 ft (L) × 4.5 ft (W) × 5.0 ft (H)',
        suitableFor: 'Heavy retail goods, machinery parts, wholesale goods',
        badge: null,
        eta: '1 mins',
        capacity: '500 kg',
      ),
      choice(
        key: 'R_TATA_ACE',
        label: 'Tata Ace',
        wheelCount: 4,
        category: 'Trucks',
        icon: Icons.local_shipping,
        imagePath: AppImage.minitruck,
        dimImagePath: AppImage.dimTataAce,
        dimSummary: '5.5 FT (H) × 7 FT × 4.5 FT',
        dimDesc: 'Bed: 7.0 ft (L) × 4.5 ft (W) × 5.5 ft (H)',
        suitableFor: 'Full commercial loads, house shifting, heavy machinery',
        badge: null,
        eta: '2 mins',
        capacity: '750 kg',
        pickup: true,
      ),
    ];
  }

  void _autoSelect(List<_VehicleChoice> choices) {
    if (_selectedKey != null || choices.isEmpty) return;
    final hint     = (widget.preSelectedVehicleName ?? '').toLowerCase();
    final selected = choices.firstWhere(
      (c) => c.key == hint || c.label.toLowerCase() == hint,
      orElse: () => choices.first,
    );
    Future.microtask(() {
      if (mounted && _selectedKey == null) setState(() => _selectedKey = selected.key);
    });
  }

  // ── Book action ─────────────────────────────────────────────────────────────
  // Toggles the "more vehicles below" hint based on how far the vehicle
  // list's scroll position is from its end. Guarded with a value check so
  // it doesn't setState on every scroll frame once the state is settled.
  void _updateHasMoreVehiclesBelow(ScrollMetrics metrics) {
    final hasMore = metrics.maxScrollExtent > 0 &&
        metrics.pixels < metrics.maxScrollExtent - 4;
    if (hasMore == _hasMoreVehiclesBelow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _hasMoreVehiclesBelow = hasMore);
    });
  }

  void _onBook(_VehicleChoice choice) {
    final backend = choice.backendVehicle;
    if (backend == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle setup is incomplete. Please check backend vehicle/sub-vehicle data.')),
      );
      return;
    }

    String resolvedSubId = choice.subVehicleTypeId;
    if (resolvedSubId.isEmpty) {
      final subTypes = (backend['sub_types'] as List?) ?? [];
      if (subTypes.isNotEmpty) resolvedSubId = (subTypes.first['_id'] ?? '').toString();
    }
    if (resolvedSubId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle sub-type missing. Please add sub-types in admin panel.')),
      );
      return;
    }

    // Only navigate if we have a resolved fare — prevents booking with ₹0
    final fare = _fareFor(choice);
    if (fare == null || fare <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fare is being calculated. Please wait a moment.')),
      );
      return;
    }

    final vehicleData = {
      'name':               choice.label,
      'baseVehicleName':    backend['name'],
      'wheelCount':         choice.wheelCount,
      'vehicleCategory':    choice.category,
      'pricingModifier':    1.0,
      'vehicleKey':         choice.key,
      'requiredTag':        choice.key,
      'displayVehicleName': choice.label,
      'bookingFlow':        'retailer',
      'priorityPickup':     _priorityPickupByKey[choice.key],
      'estimatedCoins':     _coinsByKey[choice.key] ?? 0,
      'firstRideDiscount':  _discountByKey[choice.key],
    };

    // Picker mode: return vehicle selection to the caller (RetailerConfirmScreen)
    if (widget.onVehicleSelected != null) {
      widget.onVehicleSelected!({
        'vehicleTypeId':    (backend['_id'] ?? '').toString(),
        'subVehicleTypeId': resolvedSubId,
        'vehicleData':      vehicleData,
        'rawDistanceKm':    _rawDistanceKm,
        'estimatedFare':    fare,
      });
      if (mounted) Navigator.pop(context);
      return;
    }

    // Pickup contact defaults to the retailer's own registered number when no
    // specific contact was carried forward from the location step (they're
    // usually the one at the pickup point). Drop contact is NEVER defaulted —
    // it's who the driver actually hands the delivery to, so the retailer
    // must fill it in themselves on the confirm screen.
    String pickupContactName  = _effectivePickupContactName;
    String pickupContactPhone = _effectivePickupContactPhone;
    String dropContactName    = _effectiveDropContactName;
    String dropContactPhone   = _effectiveDropContactPhone;
    if (pickupContactName.isEmpty || pickupContactPhone.isEmpty) {
      final user = Provider.of<UserController>(context, listen: false);
      pickupContactName  = user.getUserName;
      pickupContactPhone = _cleanPhone(user.getUserMobile);
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewConfirmScreen(
          vehicleTypeId:    (backend['_id'] ?? '').toString(),
          subVehicleTypeId: resolvedSubId,
          vehicleData:      vehicleData,
          pickupData: {
            'lat':     _effectivePickupLatLng.latitude,
            'lng':     _effectivePickupLatLng.longitude,
            'address': _effectivePickupAddress,
          },
          dropData: {
            'lat':     _effectiveDropLatLng.latitude,
            'lng':     _effectiveDropLatLng.longitude,
            'address': _effectiveDropAddress,
          },
          rawDistanceKm: _rawDistanceKm,
          estimatedFare: fare,
          subVehicleTypeList: (backend['sub_types'] as List?) ?? [],
          bookingType: 'Now',
          pickupDate: '',
          pickupSlot: '',
          pickupContactName:  pickupContactName,
          pickupContactPhone: pickupContactPhone,
          dropContactName:  dropContactName,
          dropContactPhone: dropContactPhone,
          extraStops: _extraStops.map((s) => {
            'address':       s.address,
            'lat':           s.latLng.latitude,
            'lng':           s.latLng.longitude,
            'contact_name':  s.contactName,
            'contact_phone': s.contactPhone,
          }).toList(),
        ),
      ),
    );
  }

  /// Strips a phone number down to its bare 10 digits (drops country code /
  /// leading zero), matching the cleanup the old contact-info wizard did.
  String _cleanPhone(String raw) {
    var phone = raw.replaceAll(RegExp(r'\D'), '');
    if (phone.length > 10) {
      if (phone.startsWith('91')) {
        phone = phone.substring(2);
      } else if (phone.startsWith('0')) {
        phone = phone.substring(1);
      }
    }
    if (phone.length > 10) phone = phone.substring(phone.length - 10);
    return phone;
  }

  // ── Location phase: reorderable route card (pickup + stops + drop) ──────────
  /// Small vertical connector shown below a rail dot/pin, linking it to the
  /// next row — gives the list the "route timeline" look.
  Widget _locRailConnector(Widget dot, bool showLine) {
    return Column(
      children: [
        dot,
        if (showLine) Container(width: 2, height: 26, color: const Color(0xFFE2E8F0)),
      ],
    );
  }

  Widget _locReorderRow({
    required Key key,
    required bool isPickup,
    required int number,
    required String address,
    required bool showLine,
    required int dragIndex,
    VoidCallback? onRemove,
  }) {
    final dot = isPickup
        ? Container(width: 14, height: 14, margin: const EdgeInsets.all(4),
            decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle))
        : Container(
            width: 22, height: 22,
            decoration: const BoxDecoration(color: Color(0xFFE53935), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('$number', style: const TextStyle(fontFamily: AppFont.fontFamily, color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          );
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _locRailConnector(dot, showLine),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(address, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, color: AppColor.blackColor)),
                  ),
                  ReorderableDragStartListener(
                    index: dragIndex,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.drag_handle_rounded, size: 18, color: AppColor.hintTextColor),
                    ),
                  ),
                  if (onRemove != null)
                    GestureDetector(
                      onTap: onRemove,
                      child: const Padding(padding: EdgeInsets.only(left: 2), child: Icon(Icons.close_rounded, size: 17, color: AppColor.hintTextColor)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Reorders pickup + stops + (resolved) drop — drag any into any position.
  /// Whichever ends up first becomes pickup, whichever ends up last becomes
  /// drop. `shownList` is the exact list currently rendered by
  /// [_buildRouteOrderCard] (may or may not include drop, depending on
  /// whether it's resolved yet).
  void _reorderLocationList(int oldIndex, int newIndex, List<_ExtraStop> shownList) {
    if (newIndex > oldIndex) newIndex--;
    final list = List<_ExtraStop>.from(shownList);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    setState(() {
      _wkPickupAddress      = list.first.address;
      _wkPickupLatLng       = list.first.latLng;
      _wkPickupContactName  = list.first.contactName;
      _wkPickupContactPhone = list.first.contactPhone;
      _pickupCtrl.text      = list.first.address;

      if (list.length > 1) {
        _wkDropAddress       = list.last.address;
        _wkDropLatLng        = list.last.latLng;
        _wkDropContactName   = list.last.contactName;
        _wkDropContactPhone  = list.last.contactPhone;
        _dropCtrl.text       = list.last.address;
        _extraStops
          ..clear()
          ..addAll(list.sublist(1, list.length - 1));
      } else {
        _extraStops.clear();
      }
    });
  }

  /// Drag-to-reorder card for pickup + stops + drop — shown once at least
  /// one stop has been added, letting the user swap any of them (including
  /// pickup/drop) into any order, same as the old map-phase location bar.
  Widget _buildRouteOrderCard() {
    if (_wkPickupLatLng == null || _extraStops.isEmpty) return const SizedBox.shrink();
    final dropResolved = _wkDropLatLng != null && _wkDropAddress.isNotEmpty;
    final locations = <_ExtraStop>[
      _ExtraStop(address: _wkPickupAddress, latLng: _wkPickupLatLng!, contactName: _wkPickupContactName, contactPhone: _wkPickupContactPhone),
      ..._extraStops,
      if (dropResolved)
        _ExtraStop(address: _wkDropAddress, latLng: _wkDropLatLng!, contactName: _wkDropContactName, contactPhone: _wkDropContactPhone),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColor.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8, left: 2),
            child: Text('Drag to reorder your route',
                style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11, fontWeight: FontWeight.w600, color: AppColor.hintTextColor)),
          ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            proxyDecorator: (child, index, animation) => Material(color: Colors.transparent, child: child),
            onReorder: (oldIndex, newIndex) => _reorderLocationList(oldIndex, newIndex, locations),
            itemCount: locations.length,
            itemBuilder: (context, i) {
              final loc = locations[i];
              final isPickup = i == 0;
              final isDrop = dropResolved && i == locations.length - 1;
              return _locReorderRow(
                key: ValueKey('route_${loc.address}_$i'),
                isPickup: isPickup,
                number: i,
                address: loc.address,
                showLine: i != locations.length - 1,
                dragIndex: i,
                onRemove: isPickup
                    ? null
                    : isDrop
                        ? () => setState(() {
                              _wkDropLatLng = null;
                              _wkDropAddress = '';
                              _dropCtrl.clear();
                            })
                        : () => _removeStop(i - 1),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── BUILD ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !(_phase == _Phase.booking && _canReturnToLocationPhase),
      onPopInvoked: (didPop) {
        if (!didPop && _phase == _Phase.booking && _canReturnToLocationPhase) {
          setState(() => _phase = _Phase.location);
        }
      },
      child: _phase == _Phase.booking ? _buildBookingPhase(context) : _buildLocationPhase(context),
    );
  }

  Widget _buildPickupSummaryPill() {
    final hasContact = _wkPickupContactName.isNotEmpty || _wkPickupContactPhone.isNotEmpty;
    return GestureDetector(
      onTap: () {
        setState(() => _locActiveField = "pickup");
        WidgetsBinding.instance.addPostFrameCallback((_) => _pickupFocus.requestFocus());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColor.borderColor),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: AppColor.greenColor.withOpacity(0.12), shape: BoxShape.circle),
              child: const Icon(Icons.arrow_upward_rounded, color: AppColor.greenColor, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasContact
                        ? [_wkPickupContactName, _wkPickupContactPhone]
                            .where((s) => s.isNotEmpty)
                            .join(' · ')
                        : 'Pickup location',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColor.fontColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _wkPickupAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 12,
                      color: AppColor.hintTextColor,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColor.hintTextColor, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentLocationCard(Map<String, dynamic> recent) {
    final address = (recent['address'] ?? '').toString();
    final parts = address.split(',');
    final title = parts.isNotEmpty && parts.first.trim().isNotEmpty ? parts.first.trim() : address;
    final subtitle = parts.length > 1 ? parts.skip(1).join(',').trim() : '';
    final contactName = (recent['contact_name'] ?? '').toString();
    final saved = _isAddressSaved(address);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColor.borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppColor.themeColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.history_rounded, color: AppColor.themeColor, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _selectRecentLocation(recent),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppFont.fontFamily,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColor.fontColor,
                            ),
                          ),
                        ),
                        if (contactName.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColor.themeColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person_rounded, size: 10, color: AppColor.themeColor),
                                const SizedBox(width: 3),
                                Text(
                                  contactName.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: AppFont.fontFamily,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColor.themeColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontSize: 11.5,
                          color: AppColor.hintTextColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: saved ? null : () => _quickSaveRecent(recent),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: 17,
                  color: saved ? AppColor.redColor : AppColor.hintTextColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Phase 1: Location search (pickup/drop, stops, saved addresses) ──────────
  Widget _buildLocationPhase(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            children: [
              // ── AppBar row ───────────────────────────────────────────
              Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.04, vertical: 10),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _handleBack,
                      child: Container(
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                          color: AppColor.themeColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: AppColor.themeColor, size: 18),
                      ),
                    ),
                    SizedBox(width: size.width * 0.03),
                    const Text(
                      "Choose Location",
                      style: TextStyle(
                        fontFamily: AppFont.fontFamily,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        color: AppColor.blackColor,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Pickup: collapses to a summary pill once resolved ──────
              Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.04),
                child: (_wkPickupLatLng != null &&
                        _wkPickupAddress.isNotEmpty &&
                        _locActiveField != "pickup")
                    ? _buildPickupSummaryPill()
                    : Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _locActiveField == "pickup"
                                ? AppColor.themeColor.withOpacity(0.5)
                                : AppColor.borderColor,
                            width: _locActiveField == "pickup" ? 1.4 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: _LocationField(
                          controller: _pickupCtrl,
                          focusNode: _pickupFocus,
                          hint: "Pickup location",
                          dotColor: AppColor.greenColor,
                          icon: Icons.arrow_upward_rounded,
                          isActive: _locActiveField == "pickup",
                          onChanged: (v) {
                            setState(() {
                              _wkPickupAddress = v;
                              _wkPickupLatLng = null;
                              _wkPickupContactName = '';
                              _wkPickupContactPhone = '';
                            });
                            _onLocationSearchChanged(v);
                          },
                          onClear: () {
                            _pickupCtrl.clear();
                            _wkPickupAddress = "";
                            _wkPickupLatLng = null;
                            _wkPickupContactName = '';
                            _wkPickupContactPhone = '';
                            if (mounted) setState(() => _locSuggestions = []);
                          },
                          trailing: _currentLocationTrailingButton("pickup"),
                        ),
                      ),
              ),

              const SizedBox(height: 8),

              // ── Drop: always an active input, Porter-style ─────────────
              Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.04),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _locActiveField == "drop"
                          ? AppColor.themeColor.withOpacity(0.5)
                          : AppColor.borderColor,
                      width: _locActiveField == "drop" ? 1.4 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _LocationField(
                          controller: _dropCtrl,
                          focusNode: _dropFocus,
                          hint: "Where is your drop?",
                          dotColor: AppColor.redColor,
                          icon: Icons.location_on_rounded,
                          isActive: _locActiveField == "drop",
                          onChanged: (v) {
                            setState(() {
                              _wkDropAddress = v;
                              _wkDropLatLng = null;
                              _wkDropContactName = '';
                              _wkDropContactPhone = '';
                            });
                            _onLocationSearchChanged(v);
                          },
                          onClear: () {
                            _dropCtrl.clear();
                            _wkDropAddress = "";
                            _wkDropLatLng = null;
                            _wkDropContactName = '';
                            _wkDropContactPhone = '';
                            if (mounted) setState(() => _locSuggestions = []);
                          },
                          trailing: _currentLocationTrailingButton("drop"),
                        ),
                      ),
                      if (_wkPickupLatLng != null || _wkDropLatLng != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: _swapLocations,
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColor.themeColor.withOpacity(0.35)),
                              ),
                              child: const Icon(Icons.swap_vert_rounded, color: AppColor.themeColor, size: 16),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Select on map / Saved addresses / Add stop ────────────
              Padding(
                padding: EdgeInsets.fromLTRB(size.width * 0.04, 10, size.width * 0.04, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _PillActionButton(
                        icon: Icons.map_outlined,
                        label: 'Select on map',
                        onTap: _openMapForActiveField,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PillActionButton(
                        icon: Icons.bookmark_outlined,
                        label: 'Saved addresses',
                        onTap: _showLocationSavedAddressSheet,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PillActionButton(
                        icon: Icons.add_location_alt_outlined,
                        label: 'Add stop',
                        onTap: _showAddStopSheet,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Inline map: drag to pin-point the active field exactly ──
              Padding(
                padding: EdgeInsets.fromLTRB(size.width * 0.04, 12, size.width * 0.04, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _locActiveField == 'pickup'
                              ? Icons.trip_origin_rounded
                              : Icons.place_rounded,
                          size: 14,
                          color: _locActiveField == 'pickup'
                              ? AppColor.greenColor
                              : AppColor.redColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _locActiveField == 'pickup'
                              ? 'Drag the map to set your pickup'
                              : 'Drag the map to set your drop',
                          style: const TextStyle(
                            fontFamily: AppFont.fontFamily,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: AppColor.hintTextColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 210,
                        child: Stack(
                          children: [
                            _DraggableMapPin(
                              key: _locMapKey,
                              requireUserMove: true,
                              initialLatLng: _wkPickupLatLng ??
                                  _wkDropLatLng ??
                                  const LatLng(22.7196, 75.8577),
                              zoom: 15,
                              pinColor: _locActiveField == 'pickup'
                                  ? AppColor.greenColor
                                  : AppColor.redColor,
                              onCameraIdle: _onLocationMapIdle,
                            ),
                            if (_locMapGeocoding)
                              Positioned(
                                top: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.12),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: const SizedBox(
                                    height: 14,
                                    width: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColor.themeColor,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.place_rounded,
                            size: 14, color: AppColor.themeColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _locMapGeocoding
                                ? 'Locating address…'
                                : (() {
                                    final a = _locActiveField == 'pickup'
                                        ? _wkPickupAddress
                                        : _wkDropAddress;
                                    return a.isEmpty
                                        ? 'Move the map to choose a point'
                                        : a;
                                  })(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppFont.fontFamily,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColor.blackColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Use Current Location ──
              if (_locActiveField == "pickup")
                InkWell(
                  onTap: _useCurrentLocation,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: size.width * 0.04, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          height: 36, width: 36,
                          decoration: BoxDecoration(
                            color: AppColor.themeColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _isFetchingCurrentLocation
                              ? const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColor.themeColor),
                                )
                              : const Icon(Icons.my_location_rounded, color: AppColor.themeColor, size: 20),
                        ),
                        SizedBox(width: size.width * 0.03),
                        const Text('Use current location',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColor.themeColor)),
                      ],
                    ),
                  ),
                ),

              // ── Reorderable route (pickup + stops + drop) ─────────────
              _buildRouteOrderCard(),

              // ── Recent locations — carries the contact used there last ──
              Builder(builder: (_) {
                final isPickupField = _locActiveField == "pickup";
                final activeText = isPickupField ? _pickupCtrl.text : _dropCtrl.text;
                final recents = isPickupField ? _recentPickups : _recentDrops;
                if (_locSuggestions.isNotEmpty || activeText.isNotEmpty || recents.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(size.width * 0.04, 12, size.width * 0.04, 6),
                      child: const Text('RECENT LOCATIONS',
                          style: TextStyle(
                            fontFamily: AppFont.fontFamily,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: AppColor.hintTextColor,
                          )),
                    ),
                    ...recents.take(6).map((r) => _buildRecentLocationCard(r)),
                  ],
                );
              }),

              // ── Suggestions list ──────────────────────────────────────
              if (_isLoadingSuggestions)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      height: 22, width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColor.themeColor),
                    ),
                  ),
                )
              else if (_locSuggestions.isNotEmpty)
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: size.height * 0.3),
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: _locSuggestions.length,
                    itemBuilder: (_, i) {
                      final s = _locSuggestions[i];
                      final mainText = s['main_text'] as String;
                      final secondaryText = s['secondary_text'] as String;
                      return InkWell(
                        onTap: () => _onLocationSuggestionTap(s),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: size.width * 0.04, vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                height: 34, width: 34,
                                decoration: BoxDecoration(
                                  color: AppColor.themeColor.withOpacity(0.07),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.location_on_outlined, color: AppColor.themeColor, size: 18),
                              ),
                              SizedBox(width: size.width * 0.03),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      mainText.isNotEmpty ? mainText : (s['description'] as String),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: AppFont.fontFamily,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13,
                                        color: AppColor.blackColor,
                                      ),
                                    ),
                                    if (secondaryText.isNotEmpty)
                                      Text(
                                        secondaryText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: AppFont.fontFamily,
                                          fontWeight: FontWeight.w400,
                                          fontSize: 12,
                                          color: AppColor.hintTextColor,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                )
              else
                const SizedBox.shrink(),

              // ── Confirm button ────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                    size.width * 0.045, size.height * 0.01, size.width * 0.045, size.height * 0.02),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _canConfirmLocation ? _confirmLocation : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColor.themeColor,
                      disabledBackgroundColor: AppColor.greyLightColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text(
                      "Confirm Locations",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Phase 2: Vehicle selection screen (Redesigned with Parcel/Cargo Size Graphics) ──
  Widget _buildBookingPhase(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Consumer<VehicleTypeController>(
        builder: (context, vc, _) {
          final choices = _buildVehicleChoices(vc.vehicleTypes);
          _ensureBackendEstimates(choices);
          final selectedChoice = choices.firstWhere(
            (c) => c.key == _selectedKey,
            orElse: () => choices.isNotEmpty ? choices.first : _VehicleChoice.empty(),
          );
          final selectedFare    = _fareFor(selectedChoice);
          final selectedLoading = _isFareLoading(selectedChoice);

          return SafeArea(
            child: Column(
              children: [
                // ── Header: Back + Select Vehicle ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 16, 6),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _handleBack,
                        child: Container(
                          height: 40,
                          width: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Color(0xFF0F172A),
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Select Vehicle',
                          style: TextStyle(
                            fontFamily: AppFont.fontFamily,
                            fontWeight: FontWeight.w700,
                            fontSize: 19,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Pickup → drop summary card with Swap & Stop actions ──
                _buildBookingLocationCard(),

                // ── Vehicle list sheet ──
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x0A000000),
                          blurRadius: 10,
                          offset: Offset(0, -3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Drag handle pill
                        Center(
                          child: Container(
                            margin: const EdgeInsets.only(top: 10, bottom: 6),
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),

                        Expanded(
                          child: vc.isLoading && choices.isEmpty
                              ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E6BFF)))
                              : choices.isEmpty
                                  ? const Center(child: Text('No vehicles found', style: TextStyle(fontFamily: AppFont.fontFamily)))
                                  : ListView.builder(
                                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                                      itemCount: choices.length,
                                      itemBuilder: (context, index) {
                                        final c = choices[index];
                                        final isSelected = c.key == _selectedKey;
                                        final fare = _fareFor(c);
                                        final loading = _isFareLoading(c);

                                        return GestureDetector(
                                          onTap: () => setState(() => _selectedKey = c.key),
                                          child: isSelected
                                              ? _buildSelectedVehicleCard(c, fare, loading)
                                              : _buildUnselectedVehicleTile(c, fare, loading),
                                        );
                                      },
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Fixed footer — Proceed button ──
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, -3)),
                    ],
                  ),
                  padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: selectedChoice.backendVehicle != null &&
                              !_isLoadingRoute &&
                              !selectedLoading &&
                              selectedFare != null &&
                              selectedFare > 0
                          ? () => _onBook(selectedChoice)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColor.themeColor,
                        disabledBackgroundColor: const Color(0xFFCBD5E1),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: selectedLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                            )
                          : Text(
                              selectedChoice.backendVehicle != null && selectedFare != null && selectedFare > 0
                                  ? 'Proceed With ${selectedChoice.label}'
                                  : selectedChoice.backendVehicle == null
                                      ? 'Select a Vehicle'
                                      : 'Calculating fare...',
                              style: const TextStyle(
                                fontFamily: AppFont.fontFamily,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // 3D Bookmark Ribbon Badge — hangs from behind the top edge of each card.
  Widget _build3DBookmark(_VehicleChoice c) {
    final rawCoins = _coinsByKey[c.key] ?? 0;
    final maxCoins = rawCoins > 0 ? (rawCoins + 5) : 15;
    return _Animated3DBookmark(coins: maxCoins);
  }

  Widget _buildSelectedVehicleCard(_VehicleChoice c, int? fare, bool loading) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1E6BFF), width: 1.8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E6BFF).withOpacity(0.08),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF3F8FF), Colors.white],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Vehicle Dimension Illustration (Enlarged)
              Container(
                height: 195,
                width: double.infinity,
                alignment: Alignment.center,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    c.dimImagePath,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Image.asset(c.imagePath, height: 110, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Bottom info row: Title (i) + capacity • ETA on left, Fare on right
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              c.label,
                              style: const TextStyle(
                                fontFamily: AppFont.fontFamily,
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => _showVehicleSpecsModal(c),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                child: const Icon(
                                  Icons.info_outline_rounded,
                                  size: 16,
                                  color: Color(0xFF1E6BFF),
                                ),
                              ),
                            ),
                            if (c.badge != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF5722),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  c.badge!,
                                  style: const TextStyle(
                                    fontFamily: AppFont.fontFamily,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 9,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${c.capacity} • ${c.eta}',
                          style: const TextStyle(
                            fontFamily: AppFont.fontFamily,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        if (c.backendVehicle == null)
                          const Text(
                            'Backend vehicle missing',
                            style: TextStyle(
                              fontFamily: AppFont.fontFamily,
                              fontSize: 10,
                              color: AppColor.redColor,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Fare
                  loading
                      ? const _FareSkeleton(selected: true)
                      : _fareBlock(c, fare, selected: true),
                ],
              ),
            ],
          ),
        ),

        // 3D Bookmark Ribbon coming from behind the right edge of the card
        Positioned(
          top: 14,
          right: -4,
          child: _build3DBookmark(c),
        ),
      ],
    );
  }

  /// Fare display for a vehicle tile. When the retailer is eligible for the
  /// first-ride offer (backend flags it per vehicle in `_discountByKey`), the
  /// pre-discount total is struck through and a "X% OFF" pill sits beside the
  /// discounted rate — same treatment as the confirm screen.
  Widget _fareBlock(_VehicleChoice c, int? fare, {required bool selected}) {
    final bool hasFare = fare != null && fare > 0;
    final disc = _discountByKey[c.key];
    final int amount = (disc?['amount'] as num?)?.toInt() ?? 0;
    final int percent = (disc?['percent'] as num?)?.toInt() ?? 0;
    final bool showDisc = hasFare && disc != null && amount > 0;

    final TextStyle mainStyle = TextStyle(
      fontFamily: AppFont.fontFamily,
      fontWeight: FontWeight.w800,
      fontSize: selected ? 20 : 16,
      color: const Color(0xFF0F172A),
    );

    if (!showDisc) {
      return Text(hasFare ? '₹$fare' : '—', style: mainStyle);
    }

    final int original = (fare ?? 0) + amount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '₹$original',
          style: TextStyle(
            fontFamily: AppFont.fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: selected ? 12 : 10.5,
            color: const Color(0xFF94A3B8),
            decoration: TextDecoration.lineThrough,
          ),
        ),
        const SizedBox(height: 1),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('₹$fare', style: mainStyle),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$percent% OFF',
                style: const TextStyle(
                  fontFamily: AppFont.fontFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: 9.5,
                  color: Color(0xFF16A34A),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUnselectedVehicleTile(_VehicleChoice c, int? fare, bool loading) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Vehicle icon / image
              Container(
                width: 70,
                height: 52,
                alignment: Alignment.center,
                child: Image.asset(
                  c.imagePath,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(c.icon, size: 30, color: AppColor.hintTextColor),
                ),
              ),
              const SizedBox(width: 10),

              // Label, capacity, ETA
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          c.label,
                          style: const TextStyle(
                            fontFamily: AppFont.fontFamily,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        if (c.badge != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF5722),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              c.badge!,
                              style: const TextStyle(
                                fontFamily: AppFont.fontFamily,
                                fontWeight: FontWeight.w800,
                                fontSize: 9,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${c.capacity} • ${c.eta}',
                      style: const TextStyle(
                        fontFamily: AppFont.fontFamily,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    if (c.backendVehicle == null)
                      const Text(
                        'Backend vehicle missing',
                        style: TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontSize: 10,
                          color: AppColor.redColor,
                        ),
                      ),
                  ],
                ),
              ),

              // Fare
              loading
                  ? const _FareSkeleton(selected: false)
                  : _fareBlock(c, fare, selected: false),
            ],
          ),
        ),

        // 3D Bookmark Ribbon coming from behind the right edge of the card
        Positioned(
          top: 6,
          right: -4,
          child: _build3DBookmark(c),
        ),
      ],
    );
  }

  void _showVehicleSpecsModal(_VehicleChoice choice) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${choice.label} Specifications',
                    style: const TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 120,
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Image.asset(
                  choice.dimImagePath,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Image.asset(choice.imagePath, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 16),
              _buildSpecItem(
                icon: Icons.fitness_center_rounded,
                title: 'Max Payload Capacity',
                value: choice.capacity,
              ),
              const SizedBox(height: 10),
              _buildSpecItem(
                icon: Icons.straighten_rounded,
                title: 'Cargo Dimensions',
                value: choice.dimDesc,
              ),
              const SizedBox(height: 10),
              _buildSpecItem(
                icon: Icons.inventory_2_outlined,
                title: 'Best Suited For',
                value: choice.suitableFor,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _selectedKey = choice.key);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E6BFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    'Select ${choice.label}',
                    style: const TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSpecItem({required IconData icon, required String title, required String value}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E6BFF).withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF1E6BFF)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppFont.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: AppFont.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _swapBookingLocations() {
    setState(() {
      final tmpAddr = _effectivePickupAddress;
      final tmpLatLng = _effectivePickupLatLng;
      final tmpName = _effectivePickupContactName;
      final tmpPhone = _effectivePickupContactPhone;

      _effectivePickupAddress = _effectiveDropAddress;
      _effectivePickupLatLng = _effectiveDropLatLng;
      _effectivePickupContactName = _effectiveDropContactName;
      _effectivePickupContactPhone = _effectiveDropContactPhone;

      _effectiveDropAddress = tmpAddr;
      _effectiveDropLatLng = tmpLatLng;
      _effectiveDropContactName = tmpName;
      _effectiveDropContactPhone = tmpPhone;

      _invalidateFareCache(reason: 'locations swapped');
      _isLoadingRoute = true;
      _routeResolved = false;
    });
    _fetchRoute();
  }

  // "Add / Manage Stops" on the vehicle-selection screen → dedicated route
  // manager page. Confirm returns the reordered [pickup, ...stops, drop]
  // list; we re-derive effective pickup/drop + _extraStops and re-price.
  Future<void> _openStopManager() async {
    await _loadSavedAddresses();
    if (!mounted) return;

    final initial = <Map<String, dynamic>>[
      {
        'address':       _effectivePickupAddress,
        'lat':           _effectivePickupLatLng.latitude,
        'lng':           _effectivePickupLatLng.longitude,
        'contact_name':  _effectivePickupContactName,
        'contact_phone': _effectivePickupContactPhone,
      },
      ..._extraStops.map((s) => {
            'address':       s.address,
            'lat':           s.latLng.latitude,
            'lng':           s.latLng.longitude,
            'contact_name':  s.contactName,
            'contact_phone': s.contactPhone,
          }),
      {
        'address':       _effectiveDropAddress,
        'lat':           _effectiveDropLatLng.latitude,
        'lng':           _effectiveDropLatLng.longitude,
        'contact_name':  _effectiveDropContactName,
        'contact_phone': _effectiveDropContactPhone,
      },
    ];

    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => StopManagerScreen(
          initialPoints: initial,
          savedAddresses: _savedAddresses,
        ),
      ),
    );
    if (result == null || result.length < 2 || !mounted) return;
    _applyRoutePoints(result);
  }

  void _applyRoutePoints(List<Map<String, dynamic>> pts) {
    LatLng ll(Map m) =>
        LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
    final first = pts.first;
    final last = pts.last;
    setState(() {
      _effectivePickupAddress      = (first['address'] ?? '').toString();
      _effectivePickupLatLng       = ll(first);
      _effectivePickupContactName  = (first['contact_name'] ?? '').toString();
      _effectivePickupContactPhone = (first['contact_phone'] ?? '').toString();
      _effectiveDropAddress        = (last['address'] ?? '').toString();
      _effectiveDropLatLng         = ll(last);
      _effectiveDropContactName    = (last['contact_name'] ?? '').toString();
      _effectiveDropContactPhone   = (last['contact_phone'] ?? '').toString();
      _extraStops
        ..clear()
        ..addAll(pts.sublist(1, pts.length - 1).map((m) => _ExtraStop(
              address: (m['address'] ?? '').toString(),
              latLng: ll(m),
              contactName: (m['contact_name'] ?? '').toString(),
              contactPhone: (m['contact_phone'] ?? '').toString(),
            )));
      _haversineKm = _haversineDistanceKm(_effectivePickupLatLng, _effectiveDropLatLng);
    });
    _recalcWithStops();
  }

  // Pickup → drop summary shown above the vehicle list on the vehicle screen.
  Widget _buildBookingLocationCard() {
    final user = Provider.of<UserController>(context, listen: false);
    final defaultName = user.getUserName.isNotEmpty ? user.getUserName : 'Retailer';
    final defaultPhone = user.getUserMobile.isNotEmpty ? _cleanPhone(user.getUserMobile) : '';

    final pickupContact = _effectivePickupContactName.isNotEmpty
        ? '$_effectivePickupContactName · ${_effectivePickupContactPhone.isNotEmpty ? _effectivePickupContactPhone : defaultPhone}'
        : (defaultName.isNotEmpty ? '$defaultName · $defaultPhone' : 'Pickup Details');

    final dropContact = _effectiveDropContactName.isNotEmpty
        ? '$_effectiveDropContactName · ${_effectiveDropContactPhone.isNotEmpty ? _effectiveDropContactPhone : defaultPhone}'
        : (defaultName.isNotEmpty ? '$defaultName · $defaultPhone' : 'Drop Details');

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Pickup Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4CAF50),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pickupContact,
                                  style: const TextStyle(
                                    fontFamily: AppFont.fontFamily,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF64748B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _effectivePickupAddress,
                                  style: const TextStyle(
                                    fontFamily: AppFont.fontFamily,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Connector — plain line, or a "N stops in between" pill
                      // when this is a multi-drop route.
                      if (_extraStops.isEmpty)
                        Container(
                          margin: const EdgeInsets.only(left: 4.5),
                          height: 16,
                          width: 1.5,
                          color: const Color(0xFFCBD5E1),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                margin: const EdgeInsets.only(left: 4.5),
                                height: 12,
                                width: 1.5,
                                color: const Color(0xFFCBD5E1),
                              ),
                              const SizedBox(width: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF4FF),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFFBFD4FF)),
                                ),
                                child: Text(
                                  '${_extraStops.length} stop${_extraStops.length > 1 ? 's' : ''} in between',
                                  style: const TextStyle(
                                    fontFamily: AppFont.fontFamily,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1E6BFF),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Drop Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dropContact,
                                  style: const TextStyle(
                                    fontFamily: AppFont.fontFamily,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF64748B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _effectiveDropAddress,
                                  style: const TextStyle(
                                    fontFamily: AppFont.fontFamily,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Swap Button
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _swapBookingLocations,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Icon(
                      Icons.swap_vert_rounded,
                      color: Color(0xFF1E293B),
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // Action Buttons: Add/Manage Stops | Edit Locations
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _openStopManager,
                    borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_circle_rounded, size: 16, color: Color(0xFF1E6BFF)),
                          const SizedBox(width: 6),
                          Text(
                            _extraStops.isEmpty ? 'Add Stop' : 'Manage Stops',
                            style: const TextStyle(
                              fontFamily: AppFont.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E6BFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1, color: Color(0xFFF1F5F9)),
                Expanded(
                  child: InkWell(
                    onTap: _canReturnToLocationPhase
                        ? () => setState(() => _phase = _Phase.location)
                        : null,
                    borderRadius: const BorderRadius.only(bottomRight: Radius.circular(16)),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 11),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.edit_outlined, size: 16, color: Color(0xFF1E6BFF)),
                          SizedBox(width: 6),
                          Text(
                            'Edit Locations',
                            style: TextStyle(
                              fontFamily: AppFont.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E6BFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Full-page Saved Addresses list ──────────────────────────────────────────
class _SavedAddressesPage extends StatelessWidget {
  final List<Map<String, dynamic>> addresses;
  final IconData Function(String label) addressIconFor;

  const _SavedAddressesPage({required this.addresses, required this.addressIconFor});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF4F6FA),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: AppColor.themeColor),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Saved Addresses',
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColor.fontColor,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: addresses.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.bookmark_border_outlined, size: 52, color: Colors.grey),
                            SizedBox(height: 14),
                            Text('No saved addresses yet',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey)),
                            SizedBox(height: 8),
                            Text(
                              'After confirming a drop location, tap "Save address" to store it here for quick access.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: addresses.length,
                      itemBuilder: (_, i) {
                        final sa = addresses[i];
                        final label        = sa['label']?.toString() ?? 'Saved';
                        final address      = sa['address']?.toString() ?? '';
                        final contactName  = sa['contact_name']?.toString() ?? '';
                        final contactPhone = sa['contact_phone']?.toString() ?? '';
                        final contactLine  = [contactName, contactPhone]
                            .where((s) => s.isNotEmpty)
                            .join(', ');

                        return GestureDetector(
                          onTap: () => Navigator.pop(context, sa),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3)),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 48, height: 48,
                                      decoration: const BoxDecoration(color: Color(0xffEDEFF3), shape: BoxShape.circle),
                                      child: Icon(addressIconFor(label), color: AppColor.fontColor, size: 22),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(label,
                                              style: const TextStyle(
                                                fontFamily: AppFont.fontFamily,
                                                fontSize: 18,
                                                fontWeight: FontWeight.w700,
                                                color: AppColor.fontColor,
                                              )),
                                          if (contactLine.isNotEmpty) ...[
                                            const SizedBox(height: 3),
                                            Text(contactLine,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontFamily: AppFont.fontFamily,
                                                  fontSize: 14,
                                                  color: AppColor.hintTextColor,
                                                )),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (address.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xffF4F6FA),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      address,
                                      style: const TextStyle(
                                        fontFamily: AppFont.fontFamily,
                                        fontSize: 13.5,
                                        color: AppColor.hintTextColor,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Private widget: "Select on map" / "Saved addresses" / "Add stop" pill ───
class _PillActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PillActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColor.borderColor),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: AppColor.themeColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFont.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColor.themeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Private widget: single location input row ──────────────────────────────
class _LocationField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final Color dotColor;
  final IconData icon;
  final bool isActive;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final Widget? trailing;

  const _LocationField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.dotColor,
    required this.icon,
    required this.isActive,
    required this.onChanged,
    required this.onClear,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 10),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: dotColor.withOpacity(0.12), shape: BoxShape.circle),
          child: Icon(icon, color: dotColor, size: 14),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(
              fontFamily: AppFont.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColor.fontColor,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                fontFamily: AppFont.fontFamily,
                fontSize: 14,
                color: AppColor.hintTextColor,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          ),
        ),
        if (controller.text.isNotEmpty)
          GestureDetector(
            onTap: onClear,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Container(
                height: 20,
                width: 20,
                decoration: BoxDecoration(
                  color: AppColor.greyLightColor.withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, size: 13, color: AppColor.hintTextColor),
              ),
            ),
          ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ── Add Stop bottom sheet ─────────────────────────────────────────────────────
class _AddStopSheet extends StatefulWidget {
  final LatLng pickupLatLng;
  final List<Map<String, dynamic>> savedAddresses;
  final void Function(String address, LatLng latLng) onStopSelected;

  const _AddStopSheet({required this.pickupLatLng, required this.savedAddresses, required this.onStopSelected});

  @override
  State<_AddStopSheet> createState() => _AddStopSheetState();
}

class _AddStopSheetState extends State<_AddStopSheet> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = false;
  Timer? _debounce;
  // Bundles an Autocomplete typing sequence + its terminating Details call
  // into one billed Places session instead of billing every request alone.
  String? _sessionToken;

  // Mode: 'search' | 'map' | 'saved'
  String _mode = 'search';

  // Map picker state
  LatLng _pinLatLng = const LatLng(0, 0);
  String _pinAddress = '';
  bool _reverseGeocoding = false;

  // Confirmation step state
  bool _confirming = false;
  String _confirmingAddress = '';
  LatLng _confirmingLatLng = const LatLng(0, 0);
  bool _confirmReverseGeocoding = false;

  @override
  void initState() {
    super.initState();
    _pinLatLng = widget.pickupLatLng;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _sessionToken = null;
      setState(() { _suggestions = []; if (_mode != 'map') _mode = 'search'; });
      return;
    }
    setState(() { _suggestions = []; _mode = 'search'; });
    if (value.trim().length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 400), () => _fetchSuggestions(value.trim()));
  }

  Future<void> _fetchSuggestions(String input) async {
    if (!mounted) return;
    setState(() => _loading = true);
    _sessionToken ??= PlacesSessionToken.generate();
    try {
      final lat = widget.pickupLatLng.latitude;
      final lng = widget.pickupLatLng.longitude;
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(input)}'
        '&location=$lat,$lng'
        '&radius=50000'
        '&components=country:in'
        '&sessiontoken=$_sessionToken'
        '&key=${AppConstant.googleApiKey}',
      );
      final res = await http.get(url);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final preds = data['predictions'] as List? ?? [];
      setState(() {
        _suggestions = preds.map<Map<String, dynamic>>((p) => {
          'place_id':       p['place_id'],
          'main_text':      (p['structured_formatting']?['main_text']) ?? p['description'],
          'secondary_text': (p['structured_formatting']?['secondary_text']) ?? '',
        }).toList();
      });
    } catch (_) {
      if (mounted) setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectPlace(Map<String, dynamic> place) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=${place['place_id']}'
        '&fields=geometry,formatted_address'
        '&sessiontoken=$_sessionToken'
        '&key=${AppConstant.googleApiKey}',
      );
      // Details call ends the session — next search starts a fresh one.
      _sessionToken = null;
      final res = await http.get(url);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final loc = data['result']?['geometry']?['location'];
      final address = (data['result']?['formatted_address'] ?? place['main_text']).toString();
      if (loc != null) {
        final latLng = LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
        if (mounted) {
          _focusNode.unfocus();
          setState(() {
            _confirming = true;
            _confirmingAddress = address;
            _confirmingLatLng = latLng;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _reverseGeocode(LatLng latLng) async {
    if (!mounted) return;
    setState(() { _reverseGeocoding = true; _pinAddress = ''; });
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${latLng.latitude},${latLng.longitude}'
        '&key=${AppConstant.googleApiKey}',
      );
      final res = await http.get(url);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = data['results'] as List? ?? [];
      if (results.isNotEmpty) {
        setState(() => _pinAddress = results.first['formatted_address']?.toString() ?? '');
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _reverseGeocoding = false);
    }
  }

  void _confirmMapPin() {
    if (_pinAddress.isEmpty) return;
    _focusNode.unfocus();
    setState(() {
      _confirming = true;
      _confirmingAddress = _pinAddress;
      _confirmingLatLng = _pinLatLng;
    });
  }

  Future<void> _reverseGeocodeConfirm(LatLng latLng) async {
    if (!mounted) return;
    setState(() { _confirmReverseGeocoding = true; });
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${latLng.latitude},${latLng.longitude}'
        '&key=${AppConstant.googleApiKey}',
      );
      final res = await http.get(url);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = data['results'] as List? ?? [];
      if (results.isNotEmpty) {
        setState(() => _confirmingAddress = results.first['formatted_address']?.toString() ?? '');
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _confirmReverseGeocoding = false);
    }
  }

  void _doConfirm() {
    if (_confirmingAddress.isEmpty || _confirmReverseGeocoding) return;
    Navigator.pop(context);
    widget.onStopSelected(_confirmingAddress, _confirmingLatLng);
  }

  Widget _buildConfirmView(double sheetH) {
    final mapH = sheetH * 0.62;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(20)))),
        // Header with back button
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 16, 8),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: AppColor.blackColor, size: 22),
              onPressed: () => setState(() { _confirming = false; }),
            ),
            const Text('Confirm Stop', style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 16, color: AppColor.blackColor)),
          ]),
        ),
        // Draggable map — user can fine-tune the pin position
        SizedBox(
          height: mapH,
          child: Stack(
            children: [
              _DraggableMapPin(
                key: const ValueKey('stop_confirm_map'),
                initialLatLng: _confirmingLatLng,
                zoom: 16,
                pinColor: Colors.orange,
                onCameraIdle: (latLng) {
                  _confirmingLatLng = latLng;
                  _reverseGeocodeConfirm(latLng);
                },
              ),
              // "Move to adjust" hint
              Positioned(
                top: 10, left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Drag map to adjust pin', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Address + buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Stop Location', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11, fontWeight: FontWeight.w600, color: AppColor.hintTextColor)),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.location_on_rounded, color: Colors.orange, size: 18)),
              const SizedBox(width: 6),
              Expanded(
                child: _confirmReverseGeocoding
                    ? const LinearProgressIndicator(color: AppColor.themeColor, backgroundColor: Color(0xFFE2E8F0), minHeight: 14)
                    : Text(
                        _confirmingAddress.isNotEmpty ? _confirmingAddress : 'Move map to select location',
                        maxLines: 3, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, fontWeight: FontWeight.w500, color: AppColor.blackColor),
                      ),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() { _confirming = false; }),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColor.themeColor),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Change', style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 14, color: AppColor.themeColor)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: !_confirmReverseGeocoding && _confirmingAddress.isNotEmpty ? _doConfirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColor.themeColor,
                    disabledBackgroundColor: const Color(0xFFE2E8F0),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Add Stop', style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
                ),
              ),
            ]),
          ]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenH    = MediaQuery.of(context).size.height;
    final sheetH     = (screenH * 0.88).clamp(500.0, screenH * 0.92);
    final mapH       = (sheetH * 0.42).clamp(180.0, 280.0);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: sheetH,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(color: Color(0x26000000), blurRadius: 14, offset: Offset(0, -3))],
        ),
        child: SafeArea(
          top: false,
          child: _confirming
            ? _buildConfirmView(sheetH)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  const SizedBox(height: 10),
                  Center(child: Container(width: 42, height: 4,
                      decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(20)))),

                  // Header — back arrow only when in map/saved mode
                  Padding(
                    padding: EdgeInsets.fromLTRB(_mode != 'search' ? 4 : 16, 10, 16, 8),
                    child: Row(children: [
                      if (_mode != 'search')
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, color: AppColor.blackColor, size: 22),
                          onPressed: () => setState(() { _mode = 'search'; _pinAddress = ''; }),
                        ),
                      Text(
                        _mode == 'saved' ? 'Saved Addresses' : 'Add a Stop',
                        style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 16, color: AppColor.blackColor),
                      ),
                    ]),
                  ),

                  // Search field — hidden when in map mode (map takes full height)
                  if (_mode != 'map') ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focusNode,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Search stop address...',
                          hintStyle: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, color: AppColor.hintTextColor),
                          prefixIcon: const Icon(Icons.search_rounded, color: AppColor.hintTextColor, size: 20),
                          suffixIcon: _loading
                              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColor.themeColor)))
                              : _ctrl.text.isNotEmpty
                                  ? IconButton(icon: const Icon(Icons.close_rounded, size: 18, color: AppColor.hintTextColor), onPressed: () {
                                      _ctrl.clear();
                                      setState(() { _suggestions = []; _mode = 'search'; });
                                    })
                                  : null,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColor.themeColor, width: 1.5)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Action buttons — visible when in search mode (no query or empty suggestions)
                    if (_mode == 'search' && _suggestions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                _focusNode.unfocus();
                                setState(() { _mode = 'map'; _pinLatLng = widget.pickupLatLng; _pinAddress = ''; });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColor.themeColor.withOpacity(0.07),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColor.themeColor.withOpacity(0.3)),
                                ),
                                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(Icons.map_rounded, size: 15, color: AppColor.themeColor),
                                  SizedBox(width: 6),
                                  Text('Select on Map', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, fontWeight: FontWeight.w600, color: AppColor.themeColor)),
                                ]),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                _focusNode.unfocus();
                                setState(() { _mode = 'saved'; });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(Icons.bookmark_rounded, size: 15, color: AppColor.hintTextColor),
                                  SizedBox(width: 6),
                                  Text('Saved Address', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, fontWeight: FontWeight.w600, color: AppColor.hintTextColor)),
                                ]),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    if (_mode == 'search' && _suggestions.isEmpty) const SizedBox(height: 10),
                  ],

                  // ── Body ─────────────────────────────────────────────────
                  Expanded(child: _buildBody(mapH)),
                ],
              ),
        ),
      ),
    );
  }

  Widget _buildBody(double mapH) {
    // ── Map mode ────────────────────────────────────────────────────────────────
    if (_mode == 'map') {
      return Column(children: [
        Expanded(
          child: _DraggableMapPin(
            key: const ValueKey('stop_picker_map'),
            initialLatLng: _pinLatLng,
            onCameraIdle: (latLng) {
              _pinLatLng = latLng;
              _reverseGeocode(latLng);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Selected Location', style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 11, color: AppColor.hintTextColor)),
            const SizedBox(height: 4),
            _reverseGeocoding
                ? const LinearProgressIndicator(color: AppColor.themeColor, backgroundColor: Color(0xFFE2E8F0))
                : Text(
                    _pinAddress.isNotEmpty ? _pinAddress : 'Move the map to select a location',
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, fontWeight: FontWeight.w500, color: AppColor.blackColor),
                  ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity, height: 46,
              child: ElevatedButton(
                onPressed: _pinAddress.isNotEmpty && !_reverseGeocoding ? _confirmMapPin : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColor.themeColor,
                  disabledBackgroundColor: const Color(0xFFE2E8F0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Use This Location', style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ]);
    }

    // ── Saved addresses mode ────────────────────────────────────────────────────
    if (_mode == 'saved') {
      final addresses = widget.savedAddresses;
      if (addresses.isEmpty) {
        return const Center(child: Text('No saved addresses', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, color: AppColor.hintTextColor)));
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: addresses.length,
        itemBuilder: (_, i) {
          final sa      = addresses[i];
          final label   = (sa['label'] ?? '').toString();
          final address = (sa['address'] ?? '').toString();
          final lat = double.tryParse((sa['latitude'] ?? sa['lat'] ?? '0').toString()) ?? 0.0;
          final lng = double.tryParse((sa['longitude'] ?? sa['lng'] ?? '0').toString()) ?? 0.0;
          if (lat == 0.0 && lng == 0.0) return const SizedBox.shrink();
          return ListTile(
            leading: const Icon(Icons.bookmark_rounded, color: AppColor.themeColor, size: 22),
            title: Text(label.isNotEmpty ? label : address,
                style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 13, color: AppColor.blackColor)),
            subtitle: label.isNotEmpty
                ? Text(address, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11, color: AppColor.hintTextColor))
                : null,
            onTap: () {
              final latLng = LatLng(lat, lng);
              final display = address.isNotEmpty ? address : label;
              setState(() {
                _confirming = true;
                _confirmingAddress = display;
                _confirmingLatLng  = latLng;
              });
            },
          );
        },
      );
    }

    // ── Search mode ─────────────────────────────────────────────────────────────
    if (_suggestions.isEmpty) {
      return Center(child: Text(
        _ctrl.text.trim().isEmpty
            ? 'Search an address or choose an option above'
            : _ctrl.text.length < 2 ? 'Type at least 2 characters' : 'No results found',
        textAlign: TextAlign.center,
        style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, color: AppColor.hintTextColor),
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4),
      itemCount: _suggestions.length,
      itemBuilder: (_, i) {
        final s = _suggestions[i];
        return ListTile(
          leading: const Icon(Icons.location_on_rounded, color: AppColor.themeColor, size: 20),
          title: Text(s['main_text'] ?? '',
              style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, fontWeight: FontWeight.w600, color: AppColor.blackColor)),
          subtitle: (s['secondary_text'] ?? '').isNotEmpty
              ? Text(s['secondary_text'], maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11, color: AppColor.hintTextColor))
              : null,
          onTap: () => _selectPlace(s),
        );
      },
    );
  }
}

// ── Isolated draggable map pin ────────────────────────────────────────────────
// Owns its own GoogleMapController so parent setState never causes map rebuild.
// onCameraMove updates the pin position WITHOUT setState (crosshair is static).
// onCameraIdle fires the parent callback so the parent can reverse-geocode.
class _DraggableMapPin extends StatefulWidget {
  final LatLng initialLatLng;
  final double zoom;
  final Color pinColor;
  final void Function(LatLng) onCameraIdle;
  // When true, [onCameraIdle] fires only after the user has actually
  // panned/zoomed the map at least once — swallows the spurious idle some
  // Google Maps builds emit right after first layout, which would otherwise
  // let the map silently overwrite a field the user never touched. Existing
  // callers keep the old "fire on every idle" behaviour (default false).
  final bool requireUserMove;

  const _DraggableMapPin({
    required this.initialLatLng,
    required this.onCameraIdle,
    this.zoom = 14,
    this.pinColor = AppColor.themeColor,
    this.requireUserMove = false,
    super.key,
  });

  @override
  State<_DraggableMapPin> createState() => _DraggableMapPinState();
}

class _DraggableMapPinState extends State<_DraggableMapPin> {
  GoogleMapController? _ctrl;
  late LatLng _current;
  bool _userInteracted = false;

  @override
  void initState() {
    super.initState();
    _current = widget.initialLatLng;
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  /// Imperatively re-centre the map (e.g. after a search suggestion is picked
  /// on the parent screen). The settling idle this triggers is expected to be
  /// filtered out by the parent's "did it actually move?" proximity check.
  void moveCameraTo(LatLng target, {double zoom = 16}) {
    _current = target;
    _ctrl?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: target, zoom: zoom)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: widget.initialLatLng, zoom: widget.zoom),
          onMapCreated: (c) => _ctrl = c,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          markers: const {},
          onCameraMoveStarted: () => _userInteracted = true,
          // No setState — crosshair stays centred, no visual update needed per frame
          onCameraMove: (pos) { _current = pos.target; },
          onCameraIdle: () {
            if (widget.requireUserMove && !_userInteracted) return;
            widget.onCameraIdle(_current);
          },
          // Claim all gestures so the bottom sheet doesn't intercept map drags
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
          },
        ),
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.location_on_rounded, color: widget.pinColor, size: 40),
            const SizedBox(height: 18),
          ]),
        ),
      ],
    );
  }
}

// ── 3D Bookmark Ribbon Badge (Right-Edge Folded) ───────────────────────────────
class _Animated3DBookmark extends StatefulWidget {
  final int coins;
  const _Animated3DBookmark({required this.coins});

  @override
  State<_Animated3DBookmark> createState() => _Animated3DBookmarkState();
}

class _Animated3DBookmarkState extends State<_Animated3DBookmark> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _shimmer = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        final val = _shimmer.value;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.centerRight,
          children: [
            // Top 3D back-fold corner triangle (peeking behind the right edge)
            Positioned(
              top: -5,
              right: 0,
              child: CustomPaint(
                size: const Size(6, 6),
                painter: const _BookmarkTrianglePainter(isTop: true),
              ),
            ),
            // Bottom 3D back-fold corner triangle
            Positioned(
              bottom: -5,
              right: 0,
              child: CustomPaint(
                size: const Size(6, 6),
                painter: const _BookmarkTrianglePainter(isTop: false),
              ),
            ),
            // Right 3D wrap bar
            Positioned(
              right: -5,
              top: 0,
              bottom: 0,
              child: Container(
                width: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF0D3B99),
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(3)),
                ),
              ),
            ),
            // Main front bookmark ribbon
            Container(
              padding: const EdgeInsets.fromLTRB(9, 4, 8, 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(const Color(0xFF1E6BFF), const Color(0xFF2575FC), val)!,
                    Color.lerp(const Color(0xFF1557CD), const Color(0xFF1E6BFF), val)!,
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                  topRight: Radius.circular(2),
                  bottomRight: Radius.circular(2),
                ),
                border: Border.all(
                  color: Color.lerp(const Color(0xFFFFD54F), const Color(0xFFFFF176), val)!,
                  width: 1.2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 4,
                    offset: Offset(-1, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    AppImage.goldCoinReward,
                    width: 13,
                    height: 13,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.monetization_on_rounded,
                      color: Color(0xFFFFD54F),
                      size: 13,
                    ),
                  ),
                  const SizedBox(width: 4.5),
                  Text(
                    'UPTO ${widget.coins} COINS',
                    style: const TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontWeight: FontWeight.w800,
                      fontSize: 9.5,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BookmarkTrianglePainter extends CustomPainter {
  final bool isTop;
  const _BookmarkTrianglePainter({required this.isTop});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF0A2B70);
    final path = Path();
    if (isTop) {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(0, 0);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(0, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Fare loading skeleton ─────────────────────────────────────────────────────
class _FareSkeleton extends StatefulWidget {
  final bool selected;
  const _FareSkeleton({required this.selected});
  @override
  State<_FareSkeleton> createState() => _FareSkeletonState();
}

class _FareSkeletonState extends State<_FareSkeleton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.8).animate(_ctrl);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 52, height: 20,
        decoration: BoxDecoration(
          color: (widget.selected ? AppColor.themeColor : AppColor.greyLightColor).withOpacity(_anim.value),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}

// ── "More vehicles below" scroll hint ─────────────────────────────────────────
// A small bouncing down-chevron pill shown over the vehicle list whenever
// there are more cards below the current fold — otherwise nothing on screen
// told people the sheet could be dragged/scrolled to see the rest.
class _MoreVehiclesHint extends StatefulWidget {
  @override
  State<_MoreVehiclesHint> createState() => _MoreVehiclesHintState();
}

class _MoreVehiclesHintState extends State<_MoreVehiclesHint> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);
    _bounce = Tween<double>(begin: 0, end: 6).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounce,
      builder: (_, child) => Transform.translate(offset: Offset(0, _bounce.value), child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColor.themeColor, size: 22),
      ),
    );
  }
}

// ── Vehicle choice model ──────────────────────────────────────────────────────
class _VehicleChoice {
  final String key;
  final String label;
  final String subVehicleTypeId;
  final String category;
  final String capacity;
  final String imagePath;
  final String dimImagePath;
  final String dimSummary;
  final String dimDesc;
  final String suitableFor;
  final String? badge;
  final String eta;
  final Map<String, dynamic>? backendVehicle;
  final int wheelCount;
  final IconData icon;

  const _VehicleChoice({
    required this.key,
    required this.label,
    required this.backendVehicle,
    required this.subVehicleTypeId,
    required this.wheelCount,
    required this.category,
    required this.icon,
    required this.imagePath,
    required this.dimImagePath,
    required this.dimSummary,
    required this.dimDesc,
    required this.suitableFor,
    this.badge,
    required this.eta,
    required this.capacity,
  });

  factory _VehicleChoice.empty() => const _VehicleChoice(
    key: '',
    label: '',
    backendVehicle: null,
    subVehicleTypeId: '',
    wheelCount: 2,
    category: '2W',
    icon: Icons.two_wheeler,
    imagePath: '',
    dimImagePath: '',
    dimSummary: '',
    dimDesc: '',
    suitableFor: '',
    badge: null,
    eta: '',
    capacity: '',
  );
}

// ── Manage Route (multi-stop) full-screen page ───────────────────────────────
// Opened from the "Add / Manage Stops" action on the vehicle-selection screen.
// Shows the whole route as one draggable list — first row is the pickup, last
// row is the final drop, everything between is an intermediate stop. The user
// can add stops, re-pick any row's location, remove intermediate stops and
// drag rows into any order, then Confirm to return the new ordered route.
class StopManagerScreen extends StatefulWidget {
  /// Ordered points: [pickup, ...stops, finalDrop]. Each map holds
  /// address / lat / lng / contact_name / contact_phone.
  final List<Map<String, dynamic>> initialPoints;
  final List<Map<String, dynamic>> savedAddresses;

  const StopManagerScreen({
    super.key,
    required this.initialPoints,
    required this.savedAddresses,
  });

  @override
  State<StopManagerScreen> createState() => _StopManagerScreenState();
}

class _StopManagerScreenState extends State<StopManagerScreen> {
  late List<Map<String, dynamic>> _points;

  @override
  void initState() {
    super.initState();
    _points = widget.initialPoints
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  LatLng _ll(Map m) =>
      LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());

  LatLng get _bias =>
      _points.isNotEmpty ? _ll(_points.first) : const LatLng(22.7196, 75.8577);

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _points.removeAt(oldIndex);
      _points.insert(newIndex, item);
    });
  }

  Future<void> _pickLocation(void Function(String address, LatLng latLng) onPicked) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddStopSheet(
        pickupLatLng: _bias,
        savedAddresses: widget.savedAddresses,
        onStopSelected: onPicked,
      ),
    );
  }

  void _addStop() {
    _pickLocation((address, latLng) {
      if (!mounted) return;
      setState(() {
        // Insert just before the final drop.
        _points.insert(_points.length - 1, {
          'address': address,
          'lat': latLng.latitude,
          'lng': latLng.longitude,
          'contact_name': '',
          'contact_phone': '',
        });
      });
    });
  }

  void _editPoint(int index) {
    _pickLocation((address, latLng) {
      if (!mounted) return;
      setState(() {
        _points[index] = {
          ..._points[index],
          'address': address,
          'lat': latLng.latitude,
          'lng': latLng.longitude,
        };
      });
    });
  }

  void _remove(int index) {
    if (_points.length <= 2) return;
    setState(() => _points.removeAt(index));
  }

  void _confirm() {
    final valid = _points.every((m) =>
        (m['address'] ?? '').toString().trim().isNotEmpty &&
        m['lat'] != null &&
        m['lng'] != null);
    if (!valid) {
      SnackBarToastMessage.showSnackBar(context, 'Every point needs a valid location');
      return;
    }
    Navigator.pop(context, _points);
  }

  @override
  Widget build(BuildContext context) {
    final stopCount = _points.length - 2;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1E293B)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    'Manage Route',
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Drag to reorder — first row is the pickup, last row is the drop. Tap a row to change its location.',
                  style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, color: Color(0xFF64748B)),
                ),
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                buildDefaultDragHandles: false,
                proxyDecorator: (child, index, animation) =>
                    Material(color: Colors.transparent, child: child),
                onReorder: _reorder,
                itemCount: _points.length,
                itemBuilder: (context, i) => _row(i),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
              child: InkWell(
                onTap: _addStop,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF4FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBFD4FF)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_rounded, size: 18, color: Color(0xFF1E6BFF)),
                      SizedBox(width: 6),
                      Text(
                        'Add stop',
                        style: TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E6BFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E6BFF),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    stopCount > 0
                        ? 'Confirm Route  •  $stopCount stop${stopCount > 1 ? 's' : ''}'
                        : 'Confirm Route',
                    style: const TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(int i) {
    final m = _points[i];
    final isFirst = i == 0;
    final isLast = i == _points.length - 1;
    final label = isFirst ? 'PICKUP' : isLast ? 'DROP' : 'STOP $i';
    final accent = isFirst
        ? const Color(0xFF16A34A)
        : isLast
            ? const Color(0xFFDC2626)
            : const Color(0xFF1E6BFF);
    final address = (m['address'] ?? '').toString();

    return Padding(
      key: ValueKey('rp_${i}_$address'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: () => _editPoint(i),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: AppFont.fontFamily,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      address.isEmpty ? 'Tap to set location' : address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFont.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: address.isEmpty ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ReorderableDragStartListener(
            index: i,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.drag_handle_rounded, size: 20, color: Color(0xFF94A3B8)),
            ),
          ),
          if (!isFirst && !isLast && _points.length > 2)
            GestureDetector(
              onTap: () => _remove(i),
              child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
            )
          else
            const SizedBox(width: 18),
        ],
      ),
    );
  }
}

