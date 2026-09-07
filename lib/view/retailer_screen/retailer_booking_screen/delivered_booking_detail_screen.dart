import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:get/get.dart';

import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_header.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/Controller/retailer_home_cotroller.dart';
import 'package:movigo/Controller/get_booking_details_provider.dart';
import 'package:movigo/helper/date_time_format/date_time_format.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/view/customer_screen/new_booking_flow/retailer_confirm_screen.dart';
import 'package:movigo/view/customer_screen/new_booking_flow/route_vehicle_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

class RDeliveredBookingDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? bookingData;
  const RDeliveredBookingDetailScreen({super.key, this.bookingData});

  @override
  State<RDeliveredBookingDetailScreen> createState() =>
      _RDeliveredBookingDetailScreenState();
}

class _RDeliveredBookingDetailScreenState
    extends State<RDeliveredBookingDetailScreen> {
  Widget _displayImage(String? path, String fallback) {
    if (path == null || path.isEmpty) {
      return Image.asset(fallback, fit: BoxFit.cover, width: 48, height: 48);
    }
    if (path.startsWith('http') || path.startsWith('https')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        width: 48,
        height: 48,
        cacheWidth: 100,
        errorBuilder: (_, __, ___) => Image.asset(fallback, fit: BoxFit.cover, width: 48, height: 48),
      );
    }
    return Image.asset(path, fit: BoxFit.cover, width: 48, height: 48);
  }


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final homeCtrl = Provider.of<RetailerHomeController>(context, listen: false);
      final booking = widget.bookingData ?? homeCtrl.ongoingBookings.firstWhere(
        (b) {
          final s = (b['booking_status'] ?? b['status'] ?? '').toString().toLowerCase();
          return s.contains('deliver') || s.contains('complete');
        },
        orElse: () => null,
      );
      final String? bookingId = booking?['_id']?.toString();
      if (bookingId != null && bookingId.isNotEmpty) {
        Provider.of<BookingDetailController>(context, listen: false).reset();
        Provider.of<BookingDetailController>(context, listen: false)
            .getBookingDetail(context, bookingId: bookingId);
      }
    });
  }

  // ── Priority Pickup outcome — informational only. Movigo never moves the
  // retailer's money for this feature; this just reports what actually
  // happened (on-time/late) and what was paid to the driver directly.
  Widget _priorityOutcomeBanner(Map<String, dynamic> booking) {
    final String outcome = booking['priorityOutcome']?.toString() ?? 'pending';
    final int chargeAmount = int.tryParse(booking['priorityChargeAmount']?.toString() ?? '') ?? 0;
    final bool charged = outcome == 'priority_charged';

    final String message = charged
        ? 'Priority Pickup: your driver arrived on time. You paid ₹$chargeAmount priority fee along with the base fare.'
        : 'Priority Pickup: the priority window was missed, so no priority fee was charged — you paid the base fare only.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: charged ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: charged ? const Color(0xFF10B981) : const Color(0xFFCBD5E1)),
      ),
      child: Row(
        children: [
          Text(charged ? '⚡' : 'ℹ️', style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: AppFont.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: charged ? const Color(0xFF047857) : const Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _bookAgain(Map<String, dynamic> booking) {
    final pickupLoc = booking['pickup_location'];
    final dropLoc   = booking['dropoff_location'];
    if (pickupLoc == null || dropLoc == null) return;

    final double? pickupLat = double.tryParse(pickupLoc['latitude']?.toString() ?? '');
    final double? pickupLng = double.tryParse(pickupLoc['longitude']?.toString() ?? '');
    final double? dropLat   = double.tryParse(dropLoc['latitude']?.toString() ?? '');
    final double? dropLng   = double.tryParse(dropLoc['longitude']?.toString() ?? '');
    if (pickupLat == null || pickupLng == null || dropLat == null || dropLng == null) return;

    // Multi-drop bookings carry every stop (final drop included) in extra_drops.
    // Route those through the main vehicle-selection flow (RouteVehicleScreen
    // → NewConfirmScreen), pre-filled and skipped straight to the booking
    // phase, so stops/contacts aren't dropped and "Book Again" lands on the
    // same screen as a normal booking would.
    final List<dynamic> extraDrops = booking['extra_drops'] is List ? booking['extra_drops'] as List : [];
    if (extraDrops.length > 1) {
      final validDrops = <Map<String, dynamic>>[];
      for (final d in extraDrops) {
        if (d is! Map) continue;
        final lat = double.tryParse(d['latitude']?.toString() ?? '');
        final lng = double.tryParse(d['longitude']?.toString() ?? '');
        if (lat == null || lng == null) continue;
        validDrops.add({
          'address':      (d['address'] ?? '').toString(),
          'lat':          lat,
          'lng':          lng,
          'contactName':  (d['contact_name']  ?? '').toString(),
          'contactPhone': (d['contact_phone'] ?? '').toString(),
        });
      }
      if (validDrops.length > 1) {
        // extra_drops' last entry is the final destination — the rest are
        // the intermediate stops RouteVehicleScreen's _extraStops expects.
        final finalStop = validDrops.removeLast();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RouteVehicleScreen(
              pickupLatLng:        LatLng(pickupLat, pickupLng),
              pickupAddress:       (pickupLoc['address'] ?? '').toString(),
              pickupContactName:   (booking['sender_name']  ?? booking['customer_name']  ?? '').toString(),
              pickupContactPhone:  (booking['sender_phone'] ?? booking['customer_phone'] ?? '').toString(),
              dropLatLng:          LatLng(finalStop['lat'] as double, finalStop['lng'] as double),
              dropAddress:         finalStop['address'] as String,
              dropContactName:     finalStop['contactName'] as String,
              dropContactPhone:    finalStop['contactPhone'] as String,
              initialExtraStops:   validDrops,
              skipLocationPhase:   true,
            ),
          ),
        );
        return;
      }
    }

    int wc(String tag) {
      final t = tag.toLowerCase();
      if (t.contains('2w') || t.contains('scooter') || t.contains('bike')) return 2;
      if (t.contains('3w') || t.contains('loader')) return 3;
      return 4;
    }
    String extractId(dynamic f) {
      if (f == null) return '';
      if (f is Map) return (f['_id'] ?? '').toString();
      return f.toString();
    }
    final String requiredTag = (booking['required_tag'] ?? booking['vehicle_category'] ?? '').toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RetailerConfirmScreen(
          vehicleTypeId:    extractId(booking['vehicleType_id'] ?? booking['vehicle_type_id']),
          subVehicleTypeId: extractId(booking['subVehicleType_id'] ?? booking['sub_vehicle_type_id']),
          vehicleData: {
            'name':               (booking['requested_vehicle_name'] ?? booking['display_vehicle_name'] ?? 'Vehicle').toString(),
            'wheelCount':         wc(requiredTag),
            'vehicleCategory':    (booking['vehicle_category'] ?? requiredTag).toString(),
            'pricingModifier':    '1.0',
            'vehicleKey':         (booking['vehicle_key'] ?? '').toString(),
            'requiredTag':        requiredTag,
            'bookingFlow':        'retailer',
            'displayVehicleName': (booking['display_vehicle_name'] ?? '').toString(),
          },
          pickupData: {'address': (pickupLoc['address'] ?? '').toString(), 'lat': pickupLat, 'lng': pickupLng},
          dropData:   {'address': (dropLoc['address']   ?? '').toString(), 'lat': dropLat,   'lng': dropLng},
          rawDistanceKm:  double.tryParse((booking['distance_in_km'] ?? booking['raw_distance_km'] ?? '0').toString()) ?? 0.0,
          estimatedFare:  int.tryParse((booking['booking_price'] ?? '0').toString()) ?? 0,
          subVehicleTypeList: const [],
          initialReceiverName:  (booking['receiver_name']  ?? '').toString(),
          initialReceiverPhone: (booking['receiver_phone'] ?? '').toString(),
          initialSenderName:    (booking['sender_name']  ?? booking['customer_name']  ?? '').toString(),
          initialSenderPhone:   (booking['sender_phone'] ?? booking['customer_phone'] ?? '').toString(),
          initialNote:          (booking['note'] ?? '').toString(),
          initialGoodsTypeId:   extractId(booking['item_category_id']),
          initialIsPriorityPickup: booking['isPriorityPickup'] == true,
        ),
      ),
    );
  }

  void _showRatingSheet(BuildContext context) {
    int selectedRating = 0;
    final reviewCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Delivery Complete! 🎉', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFamily: AppFont.fontFamily)),
              const SizedBox(height: 6),
              const Text('How was your experience with the driver?', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey, fontFamily: AppFont.fontFamily)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) => GestureDetector(
                  onTap: () => setS(() => selectedRating = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      i < selectedRating ? Icons.star_rounded : Icons.star_border_rounded,
                      color: const Color(0xFFFFC107),
                      size: 40,
                    ),
                  ),
                )),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reviewCtrl,
                decoration: InputDecoration(
                  hintText: 'Leave a review (optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                        child: const Center(child: Text('Skip', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: selectedRating == 0 ? null : () async {
                        Navigator.pop(ctx);
                        try {
                          await http.post(
                            Uri.parse('${AppConstant.apiBaseUrl}booking/rate_driver'),
                            headers: {
                              'Authorization': 'Bearer ${AppConstant.token}',
                              'Content-Type': 'application/json',
                            },
                            body: jsonEncode({
                              'rating': selectedRating,
                              'review': reviewCtrl.text.trim(),
                            }),
                          );
                        } catch (_) {}
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Thank you for your rating!'),
                          behavior: SnackBarBehavior.floating,
                        ));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: selectedRating == 0 ? Colors.grey.shade300 : AppColor.themeColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(child: Text('Submit Rating', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily))),
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

  Map<String, double> _calculateTaxBreakdown(double total) {
    final gst = double.parse((total * 0.18).toStringAsFixed(2));
    return {
      'tripFare': total,
      'gst': gst,
      'total': total,
    };
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final homeCtrl = Provider.of<RetailerHomeController>(context);
    final detailCtrl = Provider.of<BookingDetailController>(context);
    final apiBooking = detailCtrl.bookingDetail;

    final Map<String, dynamic> booking = {};
    
    // Add default structures
    booking.addAll({
      "booking_code": "",
      "pickup": "Pickup address",
      "drop": "Dropoff address",
      "price": "0"
    });

    

    if (widget.bookingData != null) {
      booking.addAll(widget.bookingData!);
    }

    final String currentId = booking['_id']?.toString() ?? '';
    if (apiBooking != null && apiBooking['_id']?.toString() == currentId) {
      booking.addAll(apiBooking);
    }

    final String bookingId = booking['_id']?.toString() ?? booking['booking_code']?.toString() ?? '';
    final String bookingCodeDisplay = booking['booking_code']?.toString() ?? 
        (bookingId.length >= 6 ? bookingId.substring(bookingId.length - 6) : bookingId);

    // Ride Details
    final String pickupAddress = booking['pickup_location']?['address']?.toString() ?? booking['pickup']?.toString() ?? 'Pickup location not specified';
    final String dropAddress = booking['dropoff_location']?['address']?.toString() ?? booking['drop']?.toString() ?? 'Dropoff location not specified';
    // extra_drops includes the final drop as its last entry — only the earlier
    // entries are intermediate stops (dropAddress above already covers the last one).
    final List<dynamic> _allExtraDrops = booking['extra_drops'] is List ? booking['extra_drops'] as List : [];
    final List<dynamic> intermediateStops = _allExtraDrops.length > 1 ? _allExtraDrops.sublist(0, _allExtraDrops.length - 1) : [];

    // Driver info
    final rawDriver = booking['driver'] ?? booking['driver_id'];
    final Map<String, dynamic>? driverObj = rawDriver is Map ? Map<String, dynamic>.from(rawDriver) : null;
    final String driverName = driverObj?['full_name']?.toString() ?? driverObj?['name']?.toString() ?? booking['name']?.toString() ?? '';
    final String driverProfileImage = driverObj?['profile_image']?.toString() ?? driverObj?['photo']?.toString() ?? booking['profile']?.toString() ?? '';
    final String vehicleNumber = booking['vehicle_number']?.toString() ?? driverObj?['registration_number']?.toString() ?? driverObj?['vehicle_number']?.toString() ?? booking['registration_number']?.toString() ?? '';
    final String vehicleName = booking['requested_vehicle_name']?.toString() ?? driverObj?['vehicle_name']?.toString() ?? booking['vehicle_name']?.toString() ?? '';
    
    final String rawPrice = (booking['booking_price'] ?? booking['price'] ?? '0').toString().replaceAll('₹', '').trim();
    final double totalFareAmount = double.tryParse(rawPrice) ?? 0.0;
    final breakdown = _calculateTaxBreakdown(totalFareAmount);

    // ── Priority Pickup — quoted booking_price already includes the priority
    // fee (a preview taken at booking time), but it was only actually paid
    // to the driver if the pickup was on time. Split it back out here so the
    // receipt shows the real trip fare, the priority fee as its own line,
    // and the correct final amount actually paid.
    final bool isPriority = booking['isPriorityPickup'] == true;
    final double priorityFeeAmount = double.tryParse(booking['priorityChargeAmount']?.toString() ?? '') ?? 0.0;
    final bool priorityCollected = booking['priorityOutcome']?.toString() == 'priority_charged';
    final double baseTripFare = isPriority ? (totalFareAmount - priorityFeeAmount) : totalFareAmount;
    final double finalAmountToPay = baseTripFare + (isPriority && priorityCollected ? priorityFeeAmount : 0);

    // Backend sends the standard Mongoose `createdAt` ISO timestamp — there is
    // no `created_at` field (snake_case) on the booking payload, so this was
    // always falling through to the raw `pickup_date` (a date-only Mongoose
    // Date, always midnight) and leaking "T00:00:00" into the UI.
    final rawCreatedAt = booking['createdAt'];
    String displayDateTime = '';
    if (rawCreatedAt is String && rawCreatedAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(rawCreatedAt).toLocal();
        const _m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
        displayDateTime = "${dt.day.toString().padLeft(2,'0')} ${_m[dt.month-1]} ${dt.year}, ${h.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')} ${dt.hour >= 12 ? 'PM' : 'AM'}";
      } catch (_) {
        displayDateTime = rawCreatedAt;
      }
    }
    if (displayDateTime.isEmpty) {
      final pickupDate = BookingDateTimeHelper.isoDateToUi(booking['pickup_date']?.toString());
      final pickupSlot = booking['pickup_slot']?.toString() ?? '';
      if (pickupDate != '-') displayDateTime = pickupSlot.isNotEmpty ? "$pickupDate, $pickupSlot" : pickupDate;
    }

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Icon(Icons.arrow_back, color: Colors.black),
                ),
                const SizedBox(width: 20),
                const Text(
                  "Trip details",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: AppFont.fontFamily,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Date & CRN info Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (displayDateTime.isNotEmpty)
                              Text(
                                displayDateTime,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: AppFont.fontFamily,
                                  color: Colors.black87,
                                ),
                              ),
                            if (displayDateTime.isNotEmpty) const SizedBox(height: 2),
                            if (bookingCodeDisplay.isNotEmpty)
                              Text(
                                "#$bookingCodeDisplay",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: AppFont.fontFamily,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                          ],
                        ),
                        Text(
                          "₹ ${breakdown['total']?.toStringAsFixed(1)}",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: AppFont.fontFamily,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFEEEEEE)),
                    const SizedBox(height: 14),

                    // Rate driver row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Rate your driver",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: AppFont.fontFamily,
                            color: Colors.black87,
                          ),
                        ),
                        Row(
                          children: List.generate(5, (index) => GestureDetector(
                            onTap: () => _showRatingSheet(context),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 3),
                              child: Icon(Icons.star_border_rounded, color: Colors.black54, size: 24),
                            ),
                          )),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: Color(0xFFEEEEEE)),
                    const SizedBox(height: 16),

                    // Driver details card
                    if (driverName.isNotEmpty && driverName != 'Assigning driver...') ...[
                      const Text(
                        "Driver details",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: AppFont.fontFamily,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  driverName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: AppFont.fontFamily,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  vehicleNumber.isNotEmpty ? "$vehicleName ($vehicleNumber)" : vehicleName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: AppFont.fontFamily,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                () {
                                  final _ca = widget.bookingData?['createdAt']?.toString();
                                  final _dt = (_ca == null || _ca.isEmpty) ? '' : WalletDateTimeHelper.apiToFigmaDateTime(_ca);
                                  if (_dt.isEmpty || _dt == '-') return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(
                                      [if (bookingCodeDisplay.isNotEmpty) '#$bookingCodeDisplay', _dt].join('  •  '),
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontFamily: AppFont.fontFamily),
                                    ),
                                  );
                                }(),
                              ],
                            ),
                          ),
                          Image.asset(
                            (vehicleName.toLowerCase().contains("loader") || 
                             vehicleName.toLowerCase().contains("auto") || 
                             vehicleName.toLowerCase().contains("3w") || 
                             vehicleName.toLowerCase().contains("3 wheeler"))
                                ? AppImage.eloader
                                : (vehicleName.toLowerCase().contains("2w") || 
                                   vehicleName.toLowerCase().contains("two") || 
                                   vehicleName.toLowerCase().contains("bike") || 
                                   vehicleName.toLowerCase().contains("scoot"))
                                    ? AppImage.twowheel
                                    : AppImage.minitruck,
                            height: 32,
                            width: 32,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Divider(height: 1, color: Color(0xFFEEEEEE)),
                      const SizedBox(height: 14),
                    ],

                    // Addresses Connections
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(color: const Color(0xFF22C55E), width: 5),
                              ),
                            ),
                            Container(
                              width: 1.5,
                              height: 38,
                              color: Colors.grey.shade300,
                            ),
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.rectangle,
                                color: Colors.white,
                                border: Border.all(color: const Color(0xFFEF4444), width: 5),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pickupAddress,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontFamily: AppFont.fontFamily,
                                  color: Colors.black87,
                                ),
                              ),
                              for (int _i = 0; _i < intermediateStops.length; _i++) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'Stop ${_i + 1}: ${(intermediateStops[_i] as Map?)?['address']?.toString() ?? ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontFamily: AppFont.fontFamily,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              Text(
                                dropAddress,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontFamily: AppFont.fontFamily,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1, color: Color(0xFFEEEEEE)),
                    const SizedBox(height: 16),

                    // Fare details section
                    const Text(
                      "fare details",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppFont.fontFamily,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Trip Fare", style: TextStyle(fontSize: 13, color: Colors.black87, fontFamily: AppFont.fontFamily)),
                        Text("₹ ${baseTripFare.toStringAsFixed(2)}", style: const TextStyle(fontSize: 13, color: Colors.black87, fontFamily: AppFont.fontFamily)),
                      ],
                    ),
                    if (isPriority) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Priority Pickup Fee", style: TextStyle(fontSize: 13, color: Colors.black87, fontFamily: AppFont.fontFamily)),
                          Row(
                            children: [
                              Text(
                                "₹ ${priorityFeeAmount.toStringAsFixed(2)}",
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
                                  "Not Charged",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: AppFont.fontFamily,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      if (!priorityCollected) ...[
                        const SizedBox(height: 4),
                        Text(
                          "Driver arrived after the priority window — this fee was never charged.",
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontFamily: AppFont.fontFamily),
                        ),
                      ],
                    ],
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("GST Charges (18%)", style: TextStyle(fontSize: 13, color: Colors.black87, fontFamily: AppFont.fontFamily)),
                        Row(
                          children: [
                            Text(
                              "₹ ${breakdown['gst']?.toStringAsFixed(2)}",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade500,
                                decoration: TextDecoration.lineThrough,
                                fontFamily: AppFont.fontFamily,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Free",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green.shade600,
                                fontWeight: FontWeight.bold,
                                fontFamily: AppFont.fontFamily,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Waiting Charges", style: TextStyle(fontSize: 13, color: Colors.black87, fontFamily: AppFont.fontFamily)),
                        Row(
                          children: [
                            Text(
                              "₹ 0.00",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade500,
                                decoration: TextDecoration.lineThrough,
                                fontFamily: AppFont.fontFamily,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Free",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green.shade600,
                                fontWeight: FontWeight.bold,
                                fontFamily: AppFont.fontFamily,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Total Order Fare", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black, fontFamily: AppFont.fontFamily)),
                        Text("₹ ${finalAmountToPay.toStringAsFixed(1)}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black, fontFamily: AppFont.fontFamily)),
                      ],
                    ),
                    if (booking['isPriorityPickup'] == true) ...[
                      const SizedBox(height: 12),
                      _priorityOutcomeBanner(booking),
                    ],
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: Color(0xFFEEEEEE)),
                    const SizedBox(height: 16),

                    // Payment details section
                    const Text(
                      "payment details",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppFont.fontFamily,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          booking['payment_type']?.toString().toUpperCase() == 'WALLET' ? 'Wallet' : 'Cash',
                          style: const TextStyle(fontSize: 13, color: Colors.black87, fontFamily: AppFont.fontFamily),
                        ),
                        Text(
                          "₹ ${breakdown['total']?.toStringAsFixed(1)}",
                          style: const TextStyle(fontSize: 13, color: Colors.black87, fontFamily: AppFont.fontFamily),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // Bottom Buttons
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _bookAgain(booking),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColor.themeColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Book Again",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFamily: AppFont.fontFamily),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
