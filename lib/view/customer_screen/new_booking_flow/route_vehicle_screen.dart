import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart' show EagerGestureRecognizer, OneSequenceGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:movigo/Controller/get_vehicle_list_provider.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/fare_calculator.dart';
import 'package:movigo/Controller/SlotController.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'contact_info_screen.dart';

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
  final LatLng pickupLatLng;
  final String pickupAddress;
  final String pickupContactName;
  final String pickupContactPhone;
  final LatLng dropLatLng;
  final String dropAddress;
  final String? preSelectedVehicleName;
  final String dropContactName;
  final String dropContactPhone;
  // When provided, selecting a vehicle calls this callback and pops instead
  // of navigating forward — used by the "Change Vehicle" flow on RetailerConfirmScreen.
  final void Function(Map<String, dynamic>)? onVehicleSelected;

  const RouteVehicleScreen({
    super.key,
    required this.pickupLatLng,
    required this.pickupAddress,
    this.pickupContactName  = '',
    this.pickupContactPhone = '',
    required this.dropLatLng,
    required this.dropAddress,
    this.preSelectedVehicleName,
    this.dropContactName  = '',
    this.dropContactPhone = '',
    this.onVehicleSelected,
  });

  @override
  State<RouteVehicleScreen> createState() => _RouteVehicleScreenState();
}

class _RouteVehicleScreenState extends State<RouteVehicleScreen> {
  GoogleMapController? _mapController;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  VehicleTypeController? _vcRef;

  // ── Distance state ──────────────────────────────────────────────────────────
  double _rawDistanceKm = 0;        // authoritative km (from Google Directions)
  double _haversineKm   = 0;        // haversine fallback (used only if Directions fails)
  String _durationText  = '';
  bool _isLoadingRoute  = true;
  bool _routeResolved   = false;    // true once Directions API responded (ok or fail)
  bool _mapReady        = false;
  int  _routeRequestId  = 0;        // guards against a stale in-flight fetch overwriting a newer one

  // ── Fare state ──────────────────────────────────────────────────────────────
  String? _selectedKey;

  /// Stores the backend-calculated total payable per vehicle key.
  /// NEVER written until the route is resolved with the correct km.
  final Map<String, int>  _backendFareByKey   = {};
  final Set<String>       _backendFareLoading = {};

  /// The km value that was used to request the currently-cached fares.
  /// If _rawDistanceKm differs from this by >0.3 km, we invalidate the cache.
  double _fareRequestedAtKm = 0;

  /// True once _ensureBackendEstimates has been called at least once after
  /// route resolved. Prevents _fareFor from showing local-calc fallback during
  /// the one-frame window between route resolution and first API call.
  bool _estimatesEverStarted = false;

  // ── Feature 11: Scheduled booking ──────────────────────────────────────────
  bool _isScheduled = false;
  DateTime? _selectedDate;
  Map<String, dynamic>? _selectedSlot;

  // ── Phase: map view vs vehicle selection ────────────────────────────────────
  bool _vehiclePhase = false;

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

  void _handleBack() {
    if (_vehiclePhase) {
      setState(() => _vehiclePhase = false);
    } else {
      Navigator.maybePop(context);
    }
  }

