import 'dart:ui' as ui;
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/get_navigation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:movigo/utilities/app_config_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:movigo/Controller/get_booking_details_provider.dart';
import 'package:movigo/Provider/socket_connection/socket_provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/helper/MapImage_screen.dart';
import 'package:movigo/helper/shimmer/getbookingdetails_shimmer.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'bookingHelpAndSupport.dart';
import 'cancellation_policy_screen.dart';
import 'finding_driver_screen.dart';
import 'package:movigo/view/retailer_screen/retailer_booking_screen/edit_booking_location_screen.dart';
import 'package:movigo/view/customer_screen/coins/coin_scratch_card_screen.dart';

class BookingDetailScreen extends StatefulWidget {
  final String bookingId;
  final bool showAcceptedBanner;
  const BookingDetailScreen({
    super.key,
    required this.bookingId,
    this.showAcceptedBanner = false,
  });

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  ui.Image? _scooterImage;
  ui.Image? _miniTruckImage;
  ui.Image? _largeTruckImage;
  bool _assetsLoaded = false;

  Future<void> _loadAssetImages() async {
    _scooterImage = await _loadUiImage(AppImage.topViewBike);
    _miniTruckImage = await _loadUiImage(AppImage.minitruck);
    _largeTruckImage = await _loadUiImage(AppImage.largetruck);
    if (mounted) {
      setState(() {
        _assetsLoaded = true;
      });
    }
  }

  Future<ui.Image> _loadUiImage(String assetPath) async {
    final normalizedPath = assetPath.startsWith('./') ? assetPath.substring(2) : assetPath;
    final ByteData byteData = await rootBundle.load(normalizedPath);
    final Uint8List bytes = byteData.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 120, targetHeight: 120);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<BitmapDescriptor?> _generateMarkerIcon(String etaText, ui.Image? vehicleImage) async {
    if (vehicleImage == null) return null;
    try {
      final textPainter = TextPainter(
        text: TextSpan(
          text: etaText,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: AppFont.fontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final double bubblePadding = 10.0;
      final double bubbleWidth = textPainter.width + bubblePadding * 2;
      final double bubbleHeight = textPainter.height + 6.0;

      final double canvasWidth = max(bubbleWidth, 90.0) + 20.0;
      final double canvasHeight = bubbleHeight + 10.0 + 90.0;

      // Render at the device pixel ratio and tell fromBytes the intended
      // logical size, otherwise the marker renders tiny (and near-invisible)
      // on high-DPI phones since fromBytes treats raw PNG pixels as device px.
      final double dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(dpr);

      // ── Draw ETA Bubble ──
      final double bubbleX = (canvasWidth - bubbleWidth) / 2;
      final double bubbleY = 4.0;
      final bubbleRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(bubbleX, bubbleY, bubbleWidth, bubbleHeight),
        const Radius.circular(6),
      );

      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.15)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawRRect(bubbleRect.shift(const Offset(0, 1.5)), shadowPaint);

      final bubblePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawRRect(bubbleRect, bubblePaint);

      final borderPaint = Paint()
        ..color = Colors.grey.shade300
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRRect(bubbleRect, borderPaint);

      // Paint text
      textPainter.paint(canvas, Offset(bubbleX + bubblePadding, bubbleY + (bubbleHeight - textPainter.height) / 2));

      // ── Draw pointer triangle ──
      final double pointerX = canvasWidth / 2;
      final double pointerY = bubbleY + bubbleHeight;
      final pointerPath = Path()
        ..moveTo(pointerX - 5.0, pointerY)
        ..lineTo(pointerX + 5.0, pointerY)
        ..lineTo(pointerX, pointerY + 5.0)
        ..close();
      canvas.drawPath(pointerPath, bubblePaint);
      canvas.drawPath(pointerPath, borderPaint);

      // ── Draw circular background for vehicle icon OR draw top-view bike rider directly ──
      final bool isScooter = vehicleImage == _scooterImage;

      if (isScooter) {
        // Draw the top view of the bike rider directly in its full original colors!
        // No circle wrapper, no white background, just the clean transparent bike rider icon!
        final double bikeSize = 64.0;
        final Offset bikeCenter = Offset(canvasWidth / 2, pointerY + 5.0 + bikeSize / 2);

        canvas.save();
        canvas.drawImageRect(
          vehicleImage,
          Rect.fromLTWH(0, 0, vehicleImage.width.toDouble(), vehicleImage.height.toDouble()),
          Rect.fromCenter(center: bikeCenter, width: bikeSize, height: bikeSize),
          Paint(),
        );
        canvas.restore();
      } else {
        final double vehicleY = pointerY + 5.0;
        final circleRadius = 28.0;
        final circleCenter = Offset(canvasWidth / 2, vehicleY + circleRadius);

        canvas.drawCircle(circleCenter.translate(0, 1.5), circleRadius, shadowPaint);
        canvas.drawCircle(circleCenter, circleRadius, Paint()..color = AppColor.themeColor..style = PaintingStyle.fill);
        canvas.drawCircle(circleCenter, circleRadius - 1.5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.5);

        // Draw vehicle icon inside circle
        canvas.save();
        final clipPath = Path()..addOval(Rect.fromCircle(center: circleCenter, radius: circleRadius - 3.0));
        canvas.clipPath(clipPath);

        canvas.drawImageRect(
          vehicleImage,
          Rect.fromLTWH(0, 0, vehicleImage.width.toDouble(), vehicleImage.height.toDouble()),
          Rect.fromCenter(center: circleCenter, width: 38.0, height: 38.0),
          Paint()..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        );
        canvas.restore();
      }

      final picture = recorder.endRecording();
      final img = await picture.toImage((canvasWidth * dpr).round(), (canvasHeight * dpr).round());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      return BitmapDescriptor.fromBytes(
        byteData!.buffer.asUint8List(),
        size: Size(canvasWidth, canvasHeight),
      );
    } catch (e) {
      debugPrint("Error generating marker icon: $e");
      return null;
    }
  }

