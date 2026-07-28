import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:movigo/Controller/get_vehicle_list_provider.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/utilities/fare_calculator.dart';
import 'multi_drop_location_screen.dart';

class MultiDropVehicleScreen extends StatefulWidget {
  final LatLng pickupLatLng;
  final String pickupAddress;
  final List<MultiDropEntry> drops;

  const MultiDropVehicleScreen({
    super.key,
    required this.pickupLatLng,
    required this.pickupAddress,
    required this.drops,
  });

  @override
  State<MultiDropVehicleScreen> createState() => _MultiDropVehicleScreenState();
}

class _MultiDropVehicleScreenState extends State<MultiDropVehicleScreen> {
  GoogleMapController? _mapController;
  Set<Polyline>       _polylines = {};
  late Set<Marker>    _markers;
  VehicleTypeController? _vcRef;

  // ── Distance: TOTAL sequential route (pickup→drop1→drop2→...→finalDrop) ──────
  double _totalKm      = 0;
  String _durationText = '';
  bool   _routeLoading = true;
  bool   _routeReady   = false;
  bool   _mapReady     = false;

  // ── Fare ────────────────────────────────────────────────────────────────────
  String? _selectedKey;
  final Map<String, int> _fareByKey   = {};
  final Set<String>      _fareLoading = {};
  double _fareKm             = 0;
  bool   _estimatesStarted   = false;

  // ── Booking ──────────────────────────────────────────────────────────────────
  bool _isBooking = false;

  // Final drop = last in the list
  MultiDropEntry get _finalDrop => widget.drops.last;

