import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:movigo/utilities/app_config_provider.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/Provider/socket_connection/socket_provider.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/helper/map_style.dart';

/// Result of a route lookup — the polyline geometry plus the road-network
/// duration / distance pulled from the same Directions response (so the ETA
/// shown on screen is a real driving estimate, not a straight-line guess).
class _RouteResult {
  final List<LatLng> points;
  final int? durationSec;
  final double? distanceMeters;
  const _RouteResult(this.points, {this.durationSec, this.distanceMeters});
  bool get isEmpty => points.isEmpty;
}

class MapImageScreen extends StatefulWidget {
  var userId;
  var bookingId;
  var driverId;
  final String? vehicleName;
  final String? vehicleImage;
  final double? targetLat;
  final double? targetLng;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropLat;
  final double? dropLng;
  final String? bookingStatus;

  // Optional — shown in the redesigned bottom sheet when supplied by the caller.
  final String? driverName;
  final String? driverPhone;

  final bool isEmbed;

  MapImageScreen({
    super.key,
    required this.userId,
    this.bookingId,
    required this.driverId,
    this.vehicleName,
    this.vehicleImage,
    this.targetLat,
    this.targetLng,
    this.pickupLat,
    this.pickupLng,
    this.dropLat,
    this.dropLng,
    this.bookingStatus,
    this.driverName,
    this.driverPhone,
    this.isEmbed = false,
  });

  @override
  State<MapImageScreen> createState() => _MapImageState();
}

