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
    this.isEmbed = false,
  });

  @override
  State<MapImageScreen> createState() => _MapImageState();
}

class _MapImageState extends State<MapImageScreen> {
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
  double autoZoomThreshold = 1000;
  String deliveryStatus = "Driver is on the way";
  BitmapDescriptor? _driverMarkerIcon;
  final Map<String, List<LatLng>> _routeCache = {};
  final Map<String, LatLng> _routeStartCache = {};
  final Map<String, LatLng> _routeEndCache = {};
  final Map<String, DateTime> _routeFetchedAt = {};
  final Map<String, bool> _routeFetching = {};
  DateTime? _lastCameraFitAt;
  bool _isManualRefreshing = false;
  static const Color _googleMapsBlue = Color(0xFF4285F4);

  String get _resolvedBookingId =>
      (widget.bookingId?.toString().trim().isNotEmpty == true
          ? widget.bookingId.toString()
          : widget.driverId.toString());

  @override
  void initState() {
    super.initState();

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

    if (widget.targetLat != null && widget.targetLng != null) {
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

    List<LatLng> activeLeg = [];
    List<LatLng> pickupToDropLeg = [];
    List<LatLng> pickupToDriverLeg = [];

    if (activeTarget != null) {
      currentDistance = calculateDistance(activeTarget, driverLocation!);
      // Cost optimisation: refresh route only when driver moves ≥150 m OR
      // 60 s have elapsed — down from 35 m / 8 s. The polyline doesn't
      // change meaningfully in 8 seconds; this alone cuts active_leg
      // Directions API calls by ~87%.
      activeLeg = await _getCachedRoute(
        key: 'active_leg',
        start: driverLocation!,
        end: activeTarget,
        minRefreshDistanceMeters: 150,
        minRefreshSeconds: 60,
      );
    } else {
      currentDistance = 0;
    }

    if (pickupLocation != null && dropLocation != null) {
      // pickup→drop is a static route; fetch once and hold for 10 minutes.
      pickupToDropLeg = await _getCachedRoute(
        key: 'pickup_to_drop',
        start: pickupLocation!,
        end: dropLocation!,
        minRefreshDistanceMeters: 500,
        minRefreshSeconds: 600,
      );
    }

    // Cost optimisation: replace the "traveled path" Directions API call with
    // a simple straight-line polyline. The green covered-leg is decorative —
    // a road route isn't necessary and was generating ~90 API calls per delivery.
    if (isPostPickup && pickupLocation != null) {
      pickupToDriverLeg = [pickupLocation!, driverLocation!];
    }

    if (!isPostPickup && pickupToDropLeg.isNotEmpty) {
      _polyline.add(
        Polyline(
          polylineId: const PolylineId('future_leg'),
          points: pickupToDropLeg,
          color: Colors.grey.shade500,
          width: 5,
          geodesic: true,
        ),
      );
    }

    if (isPostPickup && pickupToDriverLeg.isNotEmpty) {
      _polyline.add(
        Polyline(
          polylineId: const PolylineId('covered_leg'),
          points: pickupToDriverLeg,
          color: Colors.green.shade600,
          width: 5,
          geodesic: true,
        ),
      );
    }

    if (activeLeg.isNotEmpty) {
      _polyline.add(
        Polyline(
          polylineId: const PolylineId('active_leg'),
          points: activeLeg,
          color: _googleMapsBlue,
          width: 7,
          geodesic: true,
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
    // Stop Pusher tracking when screen closes - use try/catch since context may be invalid
    try {
      final socketProvider = context.read<SocketProvider>();
      socketProvider.stopTrackingDriver();
    } catch (_) {}
    super.dispose();
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
                    initialCameraPosition: CameraPosition(
                      target: initialPosition,
                      zoom: 15.0,
                    ),
                    polylines: _polyline,
                    markers: _markers,
                    circles: _circles,
                    onMapCreated: (GoogleMapController controller) {
                      mapController = controller;
                      controller.setMapStyle('''
                        [
                          {
                            "featureType": "poi",
                            "elementType": "all",
                            "stylers": [
                              { "visibility": "off" }
                            ]
                          },
                          {
                            "featureType": "transit",
                            "elementType": "all",
                            "stylers": [
                              { "visibility": "off" }
                            ]
                          }
                        ]
                      ''');
                      if (!_controller.isCompleted) {
                        _controller.complete(controller);
                      }
                    },
                  )
                : const Center(
                    child: CircularProgressIndicator(color: AppColor.themeColor),
                  ),

            // ── ETA strip at the bottom of the embedded map ──────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 6,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      isPostPickup
                          ? Icons.local_shipping_rounded
                          : Icons.directions_bike_rounded,
                      color: isPostPickup
                          ? Colors.green.shade600
                          : AppColor.themeColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            deliveryStatus,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          if (currentDistance > 0)
                            Text(
                              '${(currentDistance / 1000).toStringAsFixed(1)} km away',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500]),
                            ),
                        ],
                      ),
                    ),
                    if (_etaMinutes > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isPostPickup
                              ? Colors.green.shade50
                              : AppColor.themeColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isPostPickup
                                ? Colors.green.shade300
                                : AppColor.themeColor.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 12,
                              color: isPostPickup
                                  ? Colors.green.shade700
                                  : AppColor.themeColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _etaLabel(isPostPickup),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isPostPickup
                                    ? Colors.green.shade700
                                    : AppColor.themeColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(width: 8),
                    // Control buttons
                    GestureDetector(
                      onTap: () =>
                          _fitMapToAvailableLocations(throttled: false),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.center_focus_strong,
                            color: AppColor.themeColor, size: 18),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _manualRefreshTracking,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColor.themeColor,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: _isManualRefreshing
                            ? const Padding(
                                padding: EdgeInsets.all(9),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.refresh,
                                color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Container(
          alignment: Alignment.center,
          color: Colors.white,
          child: Container(
            width: MediaQuery.of(context).size.width * 100 / 100,
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Container(
                    width: MediaQuery.of(context).size.width,
                    child: Stack(
                      children: [
                        Container(
                          width: MediaQuery.of(context).size.width,
                          child: mapshow == true
                              ? GoogleMap(
                                  myLocationButtonEnabled: false,
                                  myLocationEnabled: false,
                                  mapType: MapType.normal,
                                  compassEnabled: false,
                                  initialCameraPosition: CameraPosition(
                                    target: initialPosition,
                                    zoom: 15.0,
                                  ),
                                  polylines: _polyline,
                                  markers: _markers,
                                  circles: _circles,
                                  onMapCreated: (GoogleMapController controller) {
                                    mapController = controller;
                                    controller.setMapStyle('''
                                      [
                                        {
                                          "featureType": "poi",
                                          "elementType": "all",
                                          "stylers": [
                                            { "visibility": "off" }
                                          ]
                                        },
                                        {
                                          "featureType": "transit",
                                          "elementType": "all",
                                          "stylers": [
                                            { "visibility": "off" }
                                          ]
                                        }
                                      ]
                                    ''');
                                    if (!_controller.isCompleted) {
                                      _controller.complete(controller);
                                    }
                                  },
                                )
                              : const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircularProgressIndicator(color: AppColor.themeColor),
                                      SizedBox(height: 16),
                                      Text(
                                        "Loading map...",
                                        style: TextStyle(color: AppColor.themeColor, fontSize: 16),
                                      ),
                                    ],
                                  ),
                                ),
                        ),

                        // Status card at the top
                        Positioned(
                          top: 10,
                          left: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.delivery_dining,
                                    color: AppColor.themeColor,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        deliveryStatus,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      if (currentDistance > 0) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          "${(currentDistance / 1000).toStringAsFixed(1)} km away",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                      if (_etaMinutes > 0) ...[
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: _isPostPickupStatus(
                                                    widget.bookingStatus)
                                                ? Colors.green.shade50
                                                : AppColor.themeColor
                                                    .withOpacity(0.08),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                              color: _isPostPickupStatus(
                                                      widget.bookingStatus)
                                                  ? Colors.green.shade300
                                                  : AppColor.themeColor
                                                      .withOpacity(0.3),
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.schedule_rounded,
                                                size: 13,
                                                color: _isPostPickupStatus(
                                                        widget.bookingStatus)
                                                    ? Colors.green.shade700
                                                    : AppColor.themeColor,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                _etaLabel(_isPostPickupStatus(
                                                    widget.bookingStatus)),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: _isPostPickupStatus(
                                                          widget.bookingStatus)
                                                      ? Colors.green.shade700
                                                      : AppColor.themeColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pop(context);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Icon(
                                      Icons.close,
                                      color: Colors.grey[600],
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Control buttons
                        Positioned(
                          bottom: 20,
                          right: 20,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Center button
                              GestureDetector(
                                onTap: () {
                                  _fitMapToAvailableLocations(throttled: false);
                                },
                                child: Container(
                                  width: 56,
                                  height: 56,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(28),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 8,
                                        offset: const Offset(2, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.center_focus_strong,
                                    color: AppColor.themeColor,
                                    size: 24,
                                  ),
                                ),
                              ),
                              // Refresh button
                              GestureDetector(
                                onTap: () async {
                                  await _manualRefreshTracking();
                                },
                                child: Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: AppColor.themeColor,
                                    borderRadius: BorderRadius.circular(28),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(2, 2),
                                      ),
                                    ],
                                  ),
                                  child: _isManualRefreshing
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.refresh,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Future<void> _getCurrentPosition(type) async {
  //   final hasPermission = await _handleLocationPermission();
  //   if (!hasPermission) return;
  //   await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
  //       .then((Position position) {
  //     setState(() => _currentPosition = position);
  //     _getAddressFromLatLng(_currentPosition!, type);
  //   }).catchError((e) {
  //     print("Error getting location: $e");
  //     setLoction();
  //   });
  // }

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

  // Future<void> _getAddressFromLatLng(Position position, type) async {
  //   await placemarkFromCoordinates(
  //           _currentPosition!.latitude, _currentPosition!.longitude)
  //       .then((List<Placemark> placemarks) {
  //     Placemark place = placemarks[0];
  //     print(
  //         "Current position - Lat: ${_currentPosition!.latitude}, Long: ${_currentPosition!.longitude}");
  //     setState(() {
  //       long = _currentPosition!.longitude;
  //       lat = _currentPosition!.latitude;
  //       initialPosition =
  //           LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
  //       latitudex = _currentPosition!.latitude;
  //       longtitudex = _currentPosition!.longitude;
  //       mapshow = true;
  //       controller.text =
  //           '${place.street}, ${place.subLocality}, ${place.subAdministrativeArea}, ${place.postalCode}';
  //       isApiCalling = false;
  //     });
  //     // Call API after map is ready
  //     getMakeApiCall(_currentPosition!.latitude, _currentPosition!.longitude);
  //   }).catchError((e) {
  //     print("Error getting address: $e");
  //     setLoction();
  //   });
  // }

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
    // getMakeApiCall(22.7196, 75.8577);
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
    bearing = bearing * 180 / pi; // Convert to degrees
    bearing = (bearing + 360) % 360;
    return bearing;
  }

  // Enhanced function to calculate distance between two points
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

  Future<List<LatLng>> _getCachedRoute({
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

    if (!shouldRefresh) return _routeCache[key]!;
    if (_routeFetching[key] == true) {
      return _routeCache[key] ?? [start, end];
    }

    _routeFetching[key] = true;
    try {
      final route = await getRouteCoordinates(start, end);
      _routeCache[key] = route;
      _routeStartCache[key] = start;
      _routeEndCache[key] = end;
      _routeFetchedAt[key] = DateTime.now();
      return route;
    } catch (_) {
      return _routeCache[key] ?? [start, end];
    } finally {
      _routeFetching[key] = false;
    }
  }

  void _invalidateDynamicRouteCache() {
    const keys = ['active_leg', 'pickup_to_driver'];
    for (final key in keys) {
      _routeCache.remove(key);
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
        normalized == "ontheway" ||
        normalized == "on the way" ||
        normalized == "delivered" ||
        normalized == "completed";
  }

  void _updateDeliveryStatus(double distanceMeters,
      {required bool isPostPickup}) {
    // ETA: city average 25 km/h = 416.7 m/min
    _etaMinutes = distanceMeters > 0
        ? (distanceMeters / 416.7).ceil().clamp(1, 999)
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

  String _etaLabel(bool isPostPickup) {
    if (_etaMinutes <= 0) return '';
    final arrival = DateTime.now().add(Duration(minutes: _etaMinutes));
    final h = arrival.hour.toString().padLeft(2, '0');
    final m = arrival.minute.toString().padLeft(2, '0');
    final phase = isPostPickup ? 'Delivery by' : 'Arrives by';
    return '$phase $h:$m  (~$_etaMinutes min)';
  }

  void _fitMapToAvailableLocations({required bool throttled}) {
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
      mapController
          ?.animateCamera(CameraUpdate.newLatLngZoom(points.first, 16));
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
    mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    _lastCameraFitAt = DateTime.now();
  }

  // Smart zoom function based on distance
  void _smartZoom(LatLng userLocation, LatLng driverLocation) {
    double distance = calculateDistance(userLocation, driverLocation);
    double zoomLevel;

    if (distance < 200) {
      zoomLevel = 18.0;
      deliveryStatus = "Driver is arriving!";
    } else if (distance < 500) {
      zoomLevel = 17.0;
      deliveryStatus = "Driver is nearby";
    } else if (distance < 1000) {
      zoomLevel = 16.0;
      deliveryStatus = "Driver is approaching";
    } else if (distance < 3000) {
      zoomLevel = 15.0;
      deliveryStatus = "Driver is on the way";
    } else {
      zoomLevel = 14.0;
      deliveryStatus = "Driver is on the way";
    }

    // Calculate bounds to show both locations
    double minLat = min(userLocation.latitude, driverLocation.latitude);
    double maxLat = max(userLocation.latitude, driverLocation.latitude);
    double minLng = min(userLocation.longitude, driverLocation.longitude);
    double maxLng = max(userLocation.longitude, driverLocation.longitude);

    // Add padding
    double padding = 0.005;
    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(minLat - padding, minLng - padding),
      northeast: LatLng(maxLat + padding, maxLng + padding),
    );

    // Animate to show both locations
    mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 100.0),
    );
  }

  // Center function for manual centering
  void _centerMapOnBothLocations() {
    _fitMapToAvailableLocations(throttled: false);
  }

  // Enhanced route function with better path visualization
  Future<List<LatLng>> getRouteCoordinates(LatLng start, LatLng end) async {
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
          String encodedPolyline =
              data['routes'][0]['overview_polyline']['points'];
          return _decodePolyline(encodedPolyline);
        }
      }
    } catch (e) {
      print("Error getting route: $e");
    }

    // Return straight line if route fetching fails
    return [start, end];
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

class MockTrackingMap extends StatelessWidget {
  final String status;
  final String vehicleName;
  const MockTrackingMap({
    super.key,
    required this.status,
    required this.vehicleName,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Container(
      color: const Color(0xFFF1F5F9), // modern slate-100 background
      child: Stack(
        children: [
          // Stylized roads
          Positioned.fill(
            child: CustomPaint(
              painter: _RoadsPainter(),
            ),
          ),
          
          // Live Pulse overlay
          Positioned(
            top: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 6),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    "Live GPS Tracking Active",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Pickup Marker
          Positioned(
            left: size.width * 0.15,
            top: size.height * 0.10,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text("Pickup", style: TextStyle(color: Colors.white, fontSize: 8, fontFamily: 'Poppins')),
                ),
                const Icon(Icons.location_on, color: Colors.green, size: 28),
              ],
            ),
          ),

          // Drop Marker
          Positioned(
            left: size.width * 0.70,
            top: size.height * 0.32,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text("Dropoff", style: TextStyle(color: Colors.white, fontSize: 8, fontFamily: 'Poppins')),
                ),
                const Icon(Icons.location_on, color: Colors.red, size: 28),
              ],
            ),
          ),

          // Driver Marker
          Positioned(
            left: size.width * 0.40,
            top: size.height * 0.18,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
                  ),
                  child: Text(
                    "Driver ($status)",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ),
                const Icon(Icons.local_shipping, color: Colors.blue, size: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoadsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Curved road path connecting the points
    final path = Path()
      ..moveTo(size.width * 0.20, size.height * 0.15)
      ..cubicTo(
        size.width * 0.45,
        size.height * 0.10,
        size.width * 0.35,
        size.height * 0.30,
        size.width * 0.75,
        size.height * 0.36,
      );

    canvas.drawPath(path, borderPaint);
    canvas.drawPath(path, paint);

    // Dotted route line overlay
    final dashPaint = Paint()
      ..color = const Color(0xFF3B82F6)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, dashPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
