import 'package:movigo/view/customer_screen/create_booking_screen/booking_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:movigo/Controller/accepted_booking_provider.dart';
import 'package:movigo/helper/shimmer/get_booking_tab_shimmer.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_config_provider.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/helper/date_time_format/date_time_format.dart';
import 'accept_booking_detail_screen.dart';
import 'arrived_booking_detail_screen.dart';
import 'cancelled_booking_detail_screen.dart';
import 'delivered_booking_detail_screen.dart';
import 'pickup_booking_detail_screen.dart';
import 'upcoming_booking_detail_screen.dart';

class RBookingScreen extends StatefulWidget {
  final int initialTabIndex;
  const RBookingScreen({super.key, this.initialTabIndex = 0});

  @override
  State<RBookingScreen> createState() => _RBookingScreenState();
}

class _RBookingScreenState extends State<RBookingScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AcceptedBookingController>(context, listen: false)
          .getBookings(context, bookingKey: 'all');
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
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
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CustomBottomNav(
              userType: UserType.retailer,
              initialIndex: 0,
            ),
          ),
        );
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
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
              SizedBox(height: size.height * 0.02),
              Expanded(
                child: Consumer<AcceptedBookingController>(
                  builder: (_, controller, __) {
                    if (controller.isLoading) return const BookingShimmer();

                    final list = controller.bookingList;

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

                    return RefreshIndicator(
                      onRefresh: () async {
                        await Provider.of<AcceptedBookingController>(
                                context, listen: false)
                            .getBookings(context, bookingKey: 'all');
                      },
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.symmetric(
                            horizontal: size.width * 0.04),
                        itemCount: list.length + (controller.isLoadingMore ? 1 : 0),
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
                          final item =
                              Map<String, dynamic>.from(list[index]);
                          return InkWell(
                            onTap: () => _handleBookingTap(item),
                            child: _bookingCard(item: item),
                          );
                        },
                      ),
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

  void _handleBookingTap(Map<String, dynamic> item) {
    final String status =
        (item['booking_status'] ?? item['status'] ?? '').toString().trim().toLowerCase();
    if (status == 'accepted' ||
        status == 'arrived' ||
        status == 'arrivedatpickup' ||
        status == 'picked up' ||
        status == 'pickedup' ||
        status == 'ongoing' ||
        status == 'ontheway') {
      Get.to(() => BookingDetailScreen(
            bookingId: item['_id']?.toString() ?? '',
          ));
    } else if (status == 'delivered' || status == 'completed') {
      Get.to(() => RDeliveredBookingDetailScreen(bookingData: item));
    } else if (status == 'upcoming' || status == 'pending') {
      Get.to(() => RUpcomingBookingDetailScreen(bookingData: item));
    } else if (status == 'cancelled' || status == 'rejected') {
      Get.to(() => RCancelledBookingDetailScreen(bookingData: item));
    }
  }

  Widget _buildProfileAvatar(String? imageUrl) {
    final String url = (imageUrl != null && imageUrl.isNotEmpty)
        ? "${AppConfigProvider.imgUrl}$imageUrl"
        : '';
    return CircleAvatar(
      radius: 22,
      backgroundColor: Colors.grey.shade200,
      child: url.isNotEmpty
          ? ClipOval(
              child: Image.network(
                url,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                cacheWidth: 100,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.person, size: 22, color: Colors.grey.shade500),
              ),
            )
          : Icon(Icons.person, size: 22, color: Colors.grey.shade500),
    );
  }

  Widget _bookingCard({required Map<String, dynamic> item}) {
    final String status =
        item['booking_status']?.toString() ?? item['status']?.toString() ?? '';
    final String bookingCode = item['booking_code']?.toString() ?? '';

    // Backend sends the standard Mongoose `createdAt` ISO timestamp — there is
    // no `created_at: {date, time}` object on the booking payload, and
    // `pickup_date` is a date-only Mongoose Date (always midnight), so
    // displaying it raw leaked "T00:00:00" into the UI.
    final String date = WalletDateTimeHelper.apiToFigmaDateTime(item['createdAt']?.toString());

    final String price = item['booking_price'] != null
        ? '₹${item['booking_price']}'
        : (item['price']?.toString() ?? '₹0');

    final String vehicleName = item['requested_vehicle_name']?.toString() ??
        item['display_vehicle_name']?.toString() ??
        item['vehicle_name']?.toString() ??
        'Vehicle';

    final String senderName = item['sender_name']?.toString() ?? 'Sender';
    final String senderPhone = item['sender_phone']?.toString() ?? '';
    final String pickup = item['pickup_location']?['address']?.toString() ??
        item['pickup']?.toString() ?? '';

    final String receiverName = item['receiver_name']?.toString() ?? 'Receiver';
    final String receiverPhone = item['receiver_phone']?.toString() ?? '';
    final String drop = item['dropoff_location']?['address']?.toString() ??
        item['drop']?.toString() ?? '';

    // extra_drops includes the final drop as its last entry — only the earlier
    // entries are intermediate stops (drop above already covers the last one).
    final List<dynamic> _allExtraDrops = item['extra_drops'] is List ? item['extra_drops'] as List : [];
    final List<dynamic> intermediateStops = _allExtraDrops.length > 1 ? _allExtraDrops.sublist(0, _allExtraDrops.length - 1) : [];

    final String senderText =
        senderPhone.isNotEmpty ? "$senderName • $senderPhone" : senderName;
    final String receiverText =
        receiverPhone.isNotEmpty ? "$receiverName • $receiverPhone" : receiverName;

    final String driverPhoto = (item['driver'] is Map)
        ? (item['driver']?['profile_image']?.toString() ?? '')
        : '';

    Color statusColor = Colors.blue;
    String statusDisplay = status.toUpperCase();

    final String statusLower = status.toLowerCase();
    if (statusLower.contains('deliver') || statusLower.contains('complet')) {
      statusColor = AppColor.successCOlor;
      statusDisplay = 'COMPLETED';
    } else if (statusLower.contains('cancel') || statusLower == 'rejected') {
      statusColor = AppColor.redAppColor;
      statusDisplay = 'CANCELLED';
    } else if (statusLower.contains('accept')) {
      statusColor = Colors.blue;
      statusDisplay = 'ACCEPTED';
    } else if (statusLower.contains('arrive')) {
      statusColor = AppColor.orangeColor;
      statusDisplay = 'ARRIVED';
    } else if (statusLower.contains('ongoing') ||
        statusLower.contains('pick') ||
        statusLower == 'ontheway') {
      statusColor = Colors.purple;
      statusDisplay = 'ONGOING';
    } else if (statusLower == 'pending' || statusLower == 'upcoming') {
      statusColor = AppColor.uploadColor;
      statusDisplay = 'UPCOMING';
    }

    final String vehicleNameLower = vehicleName.toLowerCase();
    String vehicleImgPath = AppImage.minitruck;

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
          Row(
            children: [
              _buildProfileAvatar(driverPhoto),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicleName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        fontFamily: AppFont.fontFamily,
                        color: AppColor.blackColor,
                      ),
                    ),
                    if (bookingCode.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '#$bookingCode',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColor.primaryColor,
                          fontFamily: AppFont.fontFamily,
                        ),
                      ),
                    ],
                    if (date.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        date,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontFamily: AppFont.fontFamily,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                children: [
                  Text(
                    price,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.blackColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

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
                    Container(width: 1, height: 40, color: Colors.grey.shade300),
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
                          fontSize: 13,
                          color: Colors.grey,
                          fontFamily: AppFont.fontFamily,
                        ),
                      ),
                      for (final stop in intermediateStops) ...[
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
            ],
          ),
        ],
      ),
    );
  }
}