  @override
  void initState() {
    super.initState();
    _buildMarkers();
    _totalKm     = _haversineTotal();
    _durationText = _estDuration(_totalKm);
    _fetchRoute();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vc = Provider.of<VehicleTypeController>(context, listen: false);
      _vcRef = vc;
      if (vc.vehicleTypes.isEmpty) {
        vc.getVehicleTypeList(context);
      } else {
        _kick();
      }
      vc.addListener(_onVcChanged);
    });
  }

  @override
  void dispose() {
    _vcRef?.removeListener(_onVcChanged);
    _mapController?.dispose();
    super.dispose();
  }

  void _onVcChanged() { if (mounted) _kick(); }

  void _kick() {
    final vc      = Provider.of<VehicleTypeController>(context, listen: false);
    final choices = _buildChoices(vc.vehicleTypes);
    if (choices.isEmpty) return;
    _ensureFares(choices);
    _autoSelect(choices);
  }

  // ── Markers ──────────────────────────────────────────────────────────────────
  void _buildMarkers() {
    _markers = {
      Marker(
        markerId: const MarkerId('pickup'),
        position: widget.pickupLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: 'Pickup', snippet: widget.pickupAddress),
      ),
    };
    for (int i = 0; i < widget.drops.length; i++) {
      final isFinal = i == widget.drops.length - 1;
      _markers.add(Marker(
        markerId: MarkerId('drop_$i'),
        position: widget.drops[i].latLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(
            isFinal ? BitmapDescriptor.hueRed : BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: isFinal ? 'Final Drop' : 'Drop ${i + 1}',
          snippet: widget.drops[i].address,
        ),
      ));
    }
  }

  // ── Google Directions with waypoints ─────────────────────────────────────────
  Future<void> _fetchRoute() async {
    if (mounted) setState(() => _routeLoading = true);
    try {
      // Intermediate stops = all drops except the last one
      final intermediates = widget.drops.sublist(0, widget.drops.length - 1);
      final waypointsParam = intermediates.isNotEmpty
          ? '&waypoints=${intermediates.map((d) => '${d.latLng!.latitude},${d.latLng!.longitude}').join('|')}'
          : '';

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${widget.pickupLatLng.latitude},${widget.pickupLatLng.longitude}'
        '&destination=${_finalDrop.latLng!.latitude},${_finalDrop.latLng!.longitude}'
        '$waypointsParam'
        '&mode=driving&key=${AppConstant.googleApiKey}',
      );

      final res = await http.get(url).timeout(const Duration(seconds: 10),
          onTimeout: () => throw Exception('timeout'));
      if (!mounted) return;

      final data   = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List? ?? [];

      if (routes.isNotEmpty) {
        final route = routes.first as Map<String, dynamic>;
        final legs  = route['legs'] as List? ?? [];
        double totalMeters = 0;
        int    totalSecs   = 0;
        for (final leg in legs) {
          totalMeters += ((leg['distance']?['value'] as num?) ?? 0).toDouble();
          totalSecs   += ((leg['duration']?['value'] as num?) ?? 0).toInt();
        }
        final encoded = route['overview_polyline']?['points'] as String?;
        final points  = encoded != null ? _decodePolyline(encoded) : <LatLng>[];
        final newKm   = totalMeters > 0 ? totalMeters / 1000.0 : _haversineTotal();
        final mins    = (totalSecs / 60).ceil();
        final durText = mins < 60 ? '$mins min' : '${(mins / 60).floor()}h ${mins % 60}min';

        setState(() {
          _totalKm      = newKm;
          _durationText  = durText;
          _polylines     = points.isEmpty ? {} : {
            Polyline(
              polylineId: const PolylineId('route'),
              points: points, color: AppColor.themeColor, width: 5,
              startCap: Cap.roundCap, endCap: Cap.roundCap, jointType: JointType.round,
            ),
          };
          _routeLoading = false;
          _routeReady   = true;
        });
        _invalidateFares();
        if (_mapReady) _fitBounds();
        _kick();
      } else {
        setState(() { _routeLoading = false; _routeReady = true; });
        _kick();
      }
    } catch (_) {
      if (mounted) { setState(() { _routeLoading = false; _routeReady = true; }); _kick(); }
    }
  }

  // ── Fares ────────────────────────────────────────────────────────────────────
  void _invalidateFares() {
    _fareByKey.clear(); _fareLoading.clear(); _fareKm = 0; _estimatesStarted = false;
  }

  void _ensureFares(List<_Choice> choices) {
    if (!mounted || !_routeReady || _totalKm <= 0 || AppConstant.token.isEmpty) return;
    if (_fareKm > 0 && (_totalKm - _fareKm).abs() > 0.3) _invalidateFares();
    if (!_estimatesStarted && choices.any((c) => c.backend != null)) _estimatesStarted = true;

    for (final c in choices) {
      if (c.backend == null || _fareByKey.containsKey(c.key) || _fareLoading.contains(c.key)) continue;
      _fareLoading.add(c.key);
      if (_fareKm == 0) _fareKm = _totalKm;

      final vehicleTypeId = (c.backend!['_id'] ?? '').toString();
      final subTypes = (c.backend!['sub_types'] as List?) ?? [];
      final subId    = subTypes.isNotEmpty ? (subTypes.first['_id'] ?? '').toString() : '';
      final capturedKm = _totalKm;

      http.post(
        Uri.parse('${AppConstant.apiBaseUrl}booking/price_estimate'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${AppConstant.token}'},
        body: jsonEncode({
          'vehicleType_id':      vehicleTypeId,
          'subVehicleType_id':   subId,
          'pickup_lat':  widget.pickupLatLng.latitude.toString(),
          'pickup_lng':  widget.pickupLatLng.longitude.toString(),
          // Use final drop coordinates for the distance calculation override via raw_distance_km
          'drop_lat':    _finalDrop.latLng!.latitude.toString(),
          'drop_lng':    _finalDrop.latLng!.longitude.toString(),
          'requested_vehicle_name': c.label,
          'vehicle_key':  c.key,
          'required_tag': c.key,
          // Pass total sequential km — this overrides haversine in calculatePrice
          'raw_distance_km': capturedKm.toStringAsFixed(3),
        }),
      ).then((res) {
        if (!mounted) return;
        if ((capturedKm - _totalKm).abs() > 0.3) { setState(() => _fareLoading.remove(c.key)); return; }
        int total = 0;
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            final d = jsonDecode(res.body);
            if (d['success'] == true) {
              final pb = d['data']?['price_breakup'];
              if (pb is Map && pb['total_with_platform_fee'] != null) {
                total = num.tryParse(pb['total_with_platform_fee'].toString())?.ceil() ?? 0;
              }
            }
          } catch (_) {}
        }
        setState(() {
          _fareLoading.remove(c.key);
          if (total > 0) _fareByKey[c.key] = total;
        });
      }).catchError((_) { if (mounted) setState(() => _fareLoading.remove(c.key)); });
    }
  }

  int? _fareFor(_Choice c) {
    final cached = _fareByKey[c.key];
    if (cached != null) return cached;
    if (!_routeReady || !_estimatesStarted || _fareLoading.contains(c.key)) return null;
    if (_totalKm > 0) {
      return FareCalculator.calculate(wheelCount: c.wheelCount, rawDistanceKm: _totalKm, requiredTag: c.key).totalPayable;
    }
    return null;
  }

  bool _isLoading(_Choice c) {
    if (!_routeReady) return true;
    if (!_estimatesStarted && c.backend != null) return true;
    return _fareLoading.contains(c.key);
  }

  // ── Map helpers ──────────────────────────────────────────────────────────────
  void _fitBounds() {
    if (_mapController == null) return;
    final lats = [widget.pickupLatLng.latitude,  ...widget.drops.map((d) => d.latLng!.latitude)];
    final lngs = [widget.pickupLatLng.longitude, ...widget.drops.map((d) => d.latLng!.longitude)];
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(lats.reduce(math.min), lngs.reduce(math.min)),
        northeast: LatLng(lats.reduce(math.max), lngs.reduce(math.max)),
      ), 80,
    ));
  }

  List<LatLng> _decodePolyline(String encoded) {
    final pts = <LatLng>[]; int idx = 0; int lat = 0; int lng = 0;
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

  double _haversineTotal() {
    final pts = [widget.pickupLatLng, ...widget.drops.map((d) => d.latLng!)];
    double total = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      final a = pts[i]; final b = pts[i + 1];
      const r = 6371.0;
      final dLat = _r(b.latitude - a.latitude);
      final dLng = _r(b.longitude - a.longitude);
      final h = math.sin(dLat/2)*math.sin(dLat/2) +
          math.cos(_r(a.latitude))*math.cos(_r(b.latitude))*math.sin(dLng/2)*math.sin(dLng/2);
      total += r * 2 * math.atan2(math.sqrt(h), math.sqrt(1-h));
    }
    return total;
  }

  double _r(double d) => d * math.pi / 180.0;
  String _estDuration(double km) => '${math.max(5, (km / 22 * 60).ceil())} min';

  // ── Vehicle choices (same tags as RouteVehicleScreen) ────────────────────────
  Map<String, dynamic>? _findBackend(List<dynamic> vehicles, int wc, {bool pickup = false}) {
    if (vehicles.isEmpty) return null;
    final pool = vehicles.whereType<Map>().map((v) => Map<String, dynamic>.from(v))
        .where((v) { final n = (v['name']??'').toString().toLowerCase(); return !n.contains('large') && !n.contains('truck'); }).toList();
    final src  = pool.isEmpty ? vehicles.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList() : pool;
    final exact = src.where((v) => _wc((v['name']??'').toString()) == wc).toList();
    if (exact.isEmpty) return src.isNotEmpty ? src.first : null;
    if (pickup) {
      final pm = exact.where((v) { final n=(v['name']??'').toString().toLowerCase(); return n.contains('pickup')||n.contains('ace')||n.contains('tata'); }).toList();
      if (pm.isNotEmpty) return pm.first;
    }
    return exact.first;
  }

  int _wc(String name) {
    final n = name.toLowerCase();
    if (n.contains('2')||n.contains('two')||n.contains('bike')||n.contains('scooter')) return 2;
    if (n.contains('3')||n.contains('three')||n.contains('auto')||n.contains('rickshaw')||n.contains('loader')||n.contains('electric')) return 3;
    if (n.contains('4')||n.contains('four')||n.contains('car')||n.contains('pickup')||n.contains('tata')||n.contains('ace')) return 4;
    return 2;
  }

  List<_Choice> _buildChoices(List<dynamic> vehicles) {
    if (vehicles.isEmpty) return [];
    _Choice ch({required String key, required String label, required int wc,
        required String cat, required String img, required String cap, bool pickup = false}) {
      final backend = _findBackend(vehicles, wc, pickup: pickup);
      final subs    = (backend?['sub_types'] as List?) ?? [];
      final subId   = subs.isNotEmpty ? (subs.first['_id']??'').toString() : '';
      return _Choice(key: key, label: label, backend: backend, subId: subId,
          wheelCount: wc, category: cat, imagePath: img, capacity: cap);
    }
    return [
      ch(key: 'R_2W',       label: 'Bike / 2W',      wc: 2, cat: '2W',    img: AppImage.bike,         cap: 'Up to 20 kg'),
      ch(key: 'R_SCOOTER',  label: 'E-Scooter',      wc: 2, cat: '2W',    img: AppImage.twowheel,     cap: 'Up to 20 kg'),
      ch(key: 'R_MINI_3W',  label: 'Mini 3-Wheeler', wc: 3, cat: '3W',    img: AppImage.mini3w,       cap: 'Up to 90 kg'),
      ch(key: 'R_E_LOADER', label: 'E-Loader',       wc: 3, cat: '3W',    img: AppImage.eloader,      cap: 'Up to 300 kg'),
      ch(key: 'R_3W',       label: '3 Wheeler',      wc: 3, cat: '3W',    img: AppImage.threewheeler, cap: 'Up to 500 kg'),
      ch(key: 'R_TATA_ACE', label: 'Tata Ace',       wc: 4, cat: 'Pickup',img: AppImage.minitruck,    cap: 'Up to 800 kg', pickup: true),
    ];
  }

  void _autoSelect(List<_Choice> choices) {
    if (_selectedKey != null || choices.isEmpty) return;
    Future.microtask(() { if (mounted && _selectedKey == null) setState(() => _selectedKey = choices.first.key); });
  }

  // ── Show confirm sheet before booking ────────────────────────────────────────
  Future<void> _bookNow() async {
    final vc      = Provider.of<VehicleTypeController>(context, listen: false);
    final choices = _buildChoices(vc.vehicleTypes);
    if (choices.isEmpty) { SnackBarToastMessage.showSnackBar(context, 'Vehicle data loading. Please wait.'); return; }

    final choice = choices.firstWhere((c) => c.key == _selectedKey, orElse: () => choices.first);
    if (choice.backend == null) { SnackBarToastMessage.showSnackBar(context, 'Vehicle not available.'); return; }

    final fare = _fareFor(choice);
    if (fare == null || fare <= 0) { SnackBarToastMessage.showSnackBar(context, 'Fare is being calculated. Please wait.'); return; }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConfirmSheet(
        pickupAddress: widget.pickupAddress,
        drops:         widget.drops,
        choice:        choice,
        fare:          fare,
        totalKm:       _totalKm,
        durationText:  _durationText,
      ),
    );
    if (confirmed != true || !mounted) return;
    await _createBooking(choice, fare);
  }

  // ── Actual booking API call ───────────────────────────────────────────────────
  Future<void> _createBooking(_Choice choice, int fare) async {
    final subTypes = (choice.backend!['sub_types'] as List?) ?? [];
    final subId    = choice.subId.isNotEmpty ? choice.subId : (subTypes.isNotEmpty ? (subTypes.first['_id']??'').toString() : '');
    if (subId.isEmpty) { SnackBarToastMessage.showSnackBar(context, 'Vehicle sub-type missing.'); return; }

    setState(() => _isBooking = true);
    try {
      // ALL drops in order — backend stores these; final drop = dropoff_location
      final extraDropsPayload = widget.drops.map((d) => {
        'address':       d.address,
        'latitude':      d.latLng!.latitude,
        'longitude':     d.latLng!.longitude,
        'contact_name':  d.contactName,
        'contact_phone': d.contactPhone,
      }).toList();

      final body = <String, dynamic>{
        'vehicleType_id':         (choice.backend!['_id'] ?? '').toString(),
        'subVehicleType_id':      subId,
        'pickup_address':         widget.pickupAddress,
        'pickup_lat':             widget.pickupLatLng.latitude,
        'pickup_lng':             widget.pickupLatLng.longitude,
        // Final destination = last drop
        'drop_address':           _finalDrop.address,
        'drop_lat':               _finalDrop.latLng!.latitude,
        'drop_lng':               _finalDrop.latLng!.longitude,
        'receiver_name':          _finalDrop.contactName,
        'receiver_phone':         _finalDrop.contactPhone,
        'booking_type':           'Now',
        'payment_mode':           'Cash',
        'required_tag':           choice.key,
        'vehicle_key':            choice.key,
        'requested_vehicle_name': choice.label,
        'display_vehicle_name':   choice.label,
        'vehicle_category':       choice.category,
        // Total sequential distance — backend uses this for pricing
        'raw_distance_km':        double.parse(_totalKm.toStringAsFixed(3)),
        'is_multidrop':           true,
        // All drops in sequence (including final) for driver to follow
        'extra_drops':            extraDropsPayload,
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
        _showSuccess(booking, fare, choice);
      } else {
        final msg = (data['message'] as List?)?.first?.toString() ?? 'Booking failed.';
        SnackBarToastMessage.showSnackBar(context, msg);
      }
    } catch (e) {
      if (mounted) SnackBarToastMessage.showSnackBar(context, 'Booking failed. Check connection.');
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  void _showSuccess(Map<String, dynamic> booking, int fare, _Choice choice) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent, isDismissible: false,
      builder: (_) => _SuccessSheet(
        drops: widget.drops,
        bookingCode: (booking['booking_code'] ?? '—').toString(),
        totalFare: fare,
        vehicleLabel: choice.label,
        totalKm: _totalKm,
        onDone: () {
          int count = 3;
          Navigator.of(context)
            ..pop()
            ..popUntil((route) { count--; return count <= 0 || route.isFirst; });
        },
      ),
    );
  }

  // ── BUILD ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(
                (widget.pickupLatLng.latitude  + _finalDrop.latLng!.latitude)  / 2,
                (widget.pickupLatLng.longitude + _finalDrop.latLng!.longitude) / 2,
              ),
              zoom: 11,
            ),
            markers: _markers, polylines: _polylines,
            myLocationButtonEnabled: false, zoomControlsEnabled: false,
            onMapCreated: (c) { _mapController = c; _mapReady = true; if (!_routeLoading) _fitBounds(); },
          ),

          // ── Back ─────────────────────────────────────────────────────────────
          SafeArea(child: Padding(padding: const EdgeInsets.all(12),
            child: GestureDetector(
              onTap: () => Navigator.maybePop(context),
              child: Container(height: 42, width: 42,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 6, offset: const Offset(0,2))]),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87, size: 16)),
            ),
          )),

          // ── Bottom panel ─────────────────────────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: Consumer<VehicleTypeController>(
              builder: (ctx, vc, _) {
                final choices = _buildChoices(vc.vehicleTypes);
                if (_routeReady && choices.isNotEmpty) _ensureFares(choices);

                return Container(
                  decoration: const BoxDecoration(color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.60),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    // Handle
                    Center(child: Container(margin: const EdgeInsets.only(top: 10, bottom: 8),
                        width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),

                    // ── Route summary bar ─────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: const Color(0xFF0F0F1E).withOpacity(0.03),
                            borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.withOpacity(0.1))),
                        child: Row(children: [
                          _stat(Icons.route_rounded, '${_totalKm.toStringAsFixed(1)} km', 'Total distance'),
                          _vline(),
                          _stat(Icons.schedule_rounded, _durationText, 'Est. time'),
                          _vline(),
                          _stat(Icons.location_on_rounded, '${widget.drops.length} stops', 'Drop points'),
                        ]),
                      ),
                    ),

                    // ── Stops preview ─────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: _StopsPreview(pickupAddress: widget.pickupAddress, drops: widget.drops),
                    ),

                    // ── Vehicle 3D carousel ───────────────────────────────────
                    if (choices.isEmpty)
                      const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                    else
                      _VehicleCarousel(
                        choices:     choices,
                        selectedKey: _selectedKey,
                        fareByKey:   _fareByKey,
                        fareLoading: _fareLoading,
                        onSelect:    (k) => setState(() => _selectedKey = k),
                      ),

                    // ── Book button ───────────────────────────────────────────
                    _buildBookButton(choices),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String val, String lbl) => Expanded(child: Column(children: [
    Icon(icon, size: 15, color: AppColor.themeColor),
    const SizedBox(height: 2),
    Text(val, style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black87)),
    Text(lbl, style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 9, color: Colors.grey[500])),
  ]));

  Widget _vline() => Container(width: 1, height: 30, color: Colors.grey.withOpacity(0.15));

  Widget _buildBookButton(List<_Choice> choices) {
    if (choices.isEmpty) return const SizedBox.shrink();
    final current = choices.firstWhere((c) => c.key == _selectedKey, orElse: () => choices.first);
    final fare    = _fareFor(current);

    return Container(
      decoration: BoxDecoration(color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, -2))]),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      child: Row(children: [
        if (fare != null) ...[
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_totalKm.toStringAsFixed(1)} km total', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 10, color: Colors.grey[500])),
            Text('₹$fare', style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87)),
          ]),
          const SizedBox(width: 12),
        ],
        Expanded(child: SizedBox(height: 50,
          child: ElevatedButton(
            onPressed: (_isBooking || choices.isEmpty) ? null : _bookNow,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColor.themeColor,
              disabledBackgroundColor: AppColor.themeColor.withOpacity(0.45),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0,
            ),
            child: _isBooking
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text('Book Multi-Drop  (${widget.drops.length} stops)',
                    style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        )),
      ]),
    );
  }
}