  @override
  void initState() {
    super.initState();
    _effectivePickupAddress      = widget.pickupAddress;
    _effectivePickupLatLng       = widget.pickupLatLng;
    _effectivePickupContactName  = widget.pickupContactName;
    _effectivePickupContactPhone = widget.pickupContactPhone;
    _effectiveDropAddress        = widget.dropAddress;
    _effectiveDropLatLng         = widget.dropLatLng;
    _effectiveDropContactName    = widget.dropContactName;
    _effectiveDropContactPhone   = widget.dropContactPhone;
    _buildMarkers();
    _haversineKm = _haversineDistanceKm(widget.pickupLatLng, widget.dropLatLng);
    _rawDistanceKm = _haversineKm;         // initial estimate only for display
    _durationText = _estimateDurationText(_haversineKm);
    _fetchRoute();                          // async — updates _rawDistanceKm when done

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
    });
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
    _mapController?.dispose();
    super.dispose();
  }

  // ── Marker setup ────────────────────────────────────────────────────────────
  void _buildMarkers() => _rebuildMarkersAll();

  final Map<int, BitmapDescriptor> _numberedIconCache = {};

  /// Draws a red teardrop pin with a white number, matching the numbered
  /// stops shown in the location list — cached per number.
  Future<BitmapDescriptor> _numberedPinIcon(int number) async {
    final cached = _numberedIconCache[number];
    if (cached != null) return cached;

    const double size = 96;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
    final center = Offset(size / 2, size / 2 - 6);
    final radius = size / 2 - 14;

    final pinPaint = Paint()..color = const Color(0xFFE53935);
    canvas.drawCircle(center, radius, pinPaint);
    final pointer = Path()
      ..moveTo(center.dx - radius * 0.55, center.dy + radius * 0.75)
      ..lineTo(center.dx, size - 6)
      ..lineTo(center.dx + radius * 0.55, center.dy + radius * 0.75)
      ..close();
    canvas.drawPath(pointer, pinPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, borderPaint);

    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: '$number',
        style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800),
      )
      ..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final icon = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
    _numberedIconCache[number] = icon;
    return icon;
  }

  Future<void> _rebuildMarkersAll() async {
    final destinations = <_ExtraStop>[
      ..._extraStops,
      _ExtraStop(address: _effectiveDropAddress, latLng: _effectiveDropLatLng),
    ];

    final newMarkers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: _effectivePickupLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Pickup'),
      ),
    };
    for (int i = 0; i < destinations.length; i++) {
      final icon = await _numberedPinIcon(i + 1);
      newMarkers.add(Marker(
        markerId: MarkerId('dest_$i'),
        position: destinations[i].latLng,
        icon: icon,
        infoWindow: InfoWindow(title: i == destinations.length - 1 ? 'Drop' : 'Stop ${i + 1}'),
      ));
    }
    if (!mounted) return;
    setState(() => _markers = newMarkers);
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
        final totalSeconds = legs.fold<int>(0, (sum, leg) => sum + ((leg['duration']?['value'] as num?)?.toInt() ?? 0));
        final dur     = totalSeconds > 0 ? _formatDurationSeconds(totalSeconds) : _estimateDurationText(_totalWaypointKm());
        final encoded = route['overview_polyline']?['points'] as String?;
        final points  = encoded == null ? <LatLng>[] : _decodePolyline(encoded);

        final fallbackKm = _extraStops.isEmpty ? _haversineKm : _totalWaypointKm();
        final newKm  = totalMeters > 0 ? totalMeters / 1000.0 : fallbackKm;

        setState(() {
          _rawDistanceKm = newKm;
          _durationText  = dur;
          _polylines     = points.isEmpty ? {} : {
            Polyline(
              polylineId: const PolylineId('route'),
              points: points,
              color: AppColor.themeColor,
              width: 5,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
            ),
          };
          _isLoadingRoute = false;
          _routeResolved  = true;
          // ── KEY FIX: Clear any stale fares from haversine-distance calls ──
          // If _ensureBackendEstimates already fired (edge case where vehicle
          // list loaded before route), invalidate so we re-fetch with true km.
          _invalidateFareCache(reason: 'route resolved');
        });
        if (_mapReady) _fitMapToBounds();
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
        if (response.statusCode >= 200 && response.statusCode < 300) {
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is Map && decoded['success'] == true) {
              final apiData = Map<String, dynamic>.from(decoded['data'] ?? {});
              final pb = apiData['price_breakup'];
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

  // ── Map helpers ─────────────────────────────────────────────────────────────
  void _fitMapToBounds() {
    if (_mapController == null) return;
    final allPoints = [
      _effectivePickupLatLng,
      ..._extraStops.map((s) => s.latLng),
      _effectiveDropLatLng,
    ];
    final swLat = allPoints.map((p) => p.latitude).reduce(math.min);
    final swLng = allPoints.map((p) => p.longitude).reduce(math.min);
    final neLat = allPoints.map((p) => p.latitude).reduce(math.max);
    final neLng = allPoints.map((p) => p.longitude).reduce(math.max);
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(swLat, swLng),
          northeast: LatLng(neLat, neLng),
        ),
        90,
      ),
    );
  }

  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> pts = [];
    int idx = 0; int lat = 0; int lng = 0;
    while (idx < encoded.length) {
      int b, shift = 0, result = 0;
      do { b = encoded.codeUnitAt(idx++) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0; result = 0;
      do { b = encoded.codeUnitAt(idx++) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      pts.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return pts;
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

  String _estimateDurationText(double km) {
    final minutes = math.max(5, (km / 22 * 60).ceil());
    return '$minutes min';
  }

  String _formatDurationSeconds(int seconds) {
    final minutes = math.max(1, (seconds / 60).round());
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final mins  = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}min' : '${hours}h';
  }

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
    // the real driving route through all stops (via _fetchRoute) to get the
    // accurate distance/duration and a polyline that actually connects them.
    final km = _totalWaypointKm();
    _invalidateFareCache(reason: 'stop added/removed');
    setState(() {
      _rawDistanceKm = km;
      _durationText  = _estimateDurationText(km);
      _routeResolved = true;
    });
    _fitMapToBounds();
    _triggerEstimatesAndAutoSelect();
    _fetchRoute();
  }

  /// Removes a destination (stop or the final drop) by its index within the
  /// combined `[...extraStops, drop]` list. Pickup is never removable.
  /// When the final drop is removed, the last remaining stop is promoted to
  /// become the new drop — at least one destination always remains.
  void _removeDestination(int index) {
    final total = _extraStops.length + 1; // stops + drop
    if (total <= 1) return;
    if (index == total - 1) {
      if (_extraStops.isEmpty) return;
      final promoted = _extraStops.removeLast();
      setState(() {
        _effectiveDropAddress      = promoted.address;
        _effectiveDropLatLng       = promoted.latLng;
        _effectiveDropContactName  = promoted.contactName;
        _effectiveDropContactPhone = promoted.contactPhone;
      });
    } else {
      setState(() => _extraStops.removeAt(index));
    }
    _rebuildMarkersAll();
    _recalcWithStops();
  }

  /// Reorders the ENTIRE route (pickup + stops + drop) — any location can be
  /// dragged into any position, so a drop can become the pickup, the pickup
  /// can become a drop, or any two drops can swap. Contact info always travels
  /// with the address it belongs to, not the slot. Whichever item ends up
  /// first becomes the new pickup, whichever ends up last becomes the new
  /// (final) drop — transmission order is always pickup → stop 1 → … → drop.
  void _reorderAll(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final list = <_ExtraStop>[
      _ExtraStop(address: _effectivePickupAddress, latLng: _effectivePickupLatLng, contactName: _effectivePickupContactName, contactPhone: _effectivePickupContactPhone),
      ..._extraStops,
      _ExtraStop(address: _effectiveDropAddress, latLng: _effectiveDropLatLng, contactName: _effectiveDropContactName, contactPhone: _effectiveDropContactPhone),
    ];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    setState(() {
      _effectivePickupAddress      = list.first.address;
      _effectivePickupLatLng       = list.first.latLng;
      _effectivePickupContactName  = list.first.contactName;
      _effectivePickupContactPhone = list.first.contactPhone;
      _effectiveDropAddress        = list.last.address;
      _effectiveDropLatLng         = list.last.latLng;
      _effectiveDropContactName    = list.last.contactName;
      _effectiveDropContactPhone   = list.last.contactPhone;
      _extraStops
        ..clear()
        ..addAll(list.sublist(1, list.length - 1));
    });
    _rebuildMarkersAll();
    _recalcWithStops();
  }

  Future<void> _showAddStopSheet() async {
    await _loadSavedAddresses(); // pre-load so saved list is ready inside the sheet
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddStopSheet(
        pickupLatLng: widget.pickupLatLng,
        savedAddresses: _savedAddresses,
        onStopSelected: (address, latLng) {
          _appendNewStop(address, latLng);
        },
      ),
    );
  }

  /// Appends a newly added stop right before the existing final drop, which
  /// stays the final drop unchanged — so adding stops one at a time produces
  /// the expected sequence: pickup → stop 1 → stop 2 → … → drop (final,
  /// untouched unless the retailer explicitly drags it elsewhere).
  void _appendNewStop(String address, LatLng latLng) {
    setState(() {
      _extraStops.add(_ExtraStop(address: address, latLng: latLng));
    });
    _rebuildMarkersAll();
    _recalcWithStops();
  }

  Future<void> _loadSavedAddresses() async {
    if (_savedAddressesLoaded) return;
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
        'booking_type':           _isScheduled ? 'Scheduled' : 'Now',
        'payment_mode':           'Cash',
        'required_tag':           choice.key,
        'vehicle_key':            choice.key,
        'requested_vehicle_name': choice.label,
        'display_vehicle_name':   choice.label,
        'vehicle_category':       choice.category,
        'raw_distance_km':        double.parse(_rawDistanceKm.toStringAsFixed(3)),
        'is_multidrop':           true,
        'extra_drops':            allDrops,
        if (_isScheduled && _selectedDate != null)
          'pickup_date': '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2,'0')}-${_selectedDate!.day.toString().padLeft(2,'0')}',
        if (_isScheduled && _selectedSlot != null)
          'pickup_slot': _selectedSlot!['slot']?.toString() ?? '',
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
      required String key, required String label,
      required int wheelCount, required String category,
      required IconData icon, required String imagePath, required String capacity, bool pickup = false,
    }) {
      final backend  = _findBackendVehicle(backendVehicles, wheelCount, pickup: pickup);
      final subTypes = (backend?['sub_types'] as List?) ?? [];
      final subId    = subTypes.isNotEmpty ? (subTypes.first['_id'] ?? '').toString() : '';
      return _VehicleChoice(
        key: key, label: label, backendVehicle: backend,
        subVehicleTypeId: subId, wheelCount: wheelCount,
        category: category, icon: icon, imagePath: imagePath, capacity: capacity,
      );
    }

    return [
      choice(key: 'R_2W',       label: 'Bike / 2W',      wheelCount: 2, category: '2W',    icon: Icons.two_wheeler,       imagePath: AppImage.bike,        capacity: 'Up to 20 kg'),
      choice(key: 'R_SCOOTER',  label: 'E-Scooter',      wheelCount: 2, category: '2W',    icon: Icons.electric_scooter,  imagePath: AppImage.twowheel,    capacity: 'Up to 20 kg'),
      choice(key: 'R_MINI_3W',  label: 'Mini 3-Wheeler', wheelCount: 3, category: '3W',    icon: Icons.electric_rickshaw, imagePath: AppImage.mini3w,      capacity: 'Up to 90 kg'),
      choice(key: 'R_E_LOADER', label: 'E-Loader',       wheelCount: 3, category: '3W',    icon: Icons.electric_car,      imagePath: AppImage.eloader,     capacity: 'Up to 300 kg'),
      choice(key: 'R_3W',       label: '3 Wheeler',      wheelCount: 3, category: '3W',    icon: Icons.airport_shuttle,   imagePath: AppImage.threewheeler, capacity: 'Up to 500 kg'),
      choice(key: 'R_TATA_ACE', label: 'Tata Ace',       wheelCount: 4, category: 'Pickup',icon: Icons.local_shipping,    imagePath: AppImage.minitruck,   capacity: 'Up to 800 kg', pickup: true),
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

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContactInfoScreen(
          vehicleTypeId:    (backend['_id'] ?? '').toString(),
          subVehicleTypeId: resolvedSubId,
          vehicleData:      vehicleData,
          pickupData: {
            'lat':           _effectivePickupLatLng.latitude,
            'lng':           _effectivePickupLatLng.longitude,
            'address':       _effectivePickupAddress,
            'contact_name':  _effectivePickupContactName,
            'contact_phone': _effectivePickupContactPhone,
          },
          dropData: {
            'lat':     _effectiveDropLatLng.latitude,
            'lng':     _effectiveDropLatLng.longitude,
            'address': _effectiveDropAddress,
          },
          rawDistanceKm: _rawDistanceKm,
          estimatedFare: fare,
          subVehicleTypeList: (backend['sub_types'] as List?) ?? [],
          bookingType: _isScheduled ? 'Scheduled' : 'Now',
          pickupDate: _isScheduled && _selectedDate != null
              ? '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2,'0')}-${_selectedDate!.day.toString().padLeft(2,'0')}'
              : '',
          pickupSlot:       _selectedSlot?['slot']?.toString() ?? '',
          dropContactName:  _effectiveDropContactName,
          dropContactPhone: _effectiveDropContactPhone,
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

  // ── Location bar widgets ─────────────────────────────────────────────────────
  /// Small vertical connector shown below a rail dot/pin, linking it to the
  /// next row — gives the list the "route timeline" look from the reference design.
  Widget _railConnector(Widget dot, bool showLine) {
    return Column(
      children: [
        dot,
        if (showLine) Container(width: 2, height: 26, color: const Color(0xFFE2E8F0)),
      ],
    );
  }

  /// A single location row — used for BOTH pickup and destinations, since any
  /// location can be dragged into any position (pickup ↔ drop ↔ stop). Whether
  /// a row renders as "pickup" (green dot, no number) or a numbered red pin is
  /// purely a function of its position (index 0 = pickup), not a fixed role.
  Widget _locationRow({
    required Key key,
    required bool isPickup,
    required int number,
    required String contactName,
    required String contactPhone,
    required String address,
    required bool showLine,
    required int dragIndex,
    VoidCallback? onRemove,
  }) {
    final hasContact = contactName.isNotEmpty;
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
          _railConnector(dot, showLine),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasContact)
                          Text('$contactName · $contactPhone',
                              style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 13, color: AppColor.blackColor)),
                        Text(address, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, color: AppColor.hintTextColor)),
                      ],
                    ),
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

  /// Full editable location card — pickup, stops and the final drop are ALL
  /// in one reorderable list, so the retailer can drag any location into any
  /// position (a drop can become the pickup, the pickup can become a drop,
  /// any two stops can swap). Whichever row ends up first is the new pickup;
  /// whichever ends up last is the new drop. Shown on the confirm-address
  /// (map) screen, matching the reference design.
  Widget _buildLocationBar() {
    final allLocations = <_ExtraStop>[
      _ExtraStop(address: _effectivePickupAddress, latLng: _effectivePickupLatLng, contactName: _effectivePickupContactName, contactPhone: _effectivePickupContactPhone),
      ..._extraStops,
      _ExtraStop(address: _effectiveDropAddress, latLng: _effectiveDropLatLng, contactName: _effectiveDropContactName, contactPhone: _effectiveDropContactPhone),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            proxyDecorator: (child, index, animation) => Material(color: Colors.transparent, child: child),
            onReorder: _reorderAll,
            itemCount: allLocations.length,
            itemBuilder: (context, i) {
              final loc = allLocations[i];
              final isPickup = i == 0;
              return _locationRow(
                key: ValueKey('loc_${loc.address}_$i'),
                isPickup: isPickup,
                number: i, // destination number = position among non-pickup rows
                contactName: loc.contactName,
                contactPhone: loc.contactPhone,
                address: loc.address,
                showLine: i != allLocations.length - 1,
                dragIndex: i,
                onRemove: isPickup ? null : () => _removeDestination(i - 1),
              );
            },
          ),
          const SizedBox(height: 4),
          Center(
            child: GestureDetector(
              onTap: _showAddStopSheet,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 22, height: 22,
                    decoration: const BoxDecoration(color: AppColor.themeColor, shape: BoxShape.circle),
                    child: const Icon(Icons.add_rounded, size: 15, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  const Text('ADD STOP',
                      style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 13, color: AppColor.themeColor, letterSpacing: 0.4)),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact one-line route summary shown on the vehicle-selection screen,
  /// where the full editable list would be too heavy — editing happens on
  /// the previous (confirm address) screen.
  Widget _buildRouteSummaryChip() {
    final stopsCount = _extraStops.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(children: [
        const Icon(Icons.trip_origin, size: 12, color: Color(0xFF4CAF50)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(_effectivePickupAddress, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, color: AppColor.blackColor)),
        ),
        const SizedBox(width: 6),
        const Icon(Icons.arrow_forward_rounded, size: 13, color: AppColor.hintTextColor),
        const SizedBox(width: 6),
        if (stopsCount > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: AppColor.themeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text('+$stopsCount stop${stopsCount > 1 ? 's' : ''}',
                style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 10, fontWeight: FontWeight.w700, color: AppColor.themeColor)),
          ),
          const SizedBox(width: 6),
        ],
        const Icon(Icons.location_on, size: 12, color: Color(0xFFE53935)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(_effectiveDropAddress, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, color: AppColor.blackColor)),
        ),
      ]),
    );
  }

  // ── BUILD ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_vehiclePhase,
      onPopInvoked: (didPop) {
        if (!didPop && _vehiclePhase) setState(() => _vehiclePhase = false);
      },
      child: _vehiclePhase ? _buildVehiclePhase(context) : _buildMapPhase(context),
    );
  }

  // ── Phase 1: Confirm address (location list + route map) ───────────────────
  Widget _buildMapPhase(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: back button + distance/time chip
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _handleBack,
                    child: Container(
                      height: 40, width: 40,
                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColor.themeColor, size: 17),
                    ),
                  ),
                  const Spacer(),
                  if (_rawDistanceKm > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.route_rounded, size: 14, color: AppColor.themeColor),
                        const SizedBox(width: 5),
                        Text('${_rawDistanceKm.toStringAsFixed(1)} km',
                            style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 12, color: AppColor.blackColor)),
                        const SizedBox(width: 6),
                        const Icon(Icons.access_time_rounded, size: 12, color: AppColor.hintTextColor),
                        const SizedBox(width: 3),
                        Text(_isLoadingRoute ? '...' : _durationText,
                            style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11, color: AppColor.hintTextColor)),
                      ]),
                    ),
                ],
              ),
            ),

            // Editable location list — pickup + reorderable/removable stops & drop
            _buildLocationBar(),

            // Route map fills remaining space
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      (_effectivePickupLatLng.latitude  + _effectiveDropLatLng.latitude)  / 2,
                      (_effectivePickupLatLng.longitude + _effectiveDropLatLng.longitude) / 2,
                    ),
                    zoom: 11,
                  ),
                  markers:                 _markers,
                  polylines:               _polylines,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled:     false,
                  onMapCreated: (c) {
                    _mapController = c;
                    _mapReady      = true;
                    if (!_isLoadingRoute) _fitMapToBounds();
                  },
                ),
              ),
            ),

            // Bottom: Select Vehicle button (already inset from the system
            // nav bar by the enclosing SafeArea).
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () => setState(() => _vehiclePhase = true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColor.themeColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Select Vehicle', style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 16)),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 18),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Phase 2: Vehicle selection (no map) ──────────────────────────────────────
  Widget _buildVehiclePhase(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Consumer<VehicleTypeController>(
          builder: (context, vc, _) {
            final choices = _buildVehicleChoices(vc.vehicleTypes);
            _ensureBackendEstimates(choices);
            final selectedChoice = choices.firstWhere(
              (c) => c.key == _selectedKey,
              orElse: () => choices.isNotEmpty ? choices.first : _VehicleChoice.empty(),
            );
            final selectedFare    = _fareFor(selectedChoice);
            final selectedLoading = _isFareLoading(selectedChoice);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
                  child: Row(children: [
                    GestureDetector(
                      onTap: _handleBack,
                      child: Container(
                        height: 40, width: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColor.themeColor, size: 17),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Choose vehicle',
                            style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 17, color: AppColor.blackColor)),
                        Text(_isLoadingRoute ? 'Calculating...' : '${_rawDistanceKm.toStringAsFixed(1)} km • $_durationText',
                            style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, color: AppColor.hintTextColor)),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(color: AppColor.themeColor.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
                      child: const Text('Business', style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 11, color: AppColor.themeColor)),
                    ),
                  ]),
                ),

                // Compact route summary — full editing happens on the previous screen
                _buildRouteSummaryChip(),
                const SizedBox(height: 8),

                const Divider(height: 1, color: Color(0xFFEFF2F5)),

                // Vehicle list
                Expanded(
                  child: vc.isLoading && choices.isEmpty
                      ? const Center(child: CircularProgressIndicator(color: AppColor.themeColor))
                      : choices.isEmpty
                          ? const Center(child: Text('No vehicles found', style: TextStyle(fontFamily: AppFont.fontFamily)))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              itemCount: choices.length,
                              itemBuilder: (_, i) {
                                final c          = choices[i];
                                final isSelected = c.key == _selectedKey;
                                final fare       = _fareFor(c);
                                final loading    = _isFareLoading(c);
                                return GestureDetector(
                                  onTap: () => setState(() => _selectedKey = c.key),
                                  child: AnimatedScale(
                                    scale: isSelected ? 1.025 : 1.0,
                                    duration: const Duration(milliseconds: 180),
                                    curve: Curves.easeOutCubic,
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      decoration: BoxDecoration(
                                        color: isSelected ? Colors.white : const Color(0xffF8FAFC),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                            color: isSelected ? AppColor.themeColor : const Color(0xffE2E8F0),
                                            width: isSelected ? 2 : 1),
                                        boxShadow: isSelected
                                            ? [BoxShadow(color: AppColor.themeColor.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 6))]
                                            : [BoxShadow(color: Colors.black.withOpacity(0.015), blurRadius: 4, offset: const Offset(0, 2))],
                                      ),
                                      child: Row(children: [
                                        Container(
                                          width: 72, height: 54,
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: isSelected ? AppColor.themeColor.withOpacity(0.08) : const Color(0xffF1F5F9),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.asset(c.imagePath, fit: BoxFit.contain,
                                                errorBuilder: (_, __, ___) => Icon(c.icon,
                                                    color: isSelected ? AppColor.themeColor : AppColor.hintTextColor, size: 26)),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Row(children: [
                                            Text(c.label, style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 15,
                                                color: isSelected ? AppColor.themeColor : AppColor.blackColor)),
                                            if (c.key == 'R_TATA_ACE' || c.key == 'R_E_LOADER') ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(color: AppColor.successCOlor.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                                                child: const Text('POPULAR', style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w800, fontSize: 8, color: AppColor.successCOlor)),
                                              ),
                                            ],
                                          ]),
                                          const SizedBox(height: 3),
                                          Text(c.capacity, style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w500, fontSize: 11, color: AppColor.bluishGrayColor)),
                                          if (c.backendVehicle == null)
                                            const Text('Backend vehicle missing', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 10, color: AppColor.redColor)),
                                        ])),
                                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                          loading
                                              ? _FareSkeleton(selected: isSelected)
                                              : Text(fare != null && fare > 0 ? '₹$fare' : '—',
                                                  style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w800, fontSize: 18,
                                                      color: isSelected ? AppColor.themeColor : AppColor.blackColor)),
                                          const SizedBox(height: 4),
                                          if (isSelected) const Icon(Icons.check_circle_rounded, color: AppColor.successCOlor, size: 18),
                                        ]),
                                      ]),
                                    ),
                                  ),
                                );
                              },
                            ),
                ),

                // Schedule panel
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: _ScheduleBookingPanel(
                    isScheduled: _isScheduled,
                    selectedDate: _selectedDate,
                    selectedSlot: _selectedSlot,
                    onToggle: (val) => setState(() {
                      _isScheduled = val;
                      if (!val) { _selectedDate = null; _selectedSlot = null; }
                    }),
                    onDateSelected: (d) {
                      setState(() { _selectedDate = d; _selectedSlot = null; });
                      final dateStr = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
                      Provider.of<SlotController>(context, listen: false).getSlots(context, dateStr);
                    },
                    onSlotSelected: (s) => setState(() => _selectedSlot = s),
                  ),
                ),

                // Book button
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 14),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: selectedChoice.backendVehicle != null
                          && !_isLoadingRoute
                          && !selectedLoading
                          && selectedFare != null
                          && selectedFare > 0
                          && (!_isScheduled || (_selectedDate != null && _selectedSlot != null))
                          ? () => _onBook(selectedChoice)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColor.themeColor,
                        disabledBackgroundColor: AppColor.greyLightColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: selectedLoading
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : Text(
                              selectedChoice.backendVehicle != null && selectedFare != null && selectedFare > 0
                                  ? (_isScheduled
                                      ? 'Schedule ${selectedChoice.label}  •  ₹$selectedFare'
                                      : 'Book ${selectedChoice.label}  •  ₹$selectedFare')
                                  : selectedChoice.backendVehicle == null
                                      ? 'Select a Vehicle'
                                      : 'Calculating fare...',
                              style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 16),
                            ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
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
    try {
      final lat = widget.pickupLatLng.latitude;
      final lng = widget.pickupLatLng.longitude;
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(input)}'
        '&location=$lat,$lng'
        '&radius=50000'
        '&components=country:in'
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
        '&key=${AppConstant.googleApiKey}',
      );
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

  const _DraggableMapPin({
    required this.initialLatLng,
    required this.onCameraIdle,
    this.zoom = 14,
    this.pinColor = AppColor.themeColor,
    super.key,
  });

  @override
  State<_DraggableMapPin> createState() => _DraggableMapPinState();
}

