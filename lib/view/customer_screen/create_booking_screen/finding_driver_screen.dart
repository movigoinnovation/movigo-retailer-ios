import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/get_navigation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:movigo/Controller/check_booking_status_controller.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/socket_connection/socket_provider.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_image.dart';
import 'booking_detail_screen.dart';
import 'package:movigo/view/retailer_screen/retailer_booking_screen/accept_booking_detail_screen.dart';

class FindingDriverScreen extends StatefulWidget {
  final String bookingId;
  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;
  final String dropAddress;
  final int wheelCount;
  final bool isReassigning;

  const FindingDriverScreen({
    super.key, 
    this.bookingId = '',
    this.pickupLat = 22.7196,
    this.pickupLng = 75.8577,
    this.pickupAddress = 'Fetching current address...',
    this.dropAddress = 'Fetching destination address...',
    this.wheelCount = 2,
    this.isReassigning = false,
  });

  @override
  State<FindingDriverScreen> createState() => _FindingDriverScreenState();
}

class _FindingDriverScreenState extends State<FindingDriverScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _dialogShown = false;
  Timer? _pollTimer;
  final CheckBookingStatusController _statusController = CheckBookingStatusController();

  // Map & Animation
  GoogleMapController? _mapController;
  late LatLng _pickupLocation;
  late AnimationController _radarController;
  late AnimationController _progressController;
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  Timer? _markerMovementTimer;
  List<LatLng> _dummyDriverLocations = [];

  // Zomato style text
  final List<String> _dynamicTexts = [
    "Looking for the 'One'... (driver, not soulmate) 🫣",
    "Matchmaking you with the perfect captain...",
    "Bribing the traffic lights for a green route 🚦",
    "Waking up nearby captains (we gave them coffee) ☕",
    "Looking for a captain who treats your goods like royalty 👑",
    "Sending a bat-signal to our best drivers 🦇",
    "Manifesting a ride for you right now ✨"
  ];
  int _currentTextIndex = 0;
  Timer? _textTimer;

  BitmapDescriptor? _driverMarkerIcon;

  Future<void> _loadCustomMarkerIcon() async {
    try {
      String assetPath = AppImage.twowheel;
      if (widget.wheelCount == 3) {
        assetPath = AppImage.eloader;
      } else if (widget.wheelCount == 4) {
        assetPath = AppImage.minitruck;
      }
      
      final normalizedPath = assetPath.startsWith('./') ? assetPath.substring(2) : assetPath;
      final ByteData byteData = await rootBundle.load(normalizedPath);
      final Uint8List bytes = byteData.buffer.asUint8List();

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 80,
        targetHeight: 80,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..isAntiAlias = true;

      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        const Rect.fromLTWH(0, 0, 80, 80),
        paint,
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(80, 80);
      final outByteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List resizedBytes = outByteData!.buffer.asUint8List();

      if (mounted) {
        setState(() {
          _driverMarkerIcon = BitmapDescriptor.fromBytes(resizedBytes);
          _updateMarkers();
        });
      }
    } catch (e) {
      debugPrint("Error loading custom marker: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // On resume (e.g. after a phone call), immediately re-check booking status
    // so a driver acceptance that happened during the background period is caught.
    if (state == AppLifecycleState.resumed) _checkBookingStatusNow();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pickupLocation = LatLng(widget.pickupLat, widget.pickupLng);
    _loadCustomMarkerIcon();

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 600),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _onTimerExpired();
      })
      ..forward();

    _dynamicTexts.shuffle();
    _startDynamicTextAndProgress();

    _initDummyDrivers();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final socketProvider = Provider.of<SocketProvider>(context, listen: false);
      // Reset any stale accepted state from a previous booking
      socketProvider.setDriverAccepted(false);
      socketProvider.addListener(_onSocketUpdate);

      // Subscribe to customer Pusher channel so booking-status events are received
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('user_details') ?? '';
        if (raw.isNotEmpty) {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          final uid = (data['_id'] ?? data['user_id'] ?? '').toString();
          if (uid.isNotEmpty) {
            debugPrint('[FindingDriverScreen] Subscribing to customer channel for userId=$uid');
            await socketProvider.subscribeRetailerChannel(uid);
          }
        }
      } catch (e) {
        debugPrint('[FindingDriverScreen] Failed to subscribe booking-status channel: $e');
      }
      // Immediate REST check after channel subscribe, then poll every 4 s
      _checkBookingStatusNow();
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _checkBookingStatusNow());
    });
  }

  void _initDummyDrivers() {
    final random = Random();
    for (int i = 0; i < 5; i++) {
      // 3 km radius is approx 0.027 degrees offset, so we spread them within 3 km
      double latOffset = (random.nextDouble() - 0.5) * 0.035;
      double lngOffset = (random.nextDouble() - 0.5) * 0.035;
      _dummyDriverLocations.add(LatLng(_pickupLocation.latitude + latOffset, _pickupLocation.longitude + lngOffset));
    }
    _updateMarkers();

    _markerMovementTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) return;
      for (int i = 0; i < _dummyDriverLocations.length; i++) {
        double latOffset = (random.nextDouble() - 0.5) * 0.003;
        double lngOffset = (random.nextDouble() - 0.5) * 0.003;
        _dummyDriverLocations[i] = LatLng(
          _dummyDriverLocations[i].latitude + latOffset,
          _dummyDriverLocations[i].longitude + lngOffset,
        );
      }
      _updateMarkers();
    });
  }

  void _updateMarkers() async {
    final Map<MarkerId, Marker> newMarkers = {};
    
    // Add pickup marker
    newMarkers[const MarkerId('pickup')] = Marker(
      markerId: const MarkerId('pickup'),
      position: _pickupLocation,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    );

    // Add dummy drivers
    for (int i = 0; i < _dummyDriverLocations.length; i++) {
      newMarkers[MarkerId('driver_$i')] = Marker(
        markerId: MarkerId('driver_$i'),
        position: _dummyDriverLocations[i],
        icon: _driverMarkerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        rotation: Random().nextDouble() * 360,
      );
    }

    if (mounted) {
      setState(() {
        _markers = newMarkers.values.toSet();
      });
    }
  }

  void _startDynamicTextAndProgress() {
    _textTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) return;
      setState(() {
        _currentTextIndex = (_currentTextIndex + 1) % _dynamicTexts.length;
      });
    });
  }

  Future<void> _checkBookingStatusNow() async {
    if (_dialogShown || !mounted || widget.bookingId.isEmpty) return;
    try {
      await _statusController.checkBookingStatus(context, bookingId: widget.bookingId);
    } catch (e) {
      debugPrint('[FindingDriverScreen] _checkBookingStatusNow error: $e');
      return;
    }
    if (!mounted || _dialogShown) return;
    final status = (_statusController.bookingStatus ?? '').trim();
    final accepted = _statusController.isDriverAccepted == true ||
        ['Accepted', 'Arrived', 'ArrivedAtPickup', 'Pickup', 'PickedUp', 'Ongoing', 'OnTheWay']
            .contains(status);
    if (accepted) {
      _pollTimer?.cancel();
      _progressController.stop();
      _dialogShown = true;
      debugPrint('[FindingDriverScreen] Poll detected accepted status=$status — navigating');
      WidgetsBinding.instance.addPostFrameCallback((_) => _showDriverConfirmedDialog());
      return;
    }
    if (_statusController.isTerminalStatus) {
      _pollTimer?.cancel();
      _progressController.stop();
      _dialogShown = true;
      debugPrint('[FindingDriverScreen] Poll detected terminal status=$status — showing dialog');
      WidgetsBinding.instance.addPostFrameCallback((_) => _showNoDriverDialog());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _markerMovementTimer?.cancel();
    _textTimer?.cancel();
    _radarController.dispose();
    _progressController.dispose();
    try {
      Provider.of<SocketProvider>(context, listen: false).removeListener(_onSocketUpdate);
    } catch (_) {}
    super.dispose();
  }

  void _onSocketUpdate() {
    final socket = Provider.of<SocketProvider>(context, listen: false);
    if (socket.isDriverAccepted == true && !_dialogShown) {
      _pollTimer?.cancel();
      _progressController.stop();
      _dialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showDriverConfirmedDialog();
      });
    }
  }

  Future<void> _onTimerExpired() async {
    if (_dialogShown) return;
    if (widget.bookingId.isNotEmpty) {
      final postApi = Provider.of<PostApiProvider>(context, listen: false);
      await postApi.cancelBookingApi(
        context,
        bookingId: widget.bookingId,
        cancellationReason: "Auto Cancelled",
        cancelledBy: "System",
      );
    }
    if (!mounted) return;
    _showNoDriverDialog();
  }

  void _showCancelDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final reasons = [
          "Driver is taking too long",
          "Changed my mind",
          "Wrong pickup address",
          "Expected a different vehicle",
          "Other"
        ];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Cancel Ride?",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColor.primaryColor,
                  fontFamily: AppFont.fontFamily,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Please let us know why you are cancelling this booking.",
                style: TextStyle(fontSize: 14, color: Colors.grey, fontFamily: AppFont.fontFamily),
              ),
              const SizedBox(height: 16),
              ...reasons.map((reason) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(reason, style: const TextStyle(fontFamily: AppFont.fontFamily)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (widget.bookingId.isNotEmpty) {
                        final postApi = Provider.of<PostApiProvider>(context, listen: false);
                        await postApi.cancelBookingApi(
                          context,
                          bookingId: widget.bookingId,
                          cancellationReason: reason,
                          cancelledBy: "Customer",
                        );
                      }
                      Get.offAll(() => const CustomBottomNav(userType: UserType.retailer, initialIndex: 0));
                    },
                  )),
            ],
          ),
        );
      },
    );
  }

  void _showNoDriverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: AppColor.primaryColor.withOpacity(0.8),
      builder: (dialogContext) {
        return WillPopScope(
          onWillPop: () async {
            _navigateHome(dialogContext);
            return false;
          },
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sentiment_dissatisfied, size: 64, color: AppColor.primaryColor),
                  const SizedBox(height: 16),
                  const Text(
                    "No Captains Nearby",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColor.primaryColor),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "All our captains are currently busy. Please try again after some time.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColor.primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: () => _navigateHome(dialogContext),
                    child: const Text("Go Back Home", style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDriverConfirmedDialog() {
    // Navigate immediately to the retailer live tracking screen — no dialog tap required
    debugPrint('[FindingDriverScreen] Driver accepted — navigating to RAcceptBookingDetailScreen');
    if (!mounted) return;
    // Booking is now active with a driver — clear the "finding" restore point;
    // the detail screen manages its own state from here.
    SharedPreferences.getInstance().then((p) => p.remove('retailer_active_booking_id'));
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => BookingDetailScreen(
          bookingId: widget.bookingId,
        ),
      ),
    );
  }

  void _navigateHome(BuildContext dialogContext) {
    SharedPreferences.getInstance().then((p) => p.remove('retailer_active_booking_id'));
    Navigator.pop(dialogContext);
    Get.offAll(() => const CustomBottomNav(userType: UserType.retailer, initialIndex: 1));
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark));

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background Google Map
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _pickupLocation, zoom: 14.5),
            myLocationEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            markers: _markers,
            onMapCreated: (controller) => _mapController = controller,
          ),

          // Smooth pulsing hardware-accelerated radar circles in the center of the screen
          IgnorePointer(
            child: Center(
              child: AnimatedBuilder(
                animation: _radarController,
                builder: (context, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Inner pulse
                      Opacity(
                        opacity: (1 - _radarController.value).clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: _radarController.value * 2.5,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: AppColor.primaryColor.withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColor.primaryColor.withOpacity(0.4), width: 1.5),
                            ),
                          ),
                        ),
                      ),
                      // Outer pulse
                      Opacity(
                        opacity: (1 - _radarController.value).clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: _radarController.value * 4.5,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: AppColor.primaryColor.withOpacity(0.08),
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColor.primaryColor.withOpacity(0.2), width: 1.0),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // Top Header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: () => Get.back(),
                    child: const CircleAvatar(
                      backgroundColor: Colors.white,
                      child: Icon(Icons.arrow_back, color: AppColor.primaryColor),
                    ),
                  ),
                  const Text(
                    "Searching...",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColor.primaryColor),
                  ),
                  widget.isReassigning
                      ? const SizedBox(width: 40)
                      : InkWell(
                          onTap: _showCancelDialog,
                          child: const CircleAvatar(
                            backgroundColor: Colors.white,
                            child: Icon(Icons.more_vert, color: AppColor.primaryColor),
                          ),
                        ),
                ],
              ),
            ),
          ),

          if (widget.isReassigning)
            Positioned(
              top: MediaQuery.of(context).padding.top + 64, // Just below top header
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7), // Amber 100
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A), width: 1), // Amber 200
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFFD97706)), // Amber 600
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            "Reassigning Booking",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF92400E), // Amber 800
                              fontFamily: AppFont.fontFamily,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            "We are finding a new driver for you. Please wait.",
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFB45309), // Amber 700
                              fontFamily: AppFont.fontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Floating Bottom Card
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.only(left: 16, right: 16, bottom: 32),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, 10))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Finding Your Captain",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColor.primaryColor),
                  ),
                  const SizedBox(height: 8),
                  
                  // Dynamic Zomato text
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: Text(
                      _dynamicTexts[_currentTextIndex],
                      key: ValueKey<int>(_currentTextIndex),
                      style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Rapido Style Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 8,
                      child: AnimatedBuilder(
                        animation: _progressController,
                        builder: (_, __) => LinearProgressIndicator(
                          value: _progressController.value,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColor.primaryColor),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Location Details
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          const Icon(Icons.radio_button_checked, size: 16, color: AppColor.primaryColor),
                          Container(
                            height: 30,
                            width: 2,
                            color: Colors.grey.shade300,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                          ),
                          const Icon(Icons.location_on, size: 16, color: Colors.red),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Pickup Location", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColor.primaryColor)),
                            Text(widget.pickupAddress, style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 16),
                            const Text("Dropoff Location", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColor.primaryColor)),
                            Text(widget.dropAddress, style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  const Divider(color: Colors.black12),
                  const SizedBox(height: 8),
                  
                  // Estimated Time
                  Row(
                    children: const [
                      Icon(Icons.access_time, size: 20, color: AppColor.primaryColor),
                      SizedBox(width: 8),
                      Text("Estimated Arrival: 4-6 mins", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColor.primaryColor)),
                    ],
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
