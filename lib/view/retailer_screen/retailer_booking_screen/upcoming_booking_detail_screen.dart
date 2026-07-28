import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:movigo/Controller/retailer_home_cotroller.dart';
import 'package:movigo/Controller/get_booking_details_provider.dart';
import 'package:provider/provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/get_navigation.dart';

import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_header.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/common_text_field.dart';
import 'package:movigo/view/retailer_screen/retailer_create_booking_screen/cancellation_policy_screen.dart';

class RUpcomingBookingDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? bookingData;
  const RUpcomingBookingDetailScreen({super.key, this.bookingData});

  @override
  State<RUpcomingBookingDetailScreen> createState() =>
      _RUpcomingBookingDetailScreenState();
}

class _RUpcomingBookingDetailScreenState
    extends State<RUpcomingBookingDetailScreen> {
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
          return s.contains('upcoming');
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final homeCtrl = Provider.of<RetailerHomeController>(context);

    final detailCtrl = Provider.of<BookingDetailController>(context);
    final apiBooking = detailCtrl.bookingDetail;

    final Map<String, dynamic> booking = {};
    
    // Base placeholders
    booking.addAll({
      "booking_code": "",
      "name": "",
      "profile": "",
      "pickup": "Pickup location not specified",
      "drop": "Dropoff location not specified",
      "price": "",
      "otp": "",
      "vehicle_name": "",
      "registration_number": "",
      "driver_phone": ""
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

    // Backend sends the standard Mongoose `createdAt` ISO timestamp — there is
    // no `created_at` field (snake_case) on the booking payload, so this
    // always rendered nothing.
    String _createdAtDate = '';
    String _createdAtTime = '';
    final String? _rawCreatedAt = booking['createdAt']?.toString();
    if (_rawCreatedAt != null && _rawCreatedAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(_rawCreatedAt).toLocal();
        const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        _createdAtDate = "${dt.day.toString().padLeft(2, '0')} ${_months[dt.month - 1]}, ${dt.year}";
        final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
        _createdAtTime = "${h.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}";
      } catch (_) {}
    }

    // Driver info
    final rawDriver = booking['driver'] ?? booking['driver_id'];
    final Map<String, dynamic>? driverObj = rawDriver is Map ? Map<String, dynamic>.from(rawDriver) : null;
    final String driverName = driverObj?['full_name']?.toString() ?? driverObj?['name']?.toString() ?? booking['name']?.toString() ?? 'Assigning driver...';
    final String driverProfileImage = driverObj?['profile_image']?.toString() ?? driverObj?['photo']?.toString() ?? booking['profile']?.toString() ?? '';
    final String driverPhone = driverObj?['phone_number']?.toString() ?? driverObj?['phone']?.toString() ?? booking['driver_phone']?.toString() ?? '';
    final String vehicleNumber = booking['vehicle_number']?.toString() ?? driverObj?['registration_number']?.toString() ?? driverObj?['vehicle_number']?.toString() ?? booking['registration_number']?.toString() ?? '';
    final String vehicleName = booking['requested_vehicle_name']?.toString() ?? driverObj?['vehicle_name']?.toString() ?? booking['vehicle_name']?.toString() ?? '';
    
    // Ride Details
    final String otp = booking['otp']?.toString() ?? booking['start_pin']?.toString() ?? '';
    final String pickupAddress = booking['pickup_location']?['address']?.toString() ?? booking['pickup']?.toString() ?? 'Pickup location not specified';
    final String dropAddress = booking['dropoff_location']?['address']?.toString() ?? booking['drop']?.toString() ?? 'Dropoff location not specified';
    // extra_drops includes the final drop as its last entry — only the earlier
    // entries are intermediate stops (dropAddress above already covers the last one).
    final List<dynamic> _allExtraDrops = booking['extra_drops'] is List ? booking['extra_drops'] as List : [];
    final List<dynamic> intermediateStops = _allExtraDrops.length > 1 ? _allExtraDrops.sublist(0, _allExtraDrops.length - 1) : [];
    final String fare = booking['booking_price'] != null ? '₹${booking['booking_price']}' : (booking['price']?.toString() ?? '');

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: AppColor.transparentColor,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      // appBar: CommonAppBar(
      //   title: AppLanguage.bookingdetailsText[language],
      //   onBack: () => Get.back(),
      // ),
      body: Container(
        width: size.width,
        height: size.height,
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: size.width * 0.05,
              vertical: size.height * 0.01,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CommonAppBar(
                  title: AppLanguage.bookingdetailsText[language],
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                SizedBox(height: size.height * 0.01),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLanguage.detailText[language],
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          fontFamily: AppFont.fontFamily,
                          color: AppColor.blackColor),
                    ),
                    Text(
                      AppLanguage.upcomingText[language],
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          fontFamily: AppFont.fontFamily,
                          color: AppColor.uploadColor),
                    ),
                  ],
                ),

                SizedBox(
                  height: size.height * 0.04,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (bookingCodeDisplay.isNotEmpty)
                      Text(
                        "#$bookingCodeDisplay",
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: AppFont.fontFamily,
                            color: AppColor.fourTextColor),
                      ),
                    if (_createdAtDate.isNotEmpty || _createdAtTime.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (_createdAtDate.isNotEmpty)
                            Text(
                              _createdAtDate,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: AppFont.fontFamily,
                                  color: AppColor.secondTextColor),
                            ),
                          if (_createdAtTime.isNotEmpty)
                            Text(
                              _createdAtTime,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: AppFont.fontFamily,
                                  color: AppColor.secondTextColor),
                            ),
                        ],
                      )
                  ],
                ),
                SizedBox(
                  height: size.height * 0.04,
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Image.asset(
                          AppImage.grlocaton,
                          height: 16,
                          width: 14,
                        ),
                        // SizedBox(
                        //   height: size.height * 0.01,
                        // ),
                        SizedBox(
                          height: size.height * 0.047,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(
                              6, // number of dots
                              (index) => Container(
                                width: 1.5,
                                height: 4,
                                color: const Color(0xffC9C9C9),
                              ),
                            ),
                          ),
                        ),
                        Image.asset(
                          AppImage.redlocation,
                          height: 16,
                          width: 14,
                        )
                      ],
                    ),
                    SizedBox(
                      width: size.width * 0.03,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pickupAddress,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              fontFamily: AppFont.fontFamily,
                              color: AppColor.selectTpeColor,
                            ),
                          ),
                          for (int _i = 0; _i < intermediateStops.length; _i++) ...[
                            SizedBox(height: size.height * 0.02),
                            Text(
                              'Stop ${_i + 1}: ${(intermediateStops[_i] as Map?)?['address']?.toString() ?? ''}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                fontFamily: AppFont.fontFamily,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ],
                          SizedBox(
                            height: size.height * 0.04,
                          ),
                          Text(
                            dropAddress,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              fontFamily: AppFont.fontFamily,
                              color: AppColor.selectTpeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  height: size.height * 0.04,
                ),

                /// DRIVER DETAILS
                Text(
                  AppLanguage.driverdText[language],
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppFont.fontFamily,
                    color: AppColor.blackColor,
                  ),
                ),

                SizedBox(height: size.height * 0.015),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// PROFILE IMAGE
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: _displayImage(driverProfileImage, AppImage.profiletwo),
                    ),

                    SizedBox(width: size.width * 0.03),

                    /// NAME + VEHICLE
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driverName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: AppFont.fontFamily,
                              color: AppColor.blackColor,
                            ),
                          ),
                          SizedBox(height: size.height * 0.005),
                          Row(
                            children: [
                              Image.asset(
                                AppImage.minitruck,
                                height: 35,
                                width: 35,
                              ),
                              SizedBox(width: size.width * 0.04),
                              Text(
                                vehicleName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: AppFont.fontFamily,
                                  color: AppColor.blackColor,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: size.height * 0.035),
                          Row(
                            children: [
                              /// CALL BUTTON
                              Container(
                                height: size.height * 5 / 100,
                                width: size.width * 30 / 100,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColor.primaryColor,
                                    width: 1,
                                  ),
                                ),
                                child: InkWell(
                                  onTap: () {
                                    // call action
                                  },
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Image.asset(
                                        AppImage.calltwo,
                                        height: 20,
                                        width: 20,
                                      ),
                                      SizedBox(width: size.width * 0.03),
                                      Text(
                                        AppLanguage.callText[language],
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: AppFont.fontFamily,
                                          color: AppColor.primaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              SizedBox(width: size.width * 0.04),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                SizedBox(height: size.height * 0.035),

                Text(
                  AppLanguage.customerDetailsText[language],
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.blackColor),
                ),
                SizedBox(height: size.height * 0.01),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          AppImage.profile,
                          height: size.height * 5 / 100,
                          width: size.width * 5 / 100,
                        ),
                        SizedBox(width: size.width * 0.030),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              booking['sender_name']?.toString() ?? booking['customer_name']?.toString() ?? AppLanguage.jacobJonesText[language],
                              style: const TextStyle(
                                color: AppColor.blackColor,
                                fontFamily: AppFont.fontFamily2,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: size.height * 0.005),
                            Row(
                              children: [
                                // SizedBox(width: size.width * 0.015),
                                Text(
                                  booking['sender_phone']?.toString() ?? booking['customer_phone']?.toString() ?? AppLanguage.jacobMobText[language],
                                  style: const TextStyle(
                                    color: AppColor.grey6EColor,
                                    fontFamily: AppFont.fontFamily,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),

                SizedBox(
                  height: size.height * 0.03,
                ),
                Text(
                  AppLanguage.helperText[language],
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.blackColor),
                ),

                SizedBox(
                  height: size.height * 0.01,
                ),

                Text(
                  AppLanguage.booktsText[language],
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.blackColor),
                ),
                SizedBox(
                  height: size.height * 0.01,
                ),

                Text(
                  AppLanguage.plsHanText[language],
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFamily: AppFont.fontFamily,
                      color: Color(0xff6E6E6E)),
                ),

                SizedBox(
                  height: size.height * 0.04,
                ),
                SizedBox(
                  height: size.height * 0.20,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: 2,
                    itemBuilder: (context, index) {
                      return Container(
                        width: size.width * 0.42,
                        margin: EdgeInsets.only(
                          right: size.width * 0.03,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.grey.shade200,
                          image: const DecorationImage(
                            image: AssetImage(AppImage.gift),
                            fit: BoxFit.cover,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  height: size.height * 0.03,
                ),
                Text(
                  AppLanguage.paidText[language],
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.successCOlor),
                ),
                SizedBox(
                  height: size.height * 0.04,
                ),

                Container(
                  width: size.width,
                  height: size.height * 0.08,
                  decoration: BoxDecoration(
                      color: AppColor.whiteColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Color(
                            0xffDEE2E6,
                          ),
                          width: 1)),
                  child: Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: size.width * 0.03),
                    child: Column(
                      children: [
                        SizedBox(
                          height: size.height * 0.025,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              AppLanguage.totalText[language],
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: AppFont.fontFamily,
                                  color: AppColor.thirdTextColor),
                            ),
                            Text(
                              fare.isNotEmpty ? fare : AppLanguage.totalPriceText[language],
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: AppFont.fontFamily,
                                  color: AppColor.thirdTextColor),
                            ),
                          ],
                        ),
                        SizedBox(
                          height: size.height * 0.015,
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(
                  height: size.height * 0.20,
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: GestureDetector(
        onTap: () {},
        child: Container(
          height: MediaQuery.of(context).size.height * 0.2,
          width: MediaQuery.of(context).size.width * 0.2,
          child: Center(
            child: Image.asset(
              AppImage.Call,
              height: 64,
              width: 64,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  void _showCancelPopup(BuildContext context, {required String bookingId}) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      color: Colors.white,
      elevation: 2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          bottomLeft: Radius.circular(12),
          topRight: Radius.circular(0),
          bottomRight: Radius.circular(0),
        ),
      ),
      position: RelativeRect.fromLTRB(
        overlay.size.width - 110, // popup width
        93, // top position
        0, // no right gap
        overlay.size.height,
      ),
      items: [
        PopupMenuItem(
          height: 42,
          padding: EdgeInsets.zero, // remove default padding
          child: SizedBox(
            width: 110,
            child: Center(
              child: Text(
                AppLanguage.cancelText[language],
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppFont.fontFamily,
                  color: AppColor.thirdTextColor,
                ),
              ),
            ),
          ),
          onTap: () {
            Get.to(() => RCancellationPolicyScreen(bookingId: bookingId));
          },
        ),
      ],
    );
  }
}