class _DraggableMapPinState extends State<_DraggableMapPin> {
  GoogleMapController? _ctrl;
  late LatLng _current;

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
          // No setState — crosshair stays centred, no visual update needed per frame
          onCameraMove: (pos) { _current = pos.target; },
          onCameraIdle: () => widget.onCameraIdle(_current),
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

// ── Vehicle choice model ──────────────────────────────────────────────────────
class _VehicleChoice {
  final String key, label, subVehicleTypeId, category, capacity, imagePath;
  final Map<String, dynamic>? backendVehicle;
  final int wheelCount;
  final IconData icon;

  const _VehicleChoice({
    required this.key, required this.label, required this.backendVehicle,
    required this.subVehicleTypeId, required this.wheelCount, required this.category,
    required this.icon, required this.imagePath, required this.capacity,
  });

  factory _VehicleChoice.empty() => const _VehicleChoice(
    key:'', label:'', backendVehicle: null, subVehicleTypeId:'', wheelCount:2,
    category:'2W', icon: Icons.two_wheeler, imagePath:'', capacity:'',
  );
}

// ── Feature 11: Schedule Booking Panel ───────────────────────────────────────
class _ScheduleBookingPanel extends StatelessWidget {
  final bool isScheduled;
  final DateTime? selectedDate;
  final Map<String, dynamic>? selectedSlot;
  final ValueChanged<bool> onToggle;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<Map<String, dynamic>> onSlotSelected;

