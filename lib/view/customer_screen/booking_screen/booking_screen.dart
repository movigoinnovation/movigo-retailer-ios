import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:movigo/utilities/app_config_provider.dart';
import 'package:provider/provider.dart';
import 'package:movigo/Controller/accepted_booking_provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/helper/date_time_format/date_time_format.dart';
import 'package:movigo/helper/shimmer/get_booking_tab_shimmer.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/view/customer_screen/create_booking_screen/booking_detail_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movigo/view/customer_screen/new_booking_flow/retailer_confirm_screen.dart';
import 'package:movigo/view/customer_screen/new_booking_flow/route_vehicle_screen.dart';
import 'package:movigo/view/retailer_screen/retailer_booking_screen/delivered_booking_detail_screen.dart';
import 'package:movigo/view/retailer_screen/retailer_booking_screen/cancelled_booking_detail_screen.dart';
import 'package:movigo/view/retailer_screen/retailer_booking_screen/upcoming_booking_detail_screen.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  String userId = "";
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    final userController = Provider.of<UserController>(context, listen: false);
    userId = userController.getUserId;

    // CHANGE 1: single combined list — no per-status sub-tabs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller =
          Provider.of<AcceptedBookingController>(context, listen: false);
      controller.getBookings(context, bookingKey: 'all');
    });
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final controller =
          Provider.of<AcceptedBookingController>(context, listen: false);
      if (controller.hasMore && !controller.isLoadingMore) {
        controller.getBookings(context, bookingKey: 'all', isPagination: true);
      }
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {}); // reflect the clear-button visibility immediately
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      Provider.of<AcceptedBookingController>(context, listen: false)
          .getBookings(context, bookingKey: 'all', search: value);
    });
  }

  void _handleBack() {
    Get.offAll(() => const CustomBottomNav(
          userType: UserType.retailer,
          initialIndex: 1, // Booking tab
          bookingTabIndex: 0,
        ));
  }

  // ── CHANGE 2: terminal-status check — Book Again only shows here ──────────
  // Completed (Delivered), Cancelled, and Rejected (covers timed-out bookings
  // — the backend auto-cancel cron marks expired Pending bookings as
  // Cancelled, there is no separate "Timed-out" status).
  bool _isTerminalBookingStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'delivered' ||
        normalized == 'cancelled' ||
        normalized == 'rejected';
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }


  // Book Again: open RetailerConfirmScreen with everything from the old booking
  // pre-filled. The retailer can change the vehicle inline via "Change".
  void _bookAgain(Map item) {
    final Map pickupLoc = item['pickup_location'] is Map ? item['pickup_location'] : {};
    final Map dropLoc   = item['dropoff_location'] is Map ? item['dropoff_location'] : {};

    final double? pickupLat = _toDouble(pickupLoc['latitude']);
    final double? pickupLng = _toDouble(pickupLoc['longitude']);
    final double? dropLat   = _toDouble(dropLoc['latitude']);
    final double? dropLng   = _toDouble(dropLoc['longitude']);

    if (pickupLat == null || pickupLng == null || dropLat == null || dropLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location details missing for this booking.')),
      );
      return;
    }

    // Multi-drop bookings carry every stop (final drop included) in extra_drops.
    // Route those through the main vehicle-selection flow (RouteVehicleScreen
    // → NewConfirmScreen), pre-filled and skipped straight to the booking
    // phase, so stops/contacts aren't dropped and "Book Again" lands on the
    // same screen as a normal booking would.
    final List<dynamic> extraDrops = item['extra_drops'] is List ? item['extra_drops'] as List : [];
    if (extraDrops.length > 1) {
      final validDrops = <Map<String, dynamic>>[];
      for (final d in extraDrops) {
        if (d is! Map) continue;
        final lat = _toDouble(d['latitude']);
        final lng = _toDouble(d['longitude']);
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
              pickupContactName:   (item['sender_name']  ?? item['customer_name']  ?? '').toString(),
              pickupContactPhone:  (item['sender_phone'] ?? item['customer_phone'] ?? '').toString(),
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

    int wheelCount(String tag) {
      final t = tag.toLowerCase();
      if (t.contains('2w') || t.contains('scooter') || t.contains('bike')) return 2;
      if (t.contains('3w') || t.contains('loader'))  return 3;
      return 4;
    }

    String extractId(dynamic field) {
      if (field == null) return '';
      if (field is Map) return (field['_id'] ?? '').toString();
      return field.toString();
    }

    final String requiredTag = (item['required_tag'] ?? item['vehicle_category'] ?? '').toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RetailerConfirmScreen(
          vehicleTypeId:    extractId(item['vehicleType_id'] ?? item['vehicle_type_id']),
          subVehicleTypeId: extractId(item['subVehicleType_id'] ?? item['sub_vehicle_type_id']),
          vehicleData: {
            'name':               (item['requested_vehicle_name'] ?? item['display_vehicle_name'] ?? 'Vehicle').toString(),
            'wheelCount':         wheelCount(requiredTag),
            'vehicleCategory':    (item['vehicle_category'] ?? requiredTag).toString(),
            'pricingModifier':    '1.0',
            'vehicleKey':         (item['vehicle_key'] ?? '').toString(),
            'requiredTag':        requiredTag,
            'bookingFlow':        (item['booking_flow'] ?? 'retailer').toString(),
            'displayVehicleName': (item['display_vehicle_name'] ?? '').toString(),
          },
          pickupData: {
            'address': (pickupLoc['address'] ?? '').toString(),
            'lat': pickupLat,
            'lng': pickupLng,
          },
          dropData: {
            'address': (dropLoc['address'] ?? '').toString(),
            'lat': dropLat,
            'lng': dropLng,
          },
          rawDistanceKm:  _toDouble(item['distance_in_km'] ?? item['rounded_distance_km'] ?? item['actual_distance_km']) ?? 0.0,
          estimatedFare:  int.tryParse((item['booking_price'] ?? '0').toString()) ?? 0,
          subVehicleTypeList: const [],
          initialReceiverName:  (item['receiver_name']  ?? '').toString(),
          initialReceiverPhone: (item['receiver_phone'] ?? '').toString(),
          initialSenderName:    (item['sender_name']  ?? item['customer_name']  ?? '').toString(),
          initialSenderPhone:   (item['sender_phone'] ?? item['customer_phone'] ?? '').toString(),
          initialNote:          (item['note'] ?? '').toString(),
          initialGoodsTypeId:   extractId(item['item_category_id']),
          initialIsPriorityPickup: item['isPriorityPickup'] == true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return PopScope(
      canPop: false, // we handle pop manually
      onPopInvoked: (didPop) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(height: size.height * 0.02),
              Text(
                AppLanguage.bookingsText[language],
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppFont.fontFamily,
                  color: AppColor.blackColor,
                ),
              ),
              SizedBox(height: size.height * 0.015),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.04),
                child: TextField(
                  controller: _searchController,
                  keyboardType: TextInputType.phone,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(
                    fontFamily: AppFont.fontFamily,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search by contact number',
                    hintStyle: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    filled: true,
                    fillColor: const Color(0xffF7F9FC),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColor.themeColor),
                    ),
                  ),
                ),
              ),
              SizedBox(height: size.height * 0.015),
              Expanded(
                child: Consumer<AcceptedBookingController>(
                  builder: (_, controller, __) {
                    final List list = controller.bookingList;

                    // Shimmer
                    if (controller.isLoading) {
                      return const BookingShimmer();
                    }

                    // empty state
                    if (list.isEmpty) {
                      return Center(
                        child: Text(
                          AppLanguage.noBookingsYetText[language],
                          style: const TextStyle(
                            fontSize: 16,
                            fontFamily: AppFont.fontFamily,
                            color: AppColor.greyColor,
                          ),
                        ),
                      );
                    }

                    return _bookingList(
                      list: list,
                      isLoadingMore: controller.isLoadingMore,
                      onTap: (item) => Get.to(() => BookingDetailScreen(
                            bookingId: item['_id'],
                          )),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bookingList({
    required List list,
    required Function(Map item) onTap,
    bool isLoadingMore = false,
  }) {
    return RefreshIndicator(
      onRefresh: () async {
        final controller =
            Provider.of<AcceptedBookingController>(context, listen: false);
        await controller.getBookings(
          context,
          bookingKey: controller.currentBookingKey,
        );
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: list.length + (isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= list.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            );
          }
          final item = list[index];
          final String status =
              (item['booking_status'] ?? '').toString();
          final String statusLower = status.toLowerCase();
          final bool isTerminal = _isTerminalBookingStatus(status);

          return InkWell(
            onTap: () {
              /// 🚫 Do not navigate if booking is pending
              if (statusLower == "pending") {
                return;
              }

              final userController = Provider.of<UserController>(context, listen: false);
              final bool isRetailer = userController.getUserType.toLowerCase() == 'retailer';

              if (isRetailer) {
                final Map<String, dynamic> mappedItem = Map<String, dynamic>.from(item);
                mappedItem['status'] = status;

                final String statusTrimmed = status.trim().toLowerCase();
                if (statusTrimmed == 'accepted' ||
                    statusTrimmed == 'arrived' ||
                    statusTrimmed == 'arrivedatpickup' ||
                    statusTrimmed == 'picked up' ||
                    statusTrimmed == 'pickedup' ||
                    statusTrimmed == 'ongoing' ||
                    statusTrimmed == 'ontheway') {
                  Get.to(() => BookingDetailScreen(
                        bookingId: mappedItem['_id']?.toString() ?? '',
                      ));
                } else if (statusTrimmed == 'delivered') {
                  Get.to(() => RDeliveredBookingDetailScreen(bookingData: mappedItem));
                } else if (statusTrimmed == 'cancelled' || statusTrimmed == 'rejected') {
                  Get.to(() => RCancelledBookingDetailScreen(bookingData: mappedItem));
                } else if (statusTrimmed == 'upcoming') {
                  Get.to(() => RUpcomingBookingDetailScreen(bookingData: mappedItem));
                } else {
                  onTap(item);
                }
              } else {
                onTap(item);
              }
            },
            child: _bookingCard(
              item: item,
              onBookAgain: isTerminal ? () => _bookAgain(item) : null,
            ),
          );
        },
      ),
    );
  }

  Color _statusColor(String status) {
    String normalizedStatus = status.trim().toLowerCase();

    switch (normalizedStatus) {
      case 'accepted':
        return AppColor.uploadColor;

      case 'arrived':
      case 'arrivedatpickup':
        return AppColor.orangeColor;

      case 'picked up':
      case 'pickedup':
      case 'ontheway':
        return AppColor.successCOlor;

      case 'pending':
        return Colors.orange;

      case 'upcoming':
        return AppColor.uploadColor;

      case 'cancelled':
      case 'rejected':
        return AppColor.redAppColor;

      case 'delivered':
        return AppColor.successCOlor;

      default:
        return AppColor.greyColor;
    }
  }

  Widget _bookingCard({
    required Map item,
    VoidCallback? onBookAgain,
  }) {
    final String status = (item['booking_status'] ?? '').toString();
    final Color statusColor = _statusColor(status);
    // Backend sends the standard Mongoose `createdAt` ISO timestamp — there is
    // no `created_at: {date, time}` object on the booking payload.
    final String date = WalletDateTimeHelper.apiToFigmaDateTime(item['createdAt']?.toString());
    final String price = "₹${item['booking_price'] ?? '0'}";
    
    final String vehicleName = item['requested_vehicle_name']?.toString() ??
        item['display_vehicle_name']?.toString() ?? 'Vehicle';
        
    final String senderName = item['sender_name']?.toString() ?? item['customer_name']?.toString() ?? 'Sender';
    final String senderPhone = item['sender_phone']?.toString() ?? item['customer_phone']?.toString() ?? '';
    final String pickup = item['pickup_location']?['address']?.toString() ?? '';

    final String receiverName = item['receiver_name']?.toString() ?? 'Receiver';
    final String receiverPhone = item['receiver_phone']?.toString() ?? '';
    final String drop = item['dropoff_location']?['address']?.toString() ?? '';

    final String senderText = senderPhone.isNotEmpty ? "$senderName • $senderPhone" : senderName;
    final String receiverText = receiverPhone.isNotEmpty ? "$receiverName • $receiverPhone" : receiverName;

    final bool isMultidrop = item['is_multidrop'] == true || item['is_multidrop']?.toString() == 'true';
    final int extraDropsCount = () {
      final raw = item['extra_drops'];
      if (raw is List) return raw.length;
      return 0;
    }();

    String statusDisplay = status.toUpperCase();
    if (status.trim().toLowerCase() == 'pending') {
      statusDisplay = 'PENDING';
    } else if (status.trim().toLowerCase() == 'delivered') {
      statusDisplay = 'COMPLETED';
    } else if (status.trim().toLowerCase() == 'cancelled' || status.trim().toLowerCase() == 'rejected') {
      statusDisplay = 'CANCELLED';
    } else if (status.trim().toLowerCase() == 'arrived' || status.trim().toLowerCase() == 'arrivedatpickup') {
      statusDisplay = 'ARRIVED';
    } else if (status.trim().toLowerCase() == 'picked up' || status.trim().toLowerCase() == 'pickedup' || status.trim().toLowerCase() == 'ontheway') {
      statusDisplay = 'ONGOING';
    }

    final String vehicleNameLower = vehicleName.toLowerCase();
    String vehicleImgPath = AppImage.minitruck; // fallback

    if (vehicleNameLower.contains('e-loader') || 
        vehicleNameLower.contains('eloader') || 
        vehicleNameLower.contains('loader') || 
        vehicleNameLower.contains('3 wheeler') || 
        vehicleNameLower.contains('3w') || 
        vehicleNameLower.contains('auto')) {
      vehicleImgPath = AppImage.eloader;
    } else if (vehicleNameLower.contains('bike') || 
               vehicleNameLower.contains('2 wheeler') || 
               vehicleNameLower.contains('2w') || 
               vehicleNameLower.contains('scooter') || 
               vehicleNameLower.contains('two wheel')) {
      vehicleImgPath = AppImage.twowheel;
    } else if (vehicleNameLower.contains('large') || 
               vehicleNameLower.contains('heavy')) {
      vehicleImgPath = AppImage.largetruck;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Vehicle icon, vehicle type name, date/time, price and arrow
          Row(
            children: [
              Image.asset(
                vehicleImgPath,
                height: 40,
                width: 40,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicleName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: AppFont.fontFamily,
                        color: AppColor.blackColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      date,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontFamily: AppFont.fontFamily,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Text(
                    price,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.blackColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (isMultidrop) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.35)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.route_rounded, color: Color(0xFF6C63FF), size: 12),
                const SizedBox(width: 4),
                Text(
                  extraDropsCount > 0
                      ? 'MULTI-STOP  •  $extraDropsCount drops'
                      : 'MULTI-STOP',
                  style: const TextStyle(
                    fontFamily: AppFont.fontFamily, fontSize: 10,
                    fontWeight: FontWeight.w800, color: Color(0xFF6C63FF),
                    letterSpacing: 0.4,
                  ),
                ),
              ]),
            ),
          ],

          // Route Details Grey Container
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    const Icon(Icons.arrow_upward, color: Colors.green, size: 16),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.grey.shade300,
                    ),
                    const Icon(Icons.arrow_downward, color: Colors.red, size: 16),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        senderText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                          fontFamily: AppFont.fontFamily,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pickup,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontFamily: AppFont.fontFamily,
                        ),
                      ),
                      // Intermediate stops — extra_drops includes the final drop as
                      // its last entry (already shown below via receiverText/drop),
                      // so only the earlier entries are listed here.
                      if (isMultidrop && extraDropsCount > 1)
                        for (final stop in (item['extra_drops'] as List).sublist(0, extraDropsCount - 1)) ...[
                          const SizedBox(height: 8),
                          Row(children: [
                            const Icon(Icons.fiber_manual_record, size: 8, color: Color(0xFF6C63FF)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                (stop as Map?)?['address']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: AppFont.fontFamily),
                              ),
                            ),
                          ]),
                        ],
                      const SizedBox(height: 14),
                      Text(
                        receiverText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                          fontFamily: AppFont.fontFamily,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        drop,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontFamily: AppFont.fontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Bottom Row: Status Chip + "Book Again" Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusDisplay,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                    fontFamily: AppFont.fontFamily,
                  ),
                ),
              ),
              if (onBookAgain != null)
                GestureDetector(
                  onTap: onBookAgain,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade600,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      "Book Again",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: AppFont.fontFamily,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