class _MapImageState extends State<MapImageScreen>
    with SingleTickerProviderStateMixin {
  double raduis = 1000.0;
  Timer? _timer;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polyline = {};
  Set<Circle> _circles = {};

  GoogleMapController? mapController;
  final Completer<GoogleMapController> _controller = Completer();
  LatLng initialPosition = const LatLng(22.7196, 75.8577);
  bool mapshow = false;
  Position? _currentPosition;
  TextEditingController controller = TextEditingController();
  double lat = 22.7196;
  double long = 75.8577;
  double latitudex = 22.7196;
  double longtitudex = 75.8577;
  var address;
  bool isApiCalling = false;

  // Enhanced tracking variables
  List<LatLng> routeCoords = [];
  String googleApiKey = AppConstant.googleApiKey;
  LatLng? previousDriverLocation;
  LatLng? userLocation;
  LatLng? driverLocation;
  LatLng? pickupLocation;
  LatLng? dropLocation;
  LatLng? _lastProcessedDriverLocation;
  double currentDistance = 0.0;
  double previousDistance = double.infinity;
  bool isDriverApproaching = false;
  int _etaMinutes = 0;
  // ETA is a simple distance ÷ constant-speed estimate — never the live traffic
  // duration. Uses the road-route distance when we have it, else straight-line.
  static const double _avgSpeedKmph = 22.0;
  double? _roadDistanceMeters;
  double autoZoomThreshold = 1000;
  String deliveryStatus = "Driver is on the way";
  BitmapDescriptor? _driverMarkerIcon;
  final Map<String, List<LatLng>> _routeCache = {};
  final Map<String, LatLng> _routeStartCache = {};
  final Map<String, LatLng> _routeEndCache = {};
  final Map<String, DateTime> _routeFetchedAt = {};
  final Map<String, bool> _routeFetching = {};
  final Map<String, _RouteResult> _routeMetaCache = {};
  DateTime? _lastCameraFitAt;
  bool _isManualRefreshing = false;
  static const Color _googleMapsBlue = Color(0xFF4285F4);

  // ── Redesign state ───────────────────────────────────────────────────────
  // The map auto-follows the driver until the retailer pans/zooms it once —
  // after that it stays where they left it until they tap "recenter".
  bool _userMovedMap = false;
  bool _programmaticMove = false;
  late final AnimationController _pulseCtrl;
  List<Map<String, dynamic>> _banners = [];
  final PageController _bannerPage = PageController();
  Timer? _bannerTimer;
  int _bannerIndex = 0;

  // Dotted line style shared by every polyline on the map.
  static final List<PatternItem> _dash = <PatternItem>[
    PatternItem.dash(20),
    PatternItem.gap(12),
  ];

  String get _resolvedBookingId =>
      (widget.bookingId?.toString().trim().isNotEmpty == true
          ? widget.bookingId.toString()
          : widget.driverId.toString());

  // "Finding a driver" phase — the map is pinned on pickup and frozen.
  bool get _isSearching {
    final s = (widget.bookingStatus ?? '').trim().toLowerCase();
    if (s.isEmpty) {
      return widget.driverId == null ||
          widget.driverId.toString().trim().isEmpty;
    }
    return s == 'pending' ||
        s == 'searching' ||
        s == 'requested' ||
        s == 'created' ||
        s.contains('finding') ||
        s.contains('searching');
  }

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    // Only track if booking is active (not yet Delivered or Cancelled)
    final status = widget.bookingStatus?.toLowerCase() ?? '';
    final isActive = status != 'delivered' && status != 'cancelled';

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensureTrackingReady();
      if (isActive && widget.bookingId != null && widget.bookingId.toString().isNotEmpty) {
        // Start Pusher live tracking
        final socketProvider = context.read<SocketProvider>();
        await socketProvider.startTrackingDriver(bookingId: widget.bookingId.toString());
      }
      await _emitDriverLocationRequest();
      _loadBanners();
    });

    // Fallback REST poll — Pusher handles real-time; this is only for
    // devices where Pusher drops. 30 s is plenty; 10 s was 3× over-polling.
    if (isActive) {
      _timer = Timer.periodic(const Duration(seconds: 30), (_) async {
        await _emitDriverLocationRequest();
        debugPrint("🔄 emitDriverLiveLocation polled");
      });
    }

    _markers.clear();
    _polyline.clear();
    _circles.clear();

    if (widget.pickupLat != null && widget.pickupLng != null) {
      pickupLocation = LatLng(widget.pickupLat!, widget.pickupLng!);
    }
    if (widget.dropLat != null && widget.dropLng != null) {
      dropLocation = LatLng(widget.dropLat!, widget.dropLng!);
    }

    if (_isSearching && pickupLocation != null) {
      initialPosition = pickupLocation!;
    } else if (widget.targetLat != null && widget.targetLng != null) {
      lat = widget.targetLat!;
      long = widget.targetLng!;
      initialPosition = LatLng(lat, long);
    } else if (dropLocation != null) {
      initialPosition = dropLocation!;
    } else if (pickupLocation != null) {
      initialPosition = pickupLocation!;
    }

    _renderStaticLocationMarkers();
    mapshow = true;
    _loadDriverMarkerIcon();
  }

  Future<void> _loadBanners() async {
    try {
      final provider = Provider.of<PostApiProvider>(context, listen: false);
      final res = await provider.getPromoBannersApi(context);
      final list = (res?['data'] as List?) ?? [];
      if (!mounted) return;
      setState(() {
        _banners = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((b) => (b['image'] ?? '').toString().isNotEmpty)
            .toList();
      });
      if (_banners.length > 1) {
        _bannerTimer?.cancel();
        _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
          if (!mounted || !_bannerPage.hasClients || _banners.isEmpty) return;
          _bannerIndex = (_bannerIndex + 1) % _banners.length;
          _bannerPage.animateToPage(_bannerIndex,
              duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
        });
      }
    } catch (_) {}
  }

  void _renderStaticLocationMarkers() {
    _markers.clear();
    if (pickupLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId("pickup_location"),
          position: pickupLocation!,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: "Pickup"),
        ),
      );
    }
    if (dropLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId("drop_location"),
          position: dropLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: "Drop"),
        ),
      );
    }
  }

  Future<void> _ensureTrackingReady() async {
    await _handleLocationPermission();
    final socketProvider = context.read<SocketProvider>();
    if (!socketProvider.isConnected) {
      await socketProvider.initSocket(AppConstant.token);
      await Future.delayed(const Duration(milliseconds: 600));
    }
  }

  Future<void> _emitDriverLocationRequest() async {
    if (!mounted) return;
    await _ensureTrackingReady();
    final socketProvider = context.read<SocketProvider>();
    socketProvider.emitDriverLiveLocation(
      userId: widget.userId.toString(),
      bookingId: _resolvedBookingId,
    );
  }

  Future<void> _loadDriverMarkerIcon() async {
    final imageName = widget.vehicleImage?.toString().trim() ?? "";
    final vehicleName = widget.vehicleName?.toString().toLowerCase() ?? "";
    final fallbackAsset = _vehicleFallbackAsset(vehicleName);
    BitmapDescriptor? resolvedIcon;

    if (imageName.isNotEmpty) {
      resolvedIcon = await tryCreateCustomMarkerIcon(
        "${AppConfigProvider.imgUrl}$imageName",
        targetWidth: 120,
        targetHeight: 100,
        isCircle: false,
      );
    }

    _driverMarkerIcon = resolvedIcon ??
        await createCustomMarkerIconFromAsset(
          fallbackAsset,
          targetWidth: 120,
          targetHeight: 100,
          isCircle: false,
        );

    if (mounted) {
      setState(() {});
      if (driverLocation != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          updateMapWithSocketLocation();
        });
      }
    }
  }

  Future<void> updateMapWithSocketLocation() async {
    if (driverLocation == null) return;

    await _controller.future;

    // Clear old
    _markers.clear();
    _polyline.clear();
    _circles.clear();

    final bool isPostPickup = _isPostPickupStatus(widget.bookingStatus);
    final LatLng? activeTarget = isPostPickup
        ? (dropLocation ?? pickupLocation)
        : (pickupLocation ?? dropLocation);

    final BitmapDescriptor scooterIcon =
        _driverMarkerIcon ?? BitmapDescriptor.defaultMarker;

    _RouteResult activeLeg = const _RouteResult([]);
    List<LatLng> pickupToDropLeg = [];
    List<LatLng> pickupToDriverLeg = [];

    if (activeTarget != null) {
      currentDistance = calculateDistance(activeTarget, driverLocation!);
      activeLeg = await _getCachedRoute(
        key: 'active_leg',
        start: driverLocation!,
        end: activeTarget,
        minRefreshDistanceMeters: 150,
        minRefreshSeconds: 60,
      );
      // Road-route distance (not duration) — fed into the constant-speed ETA.
      _roadDistanceMeters = activeLeg.distanceMeters;
    } else {
      currentDistance = 0;
      _roadDistanceMeters = null;
    }

    if (pickupLocation != null && dropLocation != null) {
      final r = await _getCachedRoute(
        key: 'pickup_to_drop',
        start: pickupLocation!,
        end: dropLocation!,
        minRefreshDistanceMeters: 500,
        minRefreshSeconds: 600,
      );
      pickupToDropLeg = r.points;
    }

    // Covered leg (pickup → driver) is decorative — draw a smooth curved arc
    // instead of a straight tether, no API call.
    if (isPostPickup && pickupLocation != null) {
      pickupToDriverLeg = _curve(pickupLocation!, driverLocation!, bend: 0.16);
    }

    if (!isPostPickup && pickupToDropLeg.isNotEmpty) {
      _polyline.add(
        Polyline(
          polylineId: const PolylineId('future_leg'),
          points: pickupToDropLeg,
          color: Colors.grey.shade400,
          width: 5,
          patterns: _dash,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
    }

    if (isPostPickup && pickupToDriverLeg.isNotEmpty) {
      _polyline.add(
        Polyline(
          polylineId: const PolylineId('covered_leg'),
          points: pickupToDriverLeg,
          color: AppColor.successCOlor,
          width: 5,
          patterns: _dash,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
    }

    if (activeLeg.points.isNotEmpty) {
      _polyline.add(
        Polyline(
          polylineId: const PolylineId('active_leg'),
          points: activeLeg.points,
          color: AppColor.themeColor,
          width: 6,
          patterns: _dash,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
    }

    if (pickupLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId("pickup_location"),
          position: pickupLocation!,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: "Pickup"),
        ),
      );
    }

    if (dropLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId("drop_location"),
          position: dropLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: "Drop"),
        ),
      );
    }

    final double bearing = activeTarget != null
        ? calculateBearing(driverLocation!, activeTarget)
        : 0;

    _markers.add(
      Marker(
        markerId: const MarkerId("driver_location"),
        position: driverLocation!,
        icon: scooterIcon,
        rotation: bearing,
        infoWindow: InfoWindow(
          title: "Driver",
          snippet: "${(currentDistance / 1000).toStringAsFixed(1)} km away",
        ),
      ),
    );

    setState(() {});

    _updateDeliveryStatus(currentDistance, isPostPickup: isPostPickup);
    _fitMapToAvailableLocations(throttled: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bannerTimer?.cancel();
    _bannerPage.dispose();
    _pulseCtrl.dispose();
    // Stop Pusher tracking when screen closes - use try/catch since context may be invalid
    try {
      final socketProvider = context.read<SocketProvider>();
      socketProvider.stopTrackingDriver();
    } catch (_) {}
    super.dispose();
  }

  // ── Camera helpers ───────────────────────────────────────────────────────
  void _animateCamera(CameraUpdate update) {
    _programmaticMove = true;
    mapController?.animateCamera(update);
    Future.delayed(const Duration(milliseconds: 550), () {
      _programmaticMove = false;
    });
  }

  void _onCameraMoveStarted() {
    // A gesture (not one of our animateCamera calls) — stop auto-following.
    if (_programmaticMove || _isSearching) return;
    if (!_userMovedMap) setState(() => _userMovedMap = true);
  }

  void _recenter() {
    setState(() => _userMovedMap = false);
    _fitMapToAvailableLocations(throttled: false);
  }

  @override
  Widget build(BuildContext context) {
    final socketProvider = context.watch<SocketProvider>();
    final liveLoc = socketProvider.lastDriverLocation;
    // Driver live location comes from Pusher. If Pusher is delayed, this screen
    // continues to use the latest booking/driver coordinates already passed in.
    if (liveLoc != null) {
      final latestDriverLocation = LatLng(liveLoc['lat']!, liveLoc['lng']!);
      if (_hasDriverMovedSignificantly(latestDriverLocation)) {
        driverLocation = latestDriverLocation;
        _lastProcessedDriverLocation = latestDriverLocation;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          updateMapWithSocketLocation();
        });
      }
    }
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: AppColor.transparentColor,
        statusBarIconBrightness: Brightness.dark));

    if (widget.isEmbed) {
      return _buildEmbed(context);
    }

    final bool isPostPickup = _isPostPickupStatus(widget.bookingStatus);
    final int etaMin = _etaMinutes;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────────────
          Positioned.fill(
            child: mapshow
                ? GoogleMap(
                    myLocationButtonEnabled: false,
                    myLocationEnabled: false,
                    mapType: MapType.normal,
                    compassEnabled: false,
                    zoomControlsEnabled: false,
                    scrollGesturesEnabled: !_isSearching,
                    zoomGesturesEnabled: !_isSearching,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 70,
                      bottom: _isSearching ? 220 : 260,
                    ),
                    initialCameraPosition: CameraPosition(
                      target: _isSearching && pickupLocation != null
                          ? pickupLocation!
                          : initialPosition,
                      zoom: _isSearching ? 16.0 : 15.0,
                    ),
                    polylines: _polyline,
                    markers: _markers,
                    circles: _circles,
                    onCameraMoveStarted: _onCameraMoveStarted,
                    onMapCreated: (GoogleMapController controller) {
                      mapController = controller;
                      controller.setMapStyle(kPorterMapStyle);
                      if (!_controller.isCompleted) {
                        _controller.complete(controller);
                      }
                      if (!_isSearching) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _fitMapToAvailableLocations(throttled: false);
                        });
                      }
                    },
                  )
                : const Center(
                    child: CircularProgressIndicator(color: AppColor.themeColor),
                  ),
          ),

          // ── Searching pulse over the pickup pin ──────────────────────────
          if (_isSearching)
            Center(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) {
                    final t = _pulseCtrl.value;
                    return Container(
                      width: 60 + 140 * t,
                      height: 60 + 140 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColor.themeColor.withOpacity(0.18 * (1 - t)),
                        border: Border.all(
                          color: AppColor.themeColor.withOpacity(0.5 * (1 - t)),
                          width: 2,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // ── Top bar: back + live pill ────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 14,
            right: 14,
            child: Row(
              children: [
                _circleBtn(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => Navigator.pop(context),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: AppColor.successCOlor,
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isSearching ? 'Finding a partner' : 'Live tracking',
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── ETA rail on the right edge ───────────────────────────────────
          if (!_isSearching && etaMin > 0)
            Positioned(
              right: 0,
              top: MediaQuery.of(context).size.height * 0.30,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 12,
                        offset: const Offset(-2, 4)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                        isPostPickup
                            ? Icons.local_shipping_rounded
                            : Icons.two_wheeler_rounded,
                        size: 16,
                        color: AppColor.themeColor),
                    const SizedBox(height: 4),
                    Text(
                      '$etaMin',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1,
                        color: AppColor.themeColor,
                      ),
                    ),
                    const Text('min',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54)),
                    const SizedBox(height: 4),
                    Text(
                      isPostPickup ? 'to drop' : 'to pickup',
                      style:
                          const TextStyle(fontSize: 9.5, color: Colors.black45),
                    ),
                  ],
                ),
              ),
            ),

          // ── Recenter / refresh FABs ─────────────────────────────────────
          if (!_isSearching)
            Positioned(
              right: 16,
              bottom: _sheetHeight(context) + 14,
              child: Column(
                children: [
                  _circleBtn(
                    icon: Icons.my_location_rounded,
                    onTap: _recenter,
                  ),
                  const SizedBox(height: 10),
                  _circleBtn(
                    icon: Icons.refresh_rounded,
                    filled: true,
                    busy: _isManualRefreshing,
                    onTap: _manualRefreshTracking,
                  ),
                ],
              ),
            ),

          // ── Bottom sheet ────────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _isSearching ? _searchingSheet() : _trackingSheet(isPostPickup),
          ),
        ],
      ),
    );
  }

  double _sheetHeight(BuildContext context) {
    if (_isSearching) return 200;
    double h = 180;
    if (widget.driverName != null && widget.driverName!.trim().isNotEmpty) h += 64;
    if (_banners.isNotEmpty) h += 104;
    return h;
  }

  Widget _circleBtn({
    required IconData icon,
    required VoidCallback onTap,
    bool filled = false,
    bool busy = false,
  }) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: filled ? AppColor.themeColor : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: busy
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(icon,
                size: 20,
                color: filled ? Colors.white : AppColor.themeColor),
      ),
    );
  }

  // ── Searching sheet ──────────────────────────────────────────────────────
  Widget _searchingSheet() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 18, offset: Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _grabHandle(),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) => CircularProgressIndicator(
                    strokeWidth: 3,
                    value: null,
                    color: AppColor.themeColor
                        .withOpacity(0.5 + 0.5 * _pulseCtrl.value),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Finding you a delivery partner',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87)),
                    SizedBox(height: 3),
                    Text('Hang tight — this usually takes under a minute',
                        style:
                            TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _bannerStrip(),
        ],
      ),
    );
  }

  // ── Tracking sheet ───────────────────────────────────────────────────────
  Widget _trackingSheet(bool isPostPickup) {
    final km = currentDistance > 0
        ? '${(currentDistance / 1000).toStringAsFixed(1)} km away'
        : null;
    final hasDriver =
        widget.driverName != null && widget.driverName!.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 18, offset: Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _grabHandle(),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (isPostPickup
                          ? AppColor.successCOlor
                          : AppColor.themeColor)
                      .withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPostPickup
                      ? Icons.local_shipping_rounded
                      : Icons.two_wheeler_rounded,
                  color: isPostPickup
                      ? AppColor.successCOlor
                      : AppColor.themeColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deliveryStatus,
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87),
                    ),
                    if (km != null) ...[
                      const SizedBox(height: 2),
                      Text(km,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _stepBar(),
          if (hasDriver) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColor.themeColor.withOpacity(0.12),
                  child: Text(
                    widget.driverName!.trim().isNotEmpty
                        ? widget.driverName!.trim()[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: AppColor.themeColor,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.driverName!,
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87)),
                      Text(
                        widget.vehicleName?.toString().trim().isNotEmpty == true
                            ? widget.vehicleName!
                            : 'Your delivery partner',
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                if (widget.driverPhone != null &&
                    widget.driverPhone!.trim().isNotEmpty)
                  GestureDetector(
                    onTap: () => openDialPad(widget.driverPhone!.trim()),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: AppColor.successCOlor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.call_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
              ],
            ),
          ],
          if (_banners.isNotEmpty) ...[
            const SizedBox(height: 14),
            _bannerStrip(),
          ],
        ],
      ),
    );
  }

  Widget _grabHandle() => Container(
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(4),
        ),
      );

  // Step progress: Accepted → Arrived → Picked up → On the way → Delivered
  Widget _stepBar() {
    const steps = ['Accepted', 'Arrived', 'Picked up', 'On the way', 'Delivered'];
    final s = (widget.bookingStatus ?? '').trim().toLowerCase();
    int current = 0;
    if (s.contains('arriv')) current = 1;
    if (s.contains('pickup') || s == 'picked up' || s == 'pickedup') current = 2;
    if (s.contains('ongoing') || s.contains('on the way') || s == 'ontheway') {
      current = 3;
    }
    if (s.contains('deliver') || s.contains('complete')) current = 4;

    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final done = (i ~/ 2) < current;
          return Expanded(
            child: Container(
              height: 2,
              color: done ? AppColor.themeColor : Colors.black12,
            ),
          );
        }
        final idx = i ~/ 2;
        final done = idx <= current;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppColor.themeColor : Colors.white,
                border: Border.all(
                    color: done ? AppColor.themeColor : Colors.black26,
                    width: 2),
              ),
              child: done
                  ? const Icon(Icons.check, size: 7, color: Colors.white)
                  : null,
            ),
          ],
        );
      }),
    );
  }

  Widget _bannerStrip() {
    if (_banners.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 92,
      child: PageView.builder(
        controller: _bannerPage,
        itemCount: _banners.length,
        onPageChanged: (i) => _bannerIndex = i,
        itemBuilder: (_, i) {
          final b = _banners[i];
          return GestureDetector(
            onTap: () async {
              final actionType = (b['action_type'] ?? 'url').toString();
              final actionValue = (b['action_value'] ?? '').toString();
              if (actionType == 'url' && actionValue.isNotEmpty) {
                final uri = Uri.tryParse(actionValue);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: AppColor.themeColor.withOpacity(0.08),
              ),
              child: Image.network(
                '${AppConfigProvider.imgUrl}${b['image']}',
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Embedded (unchanged layout, benefits from the dotted polylines) ──────
  Widget _buildEmbed(BuildContext context) {
    final bool isPostPickup = _isPostPickupStatus(widget.bookingStatus);
    return Container(
      width: MediaQuery.of(context).size.width,
      color: Colors.white,
      child: Stack(
        children: [
          mapshow
              ? GoogleMap(
                  myLocationButtonEnabled: false,
                  myLocationEnabled: false,
                  mapType: MapType.normal,
                  compassEnabled: false,
                  zoomControlsEnabled: false,
                  scrollGesturesEnabled: !_isSearching,
                  zoomGesturesEnabled: !_isSearching,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  initialCameraPosition: CameraPosition(
                    target: _isSearching && pickupLocation != null
                        ? pickupLocation!
                        : initialPosition,
                    zoom: 15.0,
                  ),
                  polylines: _polyline,
                  markers: _markers,
                  circles: _circles,
                  onCameraMoveStarted: _onCameraMoveStarted,
                  onMapCreated: (GoogleMapController controller) {
                    mapController = controller;
                    controller.setMapStyle(kPorterMapStyle);
                    if (!_controller.isCompleted) {
                      _controller.complete(controller);
                    }
                  },
                )
              : const Center(
                  child: CircularProgressIndicator(color: AppColor.themeColor),
                ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.white.withOpacity(0.95),
              child: Row(
                children: [
                  Icon(
                    isPostPickup
                        ? Icons.local_shipping_rounded
                        : Icons.directions_bike_rounded,
                    color: isPostPickup
                        ? AppColor.successCOlor
                        : AppColor.themeColor,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      deliveryStatus,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87),
                    ),
                  ),
                  if (_etaMinutes > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColor.themeColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '~$_etaMinutes min',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColor.themeColor),
                      ),
                    ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _recenter,
                    child: const Icon(Icons.center_focus_strong,
                        color: AppColor.themeColor, size: 20),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _manualRefreshTracking,
                    child: _isManualRefreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColor.themeColor),
                          )
                        : const Icon(Icons.refresh,
                            color: AppColor.themeColor, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLanguage.aboutText[language])));
      setLoction();
      return false;
    }
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setLoction();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLanguage.aboutText[language])));
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      Geolocator.openLocationSettings();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLanguage.aboutText[language])));
      setLoction();
      return false;
    }
    return true;
  }

  setLoction() {
    setState(() {
      latitudex = 22.7196;
      longtitudex = 75.8577;
      lat = 22.7196;
      long = 75.8577;
      initialPosition = const LatLng(22.7196, 75.8577);
      isApiCalling = false;
      mapshow = true;
    });
  }

  // Calculate bearing for scooter rotation
  double calculateBearing(LatLng from, LatLng to) {
    double lat1 = from.latitude * pi / 180;
    double lat2 = to.latitude * pi / 180;
    double lng1 = from.longitude * pi / 180;
    double lng2 = to.longitude * pi / 180;

    double dLon = lng2 - lng1;
    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    double bearing = atan2(y, x);
    bearing = bearing * 180 / pi;
    bearing = (bearing + 360) % 360;
    return bearing;
  }

  double calculateDistance(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }

  bool _hasDriverMovedSignificantly(LatLng latest) {
    if (_lastProcessedDriverLocation == null) return true;
    final moved = calculateDistance(_lastProcessedDriverLocation!, latest);
    return moved >= 5; // meters
  }

  // Quadratic-bezier arc between two points, sampled to a smooth dotted curve.
  List<LatLng> _curve(LatLng a, LatLng b, {double bend = 0.2}) {
    final dLat = b.latitude - a.latitude;
    final dLng = b.longitude - a.longitude;
    // control point = midpoint pushed perpendicular to the a→b vector
    final cLat = (a.latitude + b.latitude) / 2 + dLng * bend;
    final cLng = (a.longitude + b.longitude) / 2 - dLat * bend;
    const seg = 26;
    final pts = <LatLng>[];
    for (int i = 0; i <= seg; i++) {
      final t = i / seg;
      final u = 1 - t;
      pts.add(LatLng(
        u * u * a.latitude + 2 * u * t * cLat + t * t * b.latitude,
        u * u * a.longitude + 2 * u * t * cLng + t * t * b.longitude,
      ));
    }
    return pts;
  }

  bool _shouldRefreshRoute({
    required String key,
    required LatLng start,
    required LatLng end,
    required double minRefreshDistanceMeters,
    required int minRefreshSeconds,
  }) {
    if (!_routeCache.containsKey(key) || _routeCache[key]!.isEmpty) return true;
    final prevStart = _routeStartCache[key];
    final prevEnd = _routeEndCache[key];
    final prevTime = _routeFetchedAt[key];
    if (prevStart == null || prevEnd == null || prevTime == null) return true;

    final movedStart = calculateDistance(prevStart, start);
    final movedEnd = calculateDistance(prevEnd, end);
    final elapsed = DateTime.now().difference(prevTime).inSeconds;

    return movedStart >= minRefreshDistanceMeters ||
        movedEnd >= minRefreshDistanceMeters ||
        elapsed >= minRefreshSeconds;
  }

  Future<_RouteResult> _getCachedRoute({
    required String key,
    required LatLng start,
    required LatLng end,
    required double minRefreshDistanceMeters,
    required int minRefreshSeconds,
  }) async {
    final shouldRefresh = _shouldRefreshRoute(
      key: key,
      start: start,
      end: end,
      minRefreshDistanceMeters: minRefreshDistanceMeters,
      minRefreshSeconds: minRefreshSeconds,
    );

    if (!shouldRefresh && _routeMetaCache[key] != null) {
      return _routeMetaCache[key]!;
    }
    if (_routeFetching[key] == true) {
      return _routeMetaCache[key] ??
          _RouteResult(_routeCache[key] ?? [start, end]);
    }

    _routeFetching[key] = true;
    try {
      final result = await getRouteCoordinates(start, end);
      _routeCache[key] = result.points;
      _routeMetaCache[key] = result;
      _routeStartCache[key] = start;
      _routeEndCache[key] = end;
      _routeFetchedAt[key] = DateTime.now();
      return result;
    } catch (_) {
      return _routeMetaCache[key] ??
          _RouteResult(_routeCache[key] ?? _curve(start, end));
    } finally {
      _routeFetching[key] = false;
    }
  }

  void _invalidateDynamicRouteCache() {
    const keys = ['active_leg', 'pickup_to_driver'];
    for (final key in keys) {
      _routeCache.remove(key);
      _routeMetaCache.remove(key);
      _routeStartCache.remove(key);
      _routeEndCache.remove(key);
      _routeFetchedAt.remove(key);
      _routeFetching.remove(key);
    }
  }

  Future<void> _manualRefreshTracking() async {
    if (_isManualRefreshing) return;
    setState(() => _isManualRefreshing = true);

    try {
      await _emitDriverLocationRequest();
      _invalidateDynamicRouteCache();
      await Future.delayed(const Duration(milliseconds: 800));

      if (driverLocation != null) {
        await updateMapWithSocketLocation();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tracking refreshed'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isManualRefreshing = false);
      }
    }
  }

  bool _isPostPickupStatus(String? status) {
    final normalized = (status ?? "").trim().toLowerCase();
    return normalized == "pickedup" ||
        normalized == "picked up" ||
        normalized == "pickup" ||
        normalized == "ontheway" ||
        normalized == "on the way" ||
        normalized == "ongoing" ||
        normalized == "delivered" ||
        normalized == "completed";
  }

  void _updateDeliveryStatus(double distanceMeters,
      {required bool isPostPickup}) {
    // ETA = distance ÷ a fixed assumed speed (never live traffic time).
    // Prefer the road-route distance; fall back to straight-line.
    final double etaDistanceM =
        (_roadDistanceMeters != null && _roadDistanceMeters! > 0)
            ? _roadDistanceMeters!
            : distanceMeters;
    final double metresPerMin = _avgSpeedKmph * 1000 / 60; // e.g. 22 km/h → ~366.7
    _etaMinutes = etaDistanceM > 0
        ? (etaDistanceM / metresPerMin).ceil().clamp(1, 999)
        : 0;

    if (distanceMeters <= 0) {
      deliveryStatus = isPostPickup
          ? "Heading to drop location"
          : "Heading to pickup location";
      return;
    }

    if (distanceMeters < 200) {
      deliveryStatus =
          isPostPickup ? "Near drop location" : "Near pickup location";
    } else if (distanceMeters < 1000) {
      deliveryStatus =
          isPostPickup ? "Going to drop location" : "Going to pickup location";
    } else {
      deliveryStatus = isPostPickup
          ? "Driver is on the way to drop"
          : "Driver is on the way to pickup";
    }
  }

  void _fitMapToAvailableLocations({required bool throttled}) {
    if (_isSearching) return;
    if (throttled && _userMovedMap) return;
    if (throttled && _lastCameraFitAt != null) {
      final elapsed = DateTime.now().difference(_lastCameraFitAt!);
      if (elapsed.inSeconds < 4) return;
    }

    final List<LatLng> points = [];
    if (driverLocation != null) points.add(driverLocation!);
    if (pickupLocation != null) points.add(pickupLocation!);
    if (dropLocation != null) points.add(dropLocation!);

    if (points.isEmpty) return;
    if (points.length == 1) {
      _animateCamera(CameraUpdate.newLatLngZoom(points.first, 16));
      _lastCameraFitAt = DateTime.now();
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points.skip(1)) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLng = min(minLng, p.longitude);
      maxLng = max(maxLng, p.longitude);
    }

    const double pad = 0.005;
    final LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(minLat - pad, minLng - pad),
      northeast: LatLng(maxLat + pad, maxLng + pad),
    );
    _animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    _lastCameraFitAt = DateTime.now();
  }

  // Enhanced route function — also pulls road duration/distance from the
  // Directions response so the ETA on screen reflects the actual road network.
  Future<_RouteResult> getRouteCoordinates(LatLng start, LatLng end) async {
    String url = "https://maps.googleapis.com/maps/api/directions/json?"
        "origin=${start.latitude},${start.longitude}&"
        "destination=${end.latitude},${end.longitude}&"
        "mode=driving&"
        "alternatives=false&"
        "avoid=tolls&"
        "key=$googleApiKey";

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        Map<String, dynamic> data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final route = data['routes'][0];
          final String encodedPolyline = route['overview_polyline']['points'];
          int? durSec;
          double? distM;
          final legs = route['legs'];
          if (legs is List && legs.isNotEmpty) {
            durSec = 0;
            distM = 0;
            for (final leg in legs) {
              durSec = durSec! + ((leg['duration']?['value'] as num?)?.round() ?? 0);
              distM = distM! + ((leg['distance']?['value'] as num?)?.toDouble() ?? 0);
            }
          }
          return _RouteResult(
            _decodePolyline(encodedPolyline),
            durationSec: durSec,
            distanceMeters: distM,
          );
        }
      }
    } catch (e) {
      print("Error getting route: $e");
    }

    // Smooth dotted arc if the route lookup fails — never a hard straight line.
    return _RouteResult(_curve(start, end));
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> polyline = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      polyline.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return polyline;
  }

  Future<BitmapDescriptor> createCustomMarkerIcon(
    String imageUrl, {
    int targetWidth = 80,
    int targetHeight = 80,
    bool isCircle = false,
  }) async {
    try {
      final http.Response response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        print("Failed to load image from $imageUrl");
        return BitmapDescriptor.defaultMarker;
      }

      final Uint8List bytes = response.bodyBytes;

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..isAntiAlias = true;

      if (isCircle) {
        final radius = targetWidth / 2;
        final path = Path()
          ..addOval(
              Rect.fromCircle(center: Offset(radius, radius), radius: radius));
        canvas.clipPath(path);
      }

      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble()),
        paint,
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(targetWidth, targetHeight);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

      final Uint8List resizedBytes = byteData!.buffer.asUint8List();
      return BitmapDescriptor.fromBytes(resizedBytes);
    } catch (e) {
      print("Error creating custom marker: $e");
      return BitmapDescriptor.defaultMarker;
    }
  }

  Future<BitmapDescriptor?> tryCreateCustomMarkerIcon(
    String imageUrl, {
    int targetWidth = 80,
    int targetHeight = 80,
    bool isCircle = false,
  }) async {
    try {
      final http.Response response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        return null;
      }

      final Uint8List bytes = response.bodyBytes;
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..isAntiAlias = true;

      if (isCircle) {
        final radius = targetWidth / 2;
        final path = Path()
          ..addOval(
              Rect.fromCircle(center: Offset(radius, radius), radius: radius));
        canvas.clipPath(path);
      }

      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble()),
        paint,
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(targetWidth, targetHeight);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  String _vehicleFallbackAsset(String vehicleName) {
    if (vehicleName.contains("2 wheeler") ||
        vehicleName.contains("bike") ||
        vehicleName.contains("scooter")) {
      return AppImage.topViewBike;
    }
    if (vehicleName.contains("mini")) {
      return AppImage.minitruck;
    }
    return AppImage.largetruck;
  }

  Future<BitmapDescriptor> createCustomMarkerIconFromAsset(
    String assetPath, {
    int targetWidth = 80,
    int targetHeight = 80,
    bool isCircle = false,
  }) async {
    try {
      final normalizedPath =
          assetPath.startsWith('./') ? assetPath.substring(2) : assetPath;
      final ByteData byteData = await rootBundle.load(normalizedPath);
      final Uint8List bytes = byteData.buffer.asUint8List();

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..isAntiAlias = true;

      if (isCircle) {
        final radius = targetWidth / 2;
        final path = Path()
          ..addOval(
              Rect.fromCircle(center: Offset(radius, radius), radius: radius));
        canvas.clipPath(path);
      }

      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble()),
        paint,
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(targetWidth, targetHeight);
      final outByteData = await img.toByteData(format: ui.ImageByteFormat.png);

      final Uint8List resizedBytes = outByteData!.buffer.asUint8List();
      return BitmapDescriptor.fromBytes(resizedBytes);
    } catch (e) {
      print("Error creating asset marker: $e");
      return BitmapDescriptor.defaultMarker;
    }
  }

  openDialPad(String phoneNumber) async {
    final Uri url = Uri.parse('tel:+91 $phoneNumber');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      print("Can't open dial pad.");
    }
  }
}