  const _ScheduleBookingPanel({
    required this.isScheduled, required this.selectedDate, required this.selectedSlot,
    required this.onToggle, required this.onDateSelected, required this.onSlotSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => onToggle(!isScheduled),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isScheduled ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isScheduled ? const Color(0xFF4CAF50) : Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 18,
                    color: isScheduled ? const Color(0xFF2E7D32) : Colors.grey.shade600),
                const SizedBox(width: 10),
                Expanded(child: Text('Schedule for later',
                    style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 14, fontWeight: FontWeight.w500,
                        color: isScheduled ? const Color(0xFF2E7D32) : Colors.grey.shade700))),
                Switch.adaptive(value: isScheduled, onChanged: onToggle, activeColor: const Color(0xFF4CAF50)),
              ],
            ),
          ),
        ),
        if (isScheduled) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(context: context,
                  initialDate: now.add(const Duration(hours: 1)),
                  firstDate: now, lastDate: now.add(const Duration(days: 30)));
              if (picked != null) onDateSelected(picked);
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300)),
              child: Row(children: [
                const Icon(Icons.today_rounded, size: 18, color: AppColor.themeColor),
                const SizedBox(width: 10),
                Text(selectedDate == null ? 'Select pickup date' : '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}',
                    style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13,
                        color: selectedDate == null ? Colors.grey.shade500 : AppColor.blackColor)),
                const Spacer(),
                Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
              ]),
            ),
          ),
          if (selectedDate != null) ...[
            const SizedBox(height: 8),
            Consumer<SlotController>(
              builder: (ctx, slotCtrl, _) {
                if (slotCtrl.isLoading) {
                  return const Center(child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: CircularProgressIndicator(strokeWidth: 2)));
                }
                if (slotCtrl.slots.isEmpty) {
                  return Padding(padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text('No slots available for selected date',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontFamily: AppFont.fontFamily)));
                }
                return Wrap(
                  spacing: 8, runSpacing: 6,
                  children: slotCtrl.slots.map((slot) {
                    final isSelected = selectedSlot?['slot'] == slot['slot'];
                    return GestureDetector(
                      onTap: () => onSlotSelected(Map<String, dynamic>.from(slot)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColor.themeColor : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isSelected ? AppColor.themeColor : Colors.grey.shade300),
                        ),
                        child: Text('${slot['slot']}  ${slot['start_time']}–${slot['end_time']}',
                            style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isSelected ? Colors.white : AppColor.blackColor)),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}