// ── Stops preview strip ───────────────────────────────────────────────────────
class _StopsPreview extends StatelessWidget {
  final String pickupAddress;
  final List<MultiDropEntry> drops;
  const _StopsPreview({required this.pickupAddress, required this.drops});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.12))),
      child: Column(children: [
        _stop(Icons.my_location_rounded, const Color(0xFF43E97B), pickupAddress, 'Pickup', false),
        ...List.generate(drops.length, (i) {
          final isFinal = i == drops.length - 1;
          return _stop(
            Icons.location_on_rounded,
            isFinal ? const Color(0xFFFF6B6B) : const Color(0xFFFF9A3C),
            drops[i].address,
            isFinal ? 'Final drop' : 'Drop ${i + 1}',
            isFinal,
          );
        }),
      ]),
    );
  }

  Widget _stop(IconData icon, Color color, String address, String label, bool isLast) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 12)),
        if (!isLast) Container(width: 1.5, height: 18, color: Colors.grey.withOpacity(0.2)),
      ]),
      const SizedBox(width: 10),
      Expanded(child: Padding(padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 9, fontWeight: FontWeight.w700,
              color: color, letterSpacing: 0.5)),
          Text(address, style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11.5, color: Colors.black87),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      )),
    ]);
  }
}

// ── Vehicle 3D Carousel ───────────────────────────────────────────────────────
class _VehicleCarousel extends StatefulWidget {
  final List<_Choice>    choices;
  final String?          selectedKey;
  final Map<String, int> fareByKey;
  final Set<String>      fareLoading;
  final ValueChanged<String> onSelect;