  // ── Priority Pickup — booking_price is quoted inclusive of the priority
  // fee at booking time (a preview), but it's only actually paid if the
  // pickup was on time. The backend only flips priorityOutcome to
  // 'priority_charged' at the DELIVERED transition, so while the trip is
  // still in progress (which is exactly when this tracking screen is shown)
  // outcome is often still 'pending' even for a pickup that was genuinely on
  // time. So while pending, fall back to computing on-time-ness directly
  // from the same timestamps the backend uses — mirrors
  // FareDisplayHelper.isPriorityChargeCollectible in the driver app.
  bool _isPriorityChargeCollectible(Map<String, dynamic> data) {
    final String outcome = data['priorityOutcome']?.toString() ?? 'pending';
    if (outcome == 'priority_charged') return true;
    if (outcome != 'pending') return false;

    final DateTime? pickupVerifiedAt = DateTime.tryParse(data['pickupGeofenceVerifiedAt']?.toString() ?? '');
    final DateTime? acceptedAt = DateTime.tryParse((data['driverAcceptedAt'] ?? data['accepted_at'])?.toString() ?? '');
    if (pickupVerifiedAt == null || acceptedAt == null) return false;

    final int limitSeconds = int.tryParse(data['priorityArrivalTimeLimitSeconds']?.toString() ?? '') ?? 600;
    return pickupVerifiedAt.difference(acceptedAt).inSeconds <= limitSeconds;
  }