  const _VehicleCarousel({
    required this.choices, required this.selectedKey,
    required this.fareByKey, required this.fareLoading, required this.onSelect,
  });

  @override
  State<_VehicleCarousel> createState() => _VehicleCarouselState();
}

class _VehicleCarouselState extends State<_VehicleCarousel> {
  late PageController _ctrl;

  @override
  void initState() {
    super.initState();
    final idx = widget.choices.indexWhere((c) => c.key == widget.selectedKey);
    _ctrl = PageController(viewportFraction: 0.82, initialPage: idx.clamp(0, widget.choices.length - 1));
  }

  @override
  void didUpdateWidget(_VehicleCarousel old) {
    super.didUpdateWidget(old);
    if (widget.selectedKey != old.selectedKey) {
      final idx = widget.choices.indexWhere((c) => c.key == widget.selectedKey);
      if (idx >= 0 && _ctrl.hasClients && _ctrl.page?.round() != idx) {
        _ctrl.animateToPage(idx, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
      }
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 136,
          child: PageView.builder(
            controller: _ctrl,
            onPageChanged: (i) => widget.onSelect(widget.choices[i].key),
            itemCount: widget.choices.length,
            itemBuilder: (_, i) => AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                double offset = 0;
                try { offset = (_ctrl.page ?? 0) - i; } catch (_) {}
                final tiltY   = offset.clamp(-1.0, 1.0) * 0.30;
                final driftY  = offset.abs().clamp(0.0, 1.0) * 14.0;
                final scale   = (1.0 - offset.abs() * 0.09).clamp(0.84, 1.0);
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(tiltY)
                    ..translate(0.0, driftY)
                    ..scale(scale),
                  child: _Vehicle3DCard(
                    choice:     widget.choices[i],
                    isSelected: widget.selectedKey == widget.choices[i].key,
                    fare:       widget.fareByKey[widget.choices[i].key],
                    isLoading:  widget.fareLoading.contains(widget.choices[i].key),
                  ),
                );
              },
            ),
          ),
        ),
        // Dot indicators
        if (widget.choices.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.choices.length, (i) {
                final active = widget.selectedKey == widget.choices[i].key;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFF1A3A6B) : const Color(0xFFD0DCF0),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

// ── Vehicle 3D Card ───────────────────────────────────────────────────────────
class _Vehicle3DCard extends StatelessWidget {
  final _Choice choice;
  final bool    isSelected;
  final int?    fare;
  final bool    isLoading;

  const _Vehicle3DCard({required this.choice, required this.isSelected,
      required this.fare, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    const navy   = Color(0xFF1A3A6B);
    const navyDk = Color(0xFF0D2137);

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF0F5FF) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? navy : const Color(0xFFE8ECF2),
          width: isSelected ? 2.0 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected ? navy.withOpacity(0.20) : Colors.black.withOpacity(0.07),
            blurRadius: isSelected ? 20 : 8,
            offset: Offset(0, isSelected ? 8 : 3),
            spreadRadius: isSelected ? 1 : 0,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Row(
          children: [
            // Vehicle image with pop-out shadow blob
            SizedBox(
              width: 78,
              height: 72,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // Shadow ellipse under vehicle — creates "floating" illusion
                  Positioned(
                    bottom: 2,
                    child: Container(
                      width: 56,
                      height: 7,
                      decoration: BoxDecoration(
                        color: navy.withOpacity(isSelected ? 0.18 : 0.07),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  // Vehicle image floats upward
                  Positioned(
                    top: 0,
                    child: Transform.translate(
                      offset: const Offset(0, -4),
                      child: Image.asset(choice.imagePath, height: 60, fit: BoxFit.contain),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Vehicle name + capacity
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(choice.label,
                      style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 14,
                          fontWeight: FontWeight.w800, color: isSelected ? navy : navyDk)),
                  const SizedBox(height: 3),
                  Row(children: [
                    Icon(Icons.inventory_2_outlined, size: 11, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(choice.capacity,
                          style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 10, color: Colors.grey[500]),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                  if (isSelected) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: navy.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_circle_rounded, size: 10, color: navy),
                        SizedBox(width: 4),
                        Text('Selected', style: TextStyle(fontFamily: AppFont.fontFamily,
                            fontSize: 9, fontWeight: FontWeight.w700, color: navy)),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
            // Fare
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                isLoading
                    ? SizedBox(
                        width: 52,
                        child: LinearProgressIndicator(
                          color: navy, backgroundColor: navy.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(3)))
                    : Text(fare != null ? '₹$fare' : '—',
                        style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 20,
                            fontWeight: FontWeight.w900, color: isSelected ? navy : navyDk)),
                Text('est.', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 9.5, color: Colors.grey[400])),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Confirm sheet (shown BEFORE booking is created) ───────────────────────────
class _ConfirmSheet extends StatelessWidget {
  final String           pickupAddress;
  final List<MultiDropEntry> drops;
  final _Choice          choice;
  final int              fare;
  final double           totalKm;
  final String           durationText;

  const _ConfirmSheet({
    required this.pickupAddress,
    required this.drops,
    required this.choice,
    required this.fare,
    required this.totalKm,
    required this.durationText,
  });

  @override
  Widget build(BuildContext context) {
    const navy   = Color(0xFF1A3A6B);
    const navyDk = Color(0xFF0D2137);
    const bg     = Color(0xFFF4F6FA);
    const border = Color(0xFFE8ECF2);
    const muted  = Color(0xFF8A94A6);
    const red    = Color(0xFFE53935);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 10, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 38, height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)),
              ),
            ),

            // Title
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: navy.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.receipt_long_rounded, color: navy, size: 18),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Confirm Booking',
                      style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 17, fontWeight: FontWeight.w800, color: navyDk)),
                  Text('Review your details before booking',
                      style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, color: muted)),
                ],
              ),
            ]),
            const SizedBox(height: 20),

            // ── Route card ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Column(children: [
                _routeRow(navy, Icons.my_location_rounded, 'PICKUP', pickupAddress, false),
                ...List.generate(drops.length, (i) {
                  final isFinal = i == drops.length - 1;
                  final dot = isFinal ? red : const Color(0xFFF59E0B);
                  final label = isFinal ? 'FINAL DROP' : 'DROP ${i + 1}';
                  final contact = drops[i].contactName.isNotEmpty
                      ? '${drops[i].contactName}${drops[i].contactPhone.isNotEmpty ? ' · ${drops[i].contactPhone}' : ''}'
                      : '';
                  return _routeRow(dot, Icons.location_on_rounded, label, drops[i].address, isFinal, contact: contact);
                }),
              ]),
            ),
            const SizedBox(height: 14),

            // ── Vehicle + fare card ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Row(children: [
                Container(
                  width: 56, height: 44,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: border)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(choice.imagePath, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(choice.label,
                      style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 14, fontWeight: FontWeight.w700, color: navyDk)),
                  Text(choice.capacity,
                      style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11, color: muted)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('₹$fare',
                      style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 22, fontWeight: FontWeight.w900, color: navyDk)),
                  const Text('estimated fare',
                      style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 10, color: muted)),
                ]),
              ]),
            ),
            const SizedBox(height: 14),

            // ── Trip stats row ───────────────────────────────────────────────
            Row(children: [
              _statChip(bg, border, Icons.route_rounded, '${totalKm.toStringAsFixed(1)} km', 'Distance'),
              const SizedBox(width: 8),
              _statChip(bg, border, Icons.schedule_rounded, durationText, 'Est. time'),
              const SizedBox(width: 8),
              _statChip(bg, border, Icons.location_on_rounded, '${drops.length} stops', 'Drop points'),
            ]),
            const SizedBox(height: 14),

            // ── Payment mode ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border),
              ),
              child: const Row(children: [
                Icon(Icons.payments_outlined, color: navy, size: 18),
                SizedBox(width: 10),
                Text('Payment Mode',
                    style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, color: navyDk, fontWeight: FontWeight.w600)),
                Spacer(),
                Text('Cash on Delivery',
                    style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, fontWeight: FontWeight.w700, color: navy)),
              ]),
            ),
            const SizedBox(height: 24),

            // ── Buttons ──────────────────────────────────────────────────────
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: border, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Go Back',
                      style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 14, fontWeight: FontWeight.w700, color: muted)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: navy,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bolt_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text('Confirm & Book',
                          style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _routeRow(Color dot, IconData icon, String label, String address, bool isLast, {String contact = ''}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: dot.withOpacity(0.12), shape: BoxShape.circle),
          child: Icon(icon, color: dot, size: 12),
        ),
        if (!isLast) Container(width: 1.5, height: contact.isNotEmpty ? 32 : 22, color: const Color(0xFFE8ECF2)),
      ]),
      const SizedBox(width: 10),
      Expanded(
        child: Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 9.5, fontWeight: FontWeight.w700,
                    color: dot.withOpacity(0.8), letterSpacing: 0.5)),
            const SizedBox(height: 1),
            Text(address,
                style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, color: Color(0xFF0D2137), height: 1.3),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            if (contact.isNotEmpty)
              Text(contact,
                  style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11, color: Color(0xFF8A94A6)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    ]);
  }

  Widget _statChip(Color bg, Color border, IconData icon, String val, String lbl) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
      child: Column(children: [
        Icon(icon, size: 14, color: const Color(0xFF1A3A6B)),
        const SizedBox(height: 3),
        Text(val, style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0D2137))),
        Text(lbl, style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 9.5, color: Color(0xFF8A94A6))),
      ]),
    ),
  );
}

// ── Success sheet ─────────────────────────────────────────────────────────────
class _SuccessSheet extends StatelessWidget {
  final List<MultiDropEntry> drops;
  final String bookingCode, vehicleLabel;
  final int    totalFare;
  final double totalKm;
  final VoidCallback onDone;

  const _SuccessSheet({required this.drops, required this.bookingCode, required this.vehicleLabel,
      required this.totalFare, required this.totalKm, required this.onDone});

  @override
  Widget build(BuildContext context) {
    const navy   = Color(0xFF1A3A6B);
    const navyDk = Color(0xFF0D2137);
    const bg     = Color(0xFFF0F5FF);
    const border = Color(0xFFE8ECF2);
    const muted  = Color(0xFF8A94A6);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 14, 24, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)))),

        // Success icon
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.12), shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 44),
        ),
        const SizedBox(height: 14),
        const Text('Booking Confirmed!',
            style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 20, fontWeight: FontWeight.w900, color: navyDk)),
        const SizedBox(height: 4),
        Text('One driver will complete all ${drops.length} stops.',
            style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, color: muted)),
        const SizedBox(height: 18),

        // Booking code
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: navy.withOpacity(0.20)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('Booking # ', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, color: muted)),
            Text(bookingCode, style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 17,
                fontWeight: FontWeight.w900, color: navy)),
          ]),
        ),
        const SizedBox(height: 14),

        // Summary chips
        Row(children: [
          _chip(bg, border, Icons.route_rounded, '${totalKm.toStringAsFixed(1)} km', navy),
          const SizedBox(width: 8),
          _chip(bg, border, Icons.location_on_rounded, '${drops.length} stops', navy),
          const SizedBox(width: 8),
          _chip(bg, border, Icons.currency_rupee_rounded, '₹$totalFare', navy),
        ]),
        const SizedBox(height: 14),

        // Stops list
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
          child: Column(children: List.generate(drops.length, (i) {
            final isFinal = i == drops.length - 1;
            final dotColor = isFinal ? const Color(0xFFE53935) : const Color(0xFFF59E0B);
            return Padding(padding: EdgeInsets.only(bottom: i < drops.length - 1 ? 8 : 0),
              child: Row(children: [
                Container(width: 22, height: 22,
                  decoration: BoxDecoration(color: dotColor.withOpacity(0.12), shape: BoxShape.circle),
                  child: Center(child: Text('${i+1}', style: TextStyle(fontFamily: AppFont.fontFamily,
                      fontSize: 10, fontWeight: FontWeight.w800, color: dotColor)))),
                const SizedBox(width: 8),
                Expanded(child: Text(drops[i].address,
                    style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11.5, color: navyDk),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (isFinal)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFE53935).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(4)),
                    child: const Text('Final', style: TextStyle(fontFamily: AppFont.fontFamily,
                        fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFE53935)))),
              ]),
            );
          })),
        ),
        const SizedBox(height: 20),

        SizedBox(width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: onDone,
            style: ElevatedButton.styleFrom(
              backgroundColor: navy,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: const Text('Done', style: TextStyle(fontFamily: AppFont.fontFamily,
                fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ),
      ]),
    );
  }

  Widget _chip(Color bg, Color border, IconData icon, String text, Color navy) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
      child: Column(children: [
        Icon(icon, size: 14, color: navy),
        const SizedBox(height: 3),
        Text(text, style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11,
            fontWeight: FontWeight.w700, color: navy)),
      ]),
    ),
  );
}

// ── Data model ────────────────────────────────────────────────────────────────
class _Choice {
  final String key, label, subId, category, capacity, imagePath;
  final int    wheelCount;
  final Map<String, dynamic>? backend;
  const _Choice({required this.key, required this.label, required this.subId, required this.category,
      required this.capacity, required this.imagePath, required this.wheelCount, required this.backend});
}