  // Same GST-waived presentation used on the delivered-trip receipt
  // (delivered_booking_detail_screen.dart) — GST is computed for display
  // then struck through and marked Free, since the retailer isn't charged it.
  Widget _buildFareCard(Map<String, dynamic> data) {
    final String rawPrice = (data['booking_price'] ?? data['price'] ?? '0').toString().replaceAll('₹', '').trim();
    final double quotedTotal = double.tryParse(rawPrice) ?? 0.0;

    final bool isPriority = data['isPriorityPickup'] == true;
    final double priorityFeeAmount = double.tryParse(data['priorityChargeAmount']?.toString() ?? '') ?? 0.0;
    final bool priorityCollected = isPriority && _isPriorityChargeCollectible(data);
    final double tripFare = isPriority ? (quotedTotal - priorityFeeAmount) : quotedTotal;
    final double amountToPay = tripFare + (priorityCollected ? priorityFeeAmount : 0);
    final double gst = double.parse((amountToPay * 0.18).toStringAsFixed(2));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEFF3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, size: 17, color: AppColor.themeColor),
              const SizedBox(width: 8),
              const Text(
                'Fare Details',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A), fontFamily: AppFont.fontFamily),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Trip Fare', style: TextStyle(fontSize: 13, color: Colors.black87, fontFamily: AppFont.fontFamily)),
              Text('₹ ${tripFare.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, color: Colors.black87, fontFamily: AppFont.fontFamily)),
            ],
          ),
          if (isPriority) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Priority Pickup Fee', style: TextStyle(fontSize: 13, color: Colors.black87, fontFamily: AppFont.fontFamily)),
                Row(
                  children: [
                    Text(
                      '₹ ${priorityFeeAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: priorityCollected ? Colors.black87 : Colors.grey.shade500,
                        decoration: priorityCollected ? null : TextDecoration.lineThrough,
                        fontFamily: AppFont.fontFamily,
                      ),
                    ),
                    if (!priorityCollected) ...[
                      const SizedBox(width: 8),
                      Text(
                        'Not Charged',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold, fontFamily: AppFont.fontFamily),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('GST Charges (18%)', style: TextStyle(fontSize: 13, color: Colors.black87, fontFamily: AppFont.fontFamily)),
              Row(
                children: [
                  Text(
                    '₹ ${gst.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                      decoration: TextDecoration.lineThrough,
                      fontFamily: AppFont.fontFamily,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Free',
                    style: TextStyle(fontSize: 13, color: Colors.green.shade600, fontWeight: FontWeight.bold, fontFamily: AppFont.fontFamily),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Amount to Pay',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A), fontFamily: AppFont.fontFamily),
              ),
              Text(
                '₹ ${amountToPay.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColor.themeColor, fontFamily: AppFont.fontFamily),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard(Map<String, dynamic> data, dynamic pickup, dynamic drop, Size size) {
    final senderName = (data['customer_name'] ?? data['sender_name'] ?? '').toString().trim();
    final senderPhone = (data['customer_phone'] ?? data['sender_phone'] ?? '').toString().trim();
    final receiverName = (data['receiver_name'] ?? '').toString().trim();
    final receiverPhone = (data['receiver_phone'] ?? '').toString().trim();
    final pickupAddress = (pickup?['address'] ?? '').toString().trim();
    final dropAddress = (drop?['address'] ?? '').toString().trim();
    final bookingId = (data['_id'] ?? '').toString();
    // Pickup can only still be moved before the driver reaches it — matches
    // the same rule/backend enforcement as the other Edit Location entry
    // points (see edit_booking_location_screen.dart doc comment).
    final normalizedStatus = (data['booking_status'] ?? '').toString().toLowerCase().replaceAll(' ', '');
    final bool canEditPickup = normalizedStatus == 'accepted';
    // extra_drops includes the final drop as its last entry — only the earlier
    // entries are intermediate stops (dropAddress above already covers the last one).
    final List<dynamic> _allExtraDrops = data['extra_drops'] is List ? data['extra_drops'] as List : [];
    final List<dynamic> intermediateStops =
        _allExtraDrops.length > 1 ? _allExtraDrops.sublist(0, _allExtraDrops.length - 1) : [];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEFF3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bookingId.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Trip Details',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    fontFamily: AppFont.fontFamily,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Get.to(() => EditBookingLocationScreen(
                          bookingId: bookingId,
                          canEditPickup: canEditPickup,
                          currentPickupAddress: canEditPickup ? pickupAddress : '',
                          currentDropAddress: dropAddress,
                          currentStops: canEditPickup
                              ? intermediateStops.whereType<Map>().map((s) => Map<String, dynamic>.from(s)).toList()
                              : const [],
                        ));
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_location_alt_outlined, size: 15, color: AppColor.themeColor),
                      const SizedBox(width: 4),
                      Text(
                        'Edit',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: AppFont.fontFamily,
                          color: AppColor.themeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Timeline vertical indicators
              Column(
                children: [
                  const SizedBox(height: 5),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColor.themeColor, width: 3),
                    ),
                  ),
                  Container(
                    width: 2,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                    ),
                  ),
                  const Icon(Icons.location_on, size: 16, color: Color(0xFFEF4444)),
                ],
              ),
              const SizedBox(width: 14),
              // Right side addresses and details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pickup Block
                    Text(
                      '${senderName.isNotEmpty ? senderName : 'Sender'} • ${senderPhone.isNotEmpty ? senderPhone : ''}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                        fontFamily: AppFont.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pickupAddress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontFamily: AppFont.fontFamily,
                      ),
                    ),
                    for (int _i = 0; _i < intermediateStops.length; _i++) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Stop ${_i + 1}: ${(intermediateStops[_i] as Map?)?['address']?.toString() ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade800,
                          fontFamily: AppFont.fontFamily,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    // Dropoff Block
                    Text(
                      '${receiverName.isNotEmpty ? receiverName : 'Receiver'} • ${receiverPhone.isNotEmpty ? receiverPhone : ''}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                        fontFamily: AppFont.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dropAddress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontFamily: AppFont.fontFamily,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? supportNumber;
  String userId = '';
  bool _allowPop = false;
  StreamSubscription? _reassigningSubscription;

  // â”€â”€â”€ Map banner state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final Completer<GoogleMapController> _mapCompleter = Completer();
  GoogleMapController? _mapController;
  Set<Marker> _bannerMarkers = {};
  Set<Polyline> _bannerPolylines = {};
  bool _mapReady = false;
  bool _hasShownRating = false; // only show rating once per delivery
  bool _hasShownScratch = false; // only show scratch card once per delivery
  Timer? _locationTimer;
  LatLng? _lastFittedDriverLocation;
  bool _hasClearedCompletedBanner = false;
  String _trackingPhaseText = 'Waiting for driver location';


  @override
  void initState() {
    super.initState();
    _loadAssetImages();

    final userController = Provider.of<UserController>(context, listen: false);
    userId = userController.getUserId;

    debugPrint("ðŸ§‘ Current Logged In UserId = $userId");

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final socketProvider = Provider.of<SocketProvider>(context, listen: false);
      
      if (userId.isNotEmpty) {
        socketProvider.subscribeRetailerChannel(userId);
      }
      
      _reassigningSubscription = socketProvider.reassigningStream.listen((data) {
        final reassignBookingId = data['booking_id']?.toString() ?? data['bookingId']?.toString();
        if (reassignBookingId == widget.bookingId) {
          debugPrint("ðŸ”„ Booking reassigned! Redirecting customer to FindingDriverScreen...");
          
          _locationTimer?.cancel();
          socketProvider.stopTrackingDriver();
          
          Get.off(() => FindingDriverScreen(
            bookingId: widget.bookingId,
            isReassigning: true,
          ));
        }
      });

      // 1ï¸âƒ£  Load booking details
      Provider.of<BookingDetailController>(
        context,
        listen: false,
      ).getBookingDetail(context, bookingId: widget.bookingId).then((_) {
        // 2ï¸âƒ£  After data is ready, start live-location emit
        _startLiveLocationEmit();
        // 3ï¸âƒ£  Subscribe to Pusher booking channel for live driver location
        if (widget.bookingId.isNotEmpty) {
          socketProvider.startTrackingDriver(bookingId: widget.bookingId);
        }
        // 4ï¸âƒ£  Show "driver accepted" banner if navigated from FindingDriverScreen
        if (widget.showAcceptedBanner && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'Driver has accepted your booking!',
                  style: TextStyle(fontFamily: AppFont.fontFamily),
                ),
              ]),
              backgroundColor: Colors.green.shade600,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      });
    });
  }

  // â”€â”€â”€ Start emitting driver live location every 30 s â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _startLiveLocationEmit() {
    final socketProvider = Provider.of<SocketProvider>(context, listen: false);

    Future<void> emitNow() async {
      if (!socketProvider.isConnected) {
        await socketProvider.initSocket(AppConstant.token);
        await Future.delayed(const Duration(milliseconds: 600));
      }
      socketProvider.emitDriverLiveLocation(
        userId: userId,
        bookingId: widget.bookingId,
      );
      // Also refresh booking data to get latest driver assignment + status
      if (mounted) {
        Provider.of<BookingDetailController>(context, listen: false)
            .getBookingDetail(context, bookingId: widget.bookingId, silent: true);
      }
    }

    emitNow();

    _locationTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted) return;
      await emitNow();
      debugPrint("[Banner] emitDriverLiveLocation called every 1 min");
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _reassigningSubscription?.cancel();
    try {
      Provider.of<SocketProvider>(context, listen: false).stopTrackingDriver();
    } catch (_) {}
    _mapReady = false;
    _mapController?.dispose();
    super.dispose();
  }

  // â”€â”€â”€ Update banner map whenever driver location changes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _updateBannerMarkers({
    required LatLng? driverLatLng,
    required LatLng? pickupLatLng,
    required LatLng? dropLatLng,
    String? bookingStatus,
  }) async {
    final Set<Marker> markers = {};
    final Set<Polyline> polylines = {};

    String vehicleName = '';
    try {
      final controller = Provider.of<BookingDetailController>(context, listen: false);
      final data = controller.bookingDetail;
      final vehicle = data?['vehicleType_id'];
      final subVehicle = data?['subVehicleType_id'];
      vehicleName = ((subVehicle is Map ? subVehicle['name'] : null) ??
                     (vehicle is Map ? vehicle['name'] : null) ??
                     data?['display_vehicle_name'] ??
                     data?['requested_vehicle_name'] ??
                     '').toString().toLowerCase();
    } catch (e) {
      debugPrint("Error parsing vehicleName: $e");
    }

    if (pickupLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId("banner_pickup"),
        position: pickupLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: "Pickup"),
      ));
    }

    if (dropLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId("banner_drop"),
        position: dropLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: "Drop"),
      ));
    }

    final String status = (bookingStatus ?? '').toLowerCase().replaceAll(' ', '');
    final bool isPostPickup = status == 'ontheway' ||
        status == 'pickedup' ||
        status == 'pickup' ||
        status == 'ongoing' ||
        status == 'started' ||
        status == 'startdelivery';
    final bool isCompleted = status == 'delivered' ||
        status == 'completed' ||
        status == 'cancelled' ||
        status == 'rejected';

    // Grey reference route: pickup → drop — straight line, no Directions API
    // call. Removed per cost decision (2026-09-05); previously called Google
    // Directions once per booking (cached after that), which was a smaller
    // but still nonzero cost across every booking ever tracked.
    if (pickupLatLng != null && dropLatLng != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('banner_pickup_drop'),
          points: [pickupLatLng, dropLatLng],
          color: Colors.grey.shade500,
          width: 4,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
    }

    String nextPhase = isCompleted
        ? 'Delivery completed'
        : (driverLatLng == null
            ? 'Waiting for driver location'
            : (isPostPickup ? 'Driver is heading to drop' : 'Driver is heading to pickup'));

    // Blue active route: driver → pickup before pickup, driver → drop after pickup.
    // Skipped once the booking is delivered/cancelled so the ETA doesn't keep
    // showing stale pickup/drop timing after the trip has ended.
    if (!isCompleted && driverLatLng != null) {
      final LatLng? activeTarget = isPostPickup
          ? (dropLatLng ?? pickupLatLng)
          : (pickupLatLng ?? dropLatLng);

      // Straight line only — no Directions API call here. This used to fetch
      // a routed polyline + ETA/distance every ~60s while the driver moved,
      // which billed Google Directions on every active delivery being
      // watched. Removed per cost decision (2026-09-05); a straight line
      // still shows direction of travel on the map without any API cost.
      if (activeTarget != null) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('banner_driver_active'),
            points: [driverLatLng, activeTarget],
            color: const Color(0xFF4285F4),
            width: 6,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
          ),
        );
      }
    }

    // Now construct the driver marker with the calculated nextEta!
    if (driverLatLng != null) {
      ui.Image? vehicleImg = _scooterImage;
      if (vehicleName.contains("mini") ||
          vehicleName.contains("loader") ||
          vehicleName.contains("tata") ||
          vehicleName.contains("ace") ||
          vehicleName.contains("diesel") ||
          vehicleName.contains("3 wheeler") ||
          vehicleName.contains("three")) {
        vehicleImg = _miniTruckImage;
      } else if (!vehicleName.contains("2 wheeler") &&
                 !vehicleName.contains("bike") &&
                 !vehicleName.contains("scooter") &&
                 vehicleName.isNotEmpty) {
        vehicleImg = _largeTruckImage;
      }

      final markerIcon = await _generateMarkerIcon("Live", vehicleImg);

      markers.add(Marker(
        markerId: const MarkerId("banner_driver"),
        position: driverLatLng,
        icon: markerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: "Driver live location"),
        anchor: const Offset(0.5, 0.8),
      ));
    }

    if (mounted) {
      setState(() {
        _bannerMarkers = markers;
        _bannerPolylines = polylines;
        _trackingPhaseText = nextPhase;
      });
    }
  }

  void _fitBannerCamera(
    LatLng? driver,
    LatLng? pickup,
    LatLng? drop,
  ) {
    final List<LatLng> points = [
      if (driver != null) driver,
      if (pickup != null) pickup,
      if (drop != null) drop,
    ];

    if (points.isEmpty) return;

    if (points.length == 1) {
      _safeAnimateCamera(
        CameraUpdate.newLatLngZoom(points.first, 15),
      );
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

    const double pad = 0.008;
    _safeAnimateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - pad, minLng - pad),
          northeast: LatLng(maxLat + pad, maxLng + pad),
        ),
        48,
      ),
    );
  }

  Future<void> _safeAnimateCamera(CameraUpdate update) async {
    if (!mounted || !_mapReady || _mapController == null) return;
    try {
      await _mapController!.animateCamera(update);
    } catch (e) {
      debugPrint('âš ï¸ [Customer live map] camera skipped: $e');
    }
  }

  // â”€â”€â”€ Parse lat/lng safely â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  double? _parseLatLng(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  void _openBannerMap() {
    final controller =
        Provider.of<BookingDetailController>(context, listen: false);
    final data = controller.bookingDetail;
    final pickup = data?['pickup_location'];
    final drop = data?['dropoff_location'];
    final vehicle = data?['vehicleType_id'];
    final subVehicle = data?['subVehicleType_id'];

    final dynamic dropLatRaw = drop?['latitude'] ?? pickup?['latitude'];
    final dynamic dropLngRaw = drop?['longitude'] ?? pickup?['longitude'];
    final double? targetLat = _parseLatLng(dropLatRaw);
    final double? targetLng = _parseLatLng(dropLngRaw);
    final double? pickupLat = _parseLatLng(pickup?['latitude']);
    final double? pickupLng = _parseLatLng(pickup?['longitude']);

    Get.to(() => MapImageScreen(
          userId: userId,
          driverId: '',
          bookingId: widget.bookingId,
          vehicleName: (subVehicle?['name'] ??
                  vehicle?['name'] ??
                  data?['display_vehicle_name'] ??
                  data?['requested_vehicle_name'] ??
                  '')
              .toString(),
          vehicleImage:
              (subVehicle?['image'] ?? vehicle?['image'] ?? '').toString(),
          targetLat: targetLat,
          targetLng: targetLng,
          pickupLat: pickupLat,
          pickupLng: pickupLng,
          dropLat: targetLat,
          dropLng: targetLng,
          bookingStatus: data?['booking_status']?.toString(),
        ));
  }

  void _zoomInBannerMap() {
    _safeAnimateCamera(CameraUpdate.zoomIn());
  }

  void _zoomOutBannerMap() {
    _safeAnimateCamera(CameraUpdate.zoomOut());
  }

  // â”€â”€â”€ Dial pad â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> openDialPad(String phoneNumber) async {
    final Uri uri = Uri.parse("tel:$phoneNumber");
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Dial pad error: $e");
    }
  }

  // â”€â”€â”€ Back handler â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _handleBack() {
    if (_allowPop) return;
    setState(() {
      _allowPop = true;
    });
    Get.offAll(() => const CustomBottomNav(
          userType: UserType.retailer,
          initialIndex: 1,
          bookingTabIndex: 0,
        ));
  }

  // â”€â”€â”€ Pull-to-refresh â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _refreshBooking() async {
    await Provider.of<BookingDetailController>(context, listen: false)
        .getBookingDetail(context, bookingId: widget.bookingId);
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  //  BUILD
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Consumer2<BookingDetailController, SocketProvider>(
          builder: (context, controller, socketProvider, _) {
            if (controller.isLoading) return const BookingDetailShimmer();

            final data = controller.bookingDetail;
            if (data == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        controller.errorMessage ?? 'Booking not found.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontFamily: AppFont.fontFamily,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: controller.isReassigned
                            ? () => _handleBack()
                            : () => _refreshBooking(),
                        child: Text(
                          controller.isReassigned ? 'Go back' : 'Retry',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            final vehicle = data['vehicleType_id'];
            final subVehicle = data['subVehicleType_id'];
            final size = MediaQuery.of(context).size;

            final String bookingStatus =
                data['booking_status']?.toString() ?? '';
            final bool isActiveBooking = bookingStatus != 'Delivered' &&
                bookingStatus != 'Cancelled';

            // â”€â”€ Rating + scratch card triggers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            if (bookingStatus == 'Delivered' &&
                !_hasShownRating &&
                data['driver_id'] != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_hasShownRating) {
                  _hasShownRating = true;
                  _showRatingSheet(context, data['driver_id']);
                }
              });
            }
            final int scratchCoins = (data['scratch_card_coins'] is num)
                ? (data['scratch_card_coins'] as num).toInt()
                : 0;
            if (data['scratch_card_pending'] == true &&
                !_hasShownScratch &&
                scratchCoins > 0) {
              _hasShownScratch = true;
              Future.delayed(const Duration(milliseconds: 2500), () {
                if (mounted) {
                  CoinScratchCardScreen.showIfNeeded(context,
                      bookingId: widget.bookingId, coins: scratchCoins);
                }
              });
            }

            // â”€â”€ Driver info â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            final rawDriver = data['driver'] ?? data['driver_id'];
            final Map<String, dynamic>? driver =
                rawDriver is Map ? Map<String, dynamic>.from(rawDriver) : null;
            final String driverName =
                (driver?['full_name'] ?? driver?['name'] ?? '').toString();
            final String driverPhone =
                (driver?['phone_number'] ?? driver?['phone'] ?? '').toString();
            final String driverPhoto =
                (driver?['profile_image'] ?? driver?['photo'] ?? '').toString();
            final String vehicleNumber = (data['vehicle_number'] ??
                    driver?['registration_number'] ??
                    driver?['vehicle_number'] ??
                    data['registration_number'] ??
                    '')
                .toString();
            final String bookingCode =
                (data['booking_code'] ?? '').toString();

            // â”€â”€ OTP (start pin only) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            final userCtrl =
                Provider.of<UserController>(context, listen: false);
            final String startPin = userCtrl.startPin.isNotEmpty
                ? userCtrl.startPin
                : (data['start_pin'] ?? '').toString().trim();
            final bool showOtp = isActiveBooking &&
                (bookingStatus == 'Accepted' ||
                    bookingStatus == 'Arrived' ||
                    bookingStatus == 'ArrivedAtPickup') &&
                !(data['start_pin_verified'] == true) &&
                startPin.isNotEmpty;

            // â”€â”€ Coordinates â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            final pickup = data['pickup_location'];
            final drop = data['dropoff_location'];
            final double? pickupLat = _parseLatLng(pickup?['latitude']);
            final double? pickupLng = _parseLatLng(pickup?['longitude']);
            final double? dropLat = _parseLatLng(drop?['latitude']);
            final double? dropLng = _parseLatLng(drop?['longitude']);
            final LatLng? pickupLatLng =
                (pickupLat != null && pickupLng != null)
                    ? LatLng(pickupLat, pickupLng)
                    : null;
            final LatLng? dropLatLng = (dropLat != null && dropLng != null)
                ? LatLng(dropLat, dropLng)
                : null;

            // â”€â”€ Driver live location (Pusher or API fallback) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            final liveLoc = socketProvider.lastDriverLocation;
            final Map<String, dynamic>? driverObj = data['driver_id'] is Map
                ? Map<String, dynamic>.from(data['driver_id'])
                : null;
            final double? driverApiLat = _parseLatLng(
                driverObj?['latitude'] ?? data['driver_lat']);
            final double? driverApiLng = _parseLatLng(
                driverObj?['longitude'] ?? data['driver_lng']);
            final double? liveLat =
                _parseLatLng(liveLoc?['lat'] ?? liveLoc?['latitude']);
            final double? liveLng =
                _parseLatLng(liveLoc?['lng'] ?? liveLoc?['longitude']);
            final LatLng? driverLatLng =
                (liveLat != null && liveLng != null)
                    ? LatLng(liveLat, liveLng)
                    : (driverApiLat != null && driverApiLng != null)
                        ? LatLng(driverApiLat, driverApiLng)
                        : null;

            // â”€â”€ Trigger marker update whenever driver moves â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            if (driverLatLng != null &&
                driverLatLng != _lastFittedDriverLocation) {
              _lastFittedDriverLocation = driverLatLng;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _updateBannerMarkers(
                  driverLatLng: driverLatLng,
                  pickupLatLng: pickupLatLng,
                  dropLatLng: dropLatLng,
                  bookingStatus: bookingStatus,
                );
              });
            }
            if (_bannerMarkers.isEmpty && _mapReady) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _updateBannerMarkers(
                  driverLatLng: driverLatLng,
                  pickupLatLng: pickupLatLng,
                  dropLatLng: dropLatLng,
                  bookingStatus: bookingStatus,
                );
              });
            }
            // Force one final recompute once the trip ends so the ETA/route
            // banner clears instead of freezing on the last pre-delivery value.
            if (!isActiveBooking && !_hasClearedCompletedBanner) {
              _hasClearedCompletedBanner = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _updateBannerMarkers(
                  driverLatLng: driverLatLng,
                  pickupLatLng: pickupLatLng,
                  dropLatLng: dropLatLng,
                  bookingStatus: bookingStatus,
                );
              });
            }

            final LatLng initialTarget = driverLatLng ??
                pickupLatLng ??
                dropLatLng ??
                const LatLng(22.7196, 75.8577);

            final bool canCancel =
                bookingStatus == 'Pending' || bookingStatus == 'Accepted';
            final String statusLabel = _trackingStatusLabel(bookingStatus);
            final Color statusColor = _trackingStatusColor(bookingStatus);

                        return Scaffold(
              backgroundColor: const Color(0xFFF8FAFC),
              body: Column(
                children: [
                  _buildTrackingHeader(bookingCode, statusLabel, statusColor),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Map Card Container — framed like it's inset into the page ──
                          Container(
                            height: MediaQuery.of(context).size.height * 0.42,
                            margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 2,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: Stack(
                                children: [
                                  _buildLiveMapBanner(initialTarget),
                                  // Inner hairline so the live map reads as embedded,
                                  // not just a plain rectangle sitting on the page.
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(15),
                                          border: Border.all(color: Colors.black.withOpacity(0.08), width: 1.2),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // ── Driver Details Card ──
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFECEFF3)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: statusColor, width: 2),
                                  ),
                                  child: _buildDriverAvatar(driverPhoto, driverName),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        driverName.isNotEmpty ? driverName : 'Assigning driver...',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
                                          fontFamily: AppFont.fontFamily,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${data['requested_vehicle_name'] ?? data['display_vehicle_name'] ?? subVehicle?['name'] ?? vehicle?['name'] ?? 'Vehicle'}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: Colors.grey.shade600,
                                          fontFamily: AppFont.fontFamily,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                        ),
                                        child: Text(
                                          vehicleNumber.isNotEmpty ? vehicleNumber : 'MP-00-XX-0000',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.4,
                                            color: Color(0xFF334155),
                                            fontFamily: AppFont.fontFamily,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (driverPhone.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () async {
                                      final uri = Uri(scheme: 'tel', path: driverPhone);
                                      try {
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      } catch (_) {}
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(11),
                                      decoration: const BoxDecoration(
                                        color: AppColor.themeColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.call_rounded,
                                        color: Colors.white,
                                        size: 19,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // ── Fare Details Card ──
                          _buildFareCard(data),

                          // ── Ride Start OTP (PIN) Card ──
                          if (showOtp) ...[
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FFF4),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.35)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.play_circle_rounded, color: Color(0xFF16A34A), size: 18),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'Ride Start PIN',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: AppFont.fontFamily,
                                          color: Color(0xFF16A34A),
                                        ),
                                      ),
                                      const Spacer(),
                                      GestureDetector(
                                        onTap: () {
                                          Clipboard.setData(ClipboardData(text: startPin));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('PIN copied!'),
                                              duration: Duration(seconds: 1),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        },
                                        child: const Icon(Icons.copy_rounded, size: 18, color: Color(0xFF16A34A)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  startPin.length <= 6
                                      ? Row(
                                          children: startPin
                                              .split('')
                                              .map((digit) => Container(
                                                    margin: const EdgeInsets.only(right: 8),
                                                    width: 40,
                                                    height: 44,
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(color: const Color(0xFF22C55E)),
                                                    ),
                                                    alignment: Alignment.center,
                                                    child: Text(
                                                      digit,
                                                      style: const TextStyle(
                                                        fontSize: 20,
                                                        fontWeight: FontWeight.w700,
                                                        color: Color(0xFF16A34A),
                                                        fontFamily: AppFont.fontFamily,
                                                      ),
                                                    ),
                                                  ))
                                              .toList(),
                                        )
                                      : SelectableText(
                                          startPin,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF16A34A),
                                            fontFamily: AppFont.fontFamily,
                                          ),
                                        ),
                                ],
                              ),
                            ),
                          ],

                          // ── Pickup & Drop Address Details Card (Timeline style) ──
                          _buildTimelineCard(data, pickup, drop, size),

                          // ── Cancel Link/Button ──
                          if (canCancel) ...[
                            const SizedBox(height: 12),
                            Center(
                              child: GestureDetector(
                                onTap: () => _showCancelPopup(context, bookingCode: bookingCode, bookingStatus: bookingStatus),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  child: const Text(
                                    'Cancel Booking',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: AppFont.fontFamily,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              )            );
          },
        ),
      ),
    );
  }

  // Custom header for this screen — carries the live status as a coloured
  // chip next to the trip code instead of a separate centred status line,
  // so the two pieces of information a customer glances at first (which
  // trip, what stage) sit together in one place.
  Widget _buildTrackingHeader(String bookingCode, String statusLabel, Color statusColor) {
    return SafeArea(
      bottom: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(8, 6, 16, 12),
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _handleBack,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A), size: 22),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bookingCode.isNotEmpty ? 'Trip $bookingCode' : 'Trip Details',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      fontFamily: AppFont.fontFamily,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                      fontFamily: AppFont.fontFamily,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Same always-visible "Help" pill as the driver app's active-ride
            // header — previously the only way to reach Help & Support here
            // was buried inside the Cancel Booking popup, which disappears
            // once the booking passes the cancellable window.
            InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: () {
                Get.to(() => bookingHelpAndSupport(
                      bookingId: widget.bookingId,
                      bookingCode: bookingCode,
                    ));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.green.shade600,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.support_agent, color: Colors.white, size: 20),
                    SizedBox(width: 6),
                    Text(
                      'Help',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFamily: AppFont.fontFamily,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverAvatar(String photoUrl, String name) {
    final initials = name.trim().isNotEmpty
        ? name
            .trim()
            .split(' ')
            .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
            .take(2)
            .join()
        : '?';
    if (photoUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          cacheWidth: 100,
          errorBuilder: (_, __, ___) => _initialsAvatar(initials),
        ),
      );
    }
    return _initialsAvatar(initials);
  }

  Widget _initialsAvatar(String initials) {
    return Container(
      width: 50,
      height: 50,
      decoration: const BoxDecoration(
        color: Color(0xFF1A3C6E),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 16,
          fontFamily: AppFont.fontFamily,
        ),
      ),
    );
  }

  String _trackingStatusLabel(String status) {
    switch (status) {
      case 'Accepted':
        return 'Driver on the way';
      case 'Arrived':
      case 'ArrivedAtPickup':
        return 'Driver arrived';
      case 'Pickup':
      case 'PickedUp':
        return 'Pickup confirmed';
      case 'Ongoing':
      case 'OnTheWay':
        return 'Delivery in progress';
      case 'Delivered':
        return 'Delivered';
      case 'Cancelled':
        return 'Cancelled';
      default:
        return status.isNotEmpty ? status : 'Finding driver...';
    }
  }

  Color _trackingStatusColor(String status) {
    switch (status) {
      case 'Accepted':
      case 'Arrived':
      case 'ArrivedAtPickup':
        return const Color(0xFFF59E0B);
      case 'Pickup':
      case 'PickedUp':
      case 'Ongoing':
      case 'OnTheWay':
        return const Color(0xFF3B82F6);
      case 'Delivered':
        return const Color(0xFF22C55E);
      case 'Cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  //  LIVE MAP BANNER  (active booking)
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  Widget _buildLiveMapBanner(LatLng initialTarget) {
    final controller =
        Provider.of<BookingDetailController>(context, listen: false);
    final data = controller.bookingDetail;
    final pickup = data?['pickup_location'];
    final drop = data?['dropoff_location'];
    final String bannerBookingStatus = data?['booking_status']?.toString() ?? '';
    final bool isActiveBooking = bannerBookingStatus != 'Delivered' &&
        bannerBookingStatus != 'Cancelled';

    // ── Determine destination/pickup coordinates ──
    final dynamic dropLatRaw = drop?['latitude'] ?? pickup?['latitude'];
    final dynamic dropLngRaw = drop?['longitude'] ?? pickup?['longitude'];
    final dynamic pickupLatRaw = pickup?['latitude'];
    final dynamic pickupLngRaw = pickup?['longitude'];

    final double? targetLat = dropLatRaw is num
        ? dropLatRaw.toDouble()
        : double.tryParse(dropLatRaw?.toString() ?? "");
    final double? targetLng = dropLngRaw is num
        ? dropLngRaw.toDouble()
        : double.tryParse(dropLngRaw?.toString() ?? "");
    final double? pLat = pickupLatRaw is num
        ? pickupLatRaw.toDouble()
        : double.tryParse(pickupLatRaw?.toString() ?? "");
    final double? pLng = pickupLngRaw is num
        ? pickupLngRaw.toDouble()
        : double.tryParse(pickupLngRaw?.toString() ?? "");

    final LatLng? targetLatLng = (targetLat != null && targetLng != null) ? LatLng(targetLat, targetLng) : null;
    final LatLng? pickupLatLng = (pLat != null && pLng != null) ? LatLng(pLat, pLng) : null;

    final liveLoc = Provider.of<SocketProvider>(context, listen: false).lastDriverLocation;
    final Map<String, dynamic>? driverObj = data?['driver_id'] is Map
        ? Map<String, dynamic>.from(data?['driver_id'])
        : null;
    final double? driverApiLat = _parseLatLng(driverObj?['latitude'] ?? data?['driver_lat']);
    final double? driverApiLng = _parseLatLng(driverObj?['longitude'] ?? data?['driver_lng']);
    final double? liveLat = _parseLatLng(liveLoc?['lat'] ?? liveLoc?['latitude']);
    final double? liveLng = _parseLatLng(liveLoc?['lng'] ?? liveLoc?['longitude']);
    final LatLng? driverLatLng = (liveLat != null && liveLng != null)
        ? LatLng(liveLat, liveLng)
        : (driverApiLat != null && driverApiLng != null)
            ? LatLng(driverApiLat, driverApiLng)
            : null;

    return Stack(
      children: [
          // ── Google Map ──
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: initialTarget,
                zoom: 14,
              ),
              markers: _bannerMarkers,
              polylines: _bannerPolylines,
              myLocationButtonEnabled: false,
              myLocationEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: true,
              minMaxZoomPreference: const MinMaxZoomPreference(3, 20),
              tiltGesturesEnabled: true,
              rotateGesturesEnabled: true,
              scrollGesturesEnabled: true,
              zoomGesturesEnabled: true,
              mapToolbarEnabled: false,
              liteModeEnabled: false,
              mapType: MapType.normal,
              onMapCreated: (ctrl) {
                _mapController = ctrl;
                // Custom style to hide distracting landmarks and business POIs
                ctrl.setMapStyle('''
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
                if (!_mapCompleter.isCompleted) {
                  _mapCompleter.complete(ctrl);
                }
                debugPrint("✅ [Banner] GoogleMap created");
                setState(() => _mapReady = true);
              },
            ),
          ),

          // ── Tracking Phase Banner (Top-Left) ──
          // No ETA/distance text here anymore — that came from a Google
          // Directions API call refreshed every ~60s per active delivery,
          // which billed on every booking anyone had open. Removed per cost
          // decision (2026-09-05); this phase label is derived locally from
          // booking status, no API call involved.
          if (driverLatLng != null && isActiveBooking)
            Positioned(
              top: 14,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  _trackingPhaseText,
                  style: const TextStyle(
                    fontFamily: AppFont.fontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColor.blackColor,
                  ),
                ),
              ),
            ),

          // ── Zoom In / Zoom Out Buttons (Bottom-Left) ──
          Positioned(
            bottom: 14,
            left: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _zoomInBannerMap,
                  child: Container(
                    width: 38,
                    height: 38,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Colors.black87,
                      size: 22,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _zoomOutBannerMap,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.remove_rounded,
                      color: Colors.black87,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Fit Bounds / Maximize Button (Top-Right) ──
          Positioned(
            top: 14,
            right: 14,
            child: GestureDetector(
              onTap: () {
                _fitBannerCamera(driverLatLng, pickupLatLng, targetLatLng);
              },
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.fullscreen_exit_rounded,
                  color: Colors.black87,
                  size: 22,
                ),
              ),
            ),
          ),

          // ── GPS / Center Focus & Refresh Buttons (Bottom-Right) ──
          Positioned(
            bottom: 14,
            right: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // GPS Focus
                GestureDetector(
                  onTap: () {
                    _fitBannerCamera(driverLatLng, pickupLatLng, targetLatLng);
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.gps_fixed_rounded,
                      color: Colors.black87,
                      size: 20,
                    ),
                  ),
                ),
                // Refresh
                GestureDetector(
                  onTap: () async {
                    final socketProv = Provider.of<SocketProvider>(context, listen: false);
                    final bookingCtrl = Provider.of<BookingDetailController>(context, listen: false);
                    // Emit fresh location request
                    socketProv.emitDriverLiveLocation(
                      userId: userId,
                      bookingId: widget.bookingId,
                    );
                    // Refresh booking data from API without flashing the
                    // full-screen shimmer over the map/tracking view.
                    await bookingCtrl.getBookingDetail(context, bookingId: widget.bookingId, silent: true);
                    // Rebuild markers with latest data
                    if (mounted) {
                      final data = bookingCtrl.bookingDetail;
                      final pickup = data?['pickup_location'];
                      final drop = data?['dropoff_location'];
                      final pLat = _parseLatLng(pickup?['latitude']);
                      final pLng = _parseLatLng(pickup?['longitude']);
                      final dLat = _parseLatLng(drop?['latitude']);
                      final dLng = _parseLatLng(drop?['longitude']);
                      final liveLoc = socketProv.lastDriverLocation;
                      final driverObj = data?['driver_id'] is Map ? Map<String, dynamic>.from(data?['driver_id']) : null;
                      final liveLat = _parseLatLng(liveLoc?['lat'] ?? liveLoc?['latitude']);
                      final liveLng = _parseLatLng(liveLoc?['lng'] ?? liveLoc?['longitude']);
                      final apiLat = _parseLatLng(driverObj?['latitude'] ?? data?['driver_lat']);
                      final apiLng = _parseLatLng(driverObj?['longitude'] ?? data?['driver_lng']);
                      final driverLatLng = (liveLat != null && liveLng != null)
                          ? LatLng(liveLat, liveLng)
                          : (apiLat != null && apiLng != null) ? LatLng(apiLat, apiLng) : null;
                      _updateBannerMarkers(
                        driverLatLng: driverLatLng,
                        pickupLatLng: (pLat != null && pLng != null) ? LatLng(pLat, pLng) : null,
                        dropLatLng: (dLat != null && dLng != null) ? LatLng(dLat, dLng) : null,
                        bookingStatus: data?['booking_status']?.toString(),
                      );
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Map refreshed'),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.black87,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStaticImageBanner() {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(AppImage.liveimage),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  // â”€â”€â”€ Price row helper â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _priceRow(String label, String value, {bool isBold = false}) {
    final style = TextStyle(
      fontSize: isBold ? 16 : 14,
      fontWeight: isBold ? FontWeight.w600 : FontWeight.w500,
      fontFamily: AppFont.fontFamily,
      color: AppColor.thirdTextColor,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }

  Widget _buildContactsSummarySection(Map<String, dynamic> data, Size size) {
    final senderName = (data['customer_name'] ?? data['sender_name'] ?? '').toString().trim();
    final senderPhone = (data['customer_phone'] ?? data['sender_phone'] ?? '').toString().trim();
    final receiverName = (data['receiver_name'] ?? '').toString().trim();
    final receiverPhone = (data['receiver_phone'] ?? '').toString().trim();

    if (senderPhone.isEmpty && receiverPhone.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Contact Details",
            style: TextStyle(
              fontFamily: AppFont.fontFamily,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColor.blackColor,
            ),
          ),
          const SizedBox(height: 12),
          if (senderPhone.isNotEmpty) ...[
            _contactRow(
              icon: Icons.person_pin_rounded,
              iconColor: AppColor.successCOlor,
              title: "Sender (Pickup)",
              name: senderName.isNotEmpty ? senderName : "Sender Contact",
              phone: senderPhone,
            ),
          ],
          if (senderPhone.isNotEmpty && receiverPhone.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: Color(0xffE2E8F0), height: 1),
            ),
          if (receiverPhone.isNotEmpty) ...[
            _contactRow(
              icon: Icons.import_contacts_rounded,
              iconColor: AppColor.redColor,
              title: "Receiver (Dropoff)",
              name: receiverName.isNotEmpty ? receiverName : "Receiver Contact",
              phone: receiverPhone,
            ),
          ],
        ],
      ),
    );
  }

  Widget _contactRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String name,
    required String phone,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 16),
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
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  color: AppColor.secondTextColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: const TextStyle(
                  fontFamily: AppFont.fontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColor.blackColor,
                ),
              ),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: () => openDialPad(phone),
                child: Text(
                  "+91 $phone  ðŸ“ž",
                  style: const TextStyle(
                    fontFamily: AppFont.fontFamily,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: AppColor.themeColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // â”€â”€â”€ OTP Card Widget â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildOtpCard({
    required String otp,
    required String label,
    required String subtitle,
    required Size size,
  }) {
    if (otp.isEmpty) return const SizedBox();

    final bool isStartOtp = label.toLowerCase().contains('start');
    final Color cardColor = isStartOtp
        ? const Color(0xFFE8F5E9)   // soft green for start
        : const Color(0xFFE3F2FD);  // soft blue for end
    final Color borderColor = isStartOtp
        ? const Color(0xFF2E7D32)
        : AppColor.themeColor;

    return Container(
      width: size.width,
      padding: EdgeInsets.symmetric(
        horizontal: size.width * 0.04,
        vertical: size.height * 0.016,
      ),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // â”€â”€ Label badge â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Row(
            children: [
              Icon(
                isStartOtp ? Icons.play_circle_rounded : Icons.flag_rounded,
                color: borderColor,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: AppFont.fontFamily,
                  color: borderColor,
                ),
              ),
            ],
          ),

          SizedBox(height: size.height * 0.008),

          // â”€â”€ Subtitle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              fontFamily: AppFont.fontFamily,
              color: borderColor.withOpacity(0.8),
            ),
          ),

          SizedBox(height: size.height * 0.012),

          // â”€â”€ OTP digit boxes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    "OTP : ",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppFont.fontFamily,
                      color: borderColor,
                    ),
                  ),
                  ...otp.split('').map(
                    (digit) => Container(
                      margin: const EdgeInsets.only(right: 6),
                      height: 38,
                      width: 34,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderColor, width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          digit,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: borderColor,
                            fontFamily: AppFont.fontFamily,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Copy to clipboard
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: otp));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$label copied!'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Icon(Icons.copy_rounded, color: borderColor, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  //  CANCEL POPUP
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  void _showRatingSheet(BuildContext context, dynamic driverId) {
    int selectedRating = 0;
    final reviewCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Delivery Complete! ðŸŽ‰', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('How was your experience with the driver?', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) => GestureDetector(
                  onTap: () => setS(() => selectedRating = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(i < selectedRating ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFFFC107), size: 40),
                  ),
                )),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reviewCtrl,
                decoration: InputDecoration(hintText: 'Leave a review (optional)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(padding: const EdgeInsets.symmetric(vertical: 13), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)), child: const Center(child: Text('Skip', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: selectedRating == 0 ? null : () async {
                        Navigator.pop(ctx);
                        try {
                          final url = Uri.parse('${AppConstant.apiBaseUrl}booking/rate_driver');
                          await http.post(url, headers: {'Authorization': 'Bearer ${AppConstant.token}', 'Content-Type': 'application/json'},
                            body: jsonEncode({'booking_id': widget.bookingId, 'driver_id': driverId.toString(), 'rating': selectedRating, 'review': reviewCtrl.text.trim()}));
                        } catch (_) {}
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(color: selectedRating == 0 ? Colors.grey.shade300 : AppColor.themeColor, borderRadius: BorderRadius.circular(10)),
                        child: const Center(child: Text('Submit Rating', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCancelPopup(
    BuildContext context, {
    required String bookingCode,
    required String? bookingStatus,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        final size = MediaQuery.of(context).size;
        return GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Material(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.only(
                  top: size.height * 8 / 100,
                  left: size.width * 0.05,
                ),
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    width: size.width * 0.59,
                    padding: EdgeInsets.symmetric(
                      horizontal: size.width * 0.04,
                      vertical: size.height * 0.02,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: size.width * 0.03,
                        vertical: size.height * 0.02,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () {
                              Navigator.pop(context);
                              Get.to(() => bookingHelpAndSupport(
                                    bookingId: widget.bookingId,
                                    bookingCode: bookingCode,
                                  ));
                            },
                            child: const Text(
                              "Help & Support",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                fontFamily: AppFont.fontFamily,
                                color: AppColor.blackColor,
                              ),
                            ),
                          ),
                          SizedBox(height: size.height * 0.01),
                          // Allow cancel: Pending or Accepted
                          if (bookingStatus != null &&
                              (bookingStatus == 'Pending' || bookingStatus == 'Accepted'))
                            InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                Get.to(() => CancellationPolicyScreen(
                                      bookingCode: bookingCode,
                                      bookingId: widget.bookingId,
                                      confirmbook: true,
                                    ));
                              },
                              child: const Text(
                                "Cancel Booking",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: AppFont.fontFamily,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          // Blocked: driver has started moving
                          if (bookingStatus != null &&
                              (bookingStatus == 'Arrived' ||
                               bookingStatus == 'Pickup' ||
                               bookingStatus == 'Ongoing'))
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                "Cannot cancel â€” driver is on the way",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontFamily: AppFont.fontFamily,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
