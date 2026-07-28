import 'package:flutter/material.dart';
import 'package:movigo/Controller/get_booking_details_provider.dart';
import 'package:provider/provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/get_navigation.dart';
import 'package:movigo/helper/MapImage_screen.dart';
import 'package:movigo/helper/date_time_format/date_time_format.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_header.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/view/retailer_screen/retailer_account_screen/help_and_support_screen.dart';
import 'package:movigo/Controller/retailer_home_cotroller.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class RArrivedBookingDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? bookingData;
  const RArrivedBookingDetailScreen({super.key, this.bookingData});

  @override
  State<RArrivedBookingDetailScreen> createState() =>
      _RArrivedBookingDetailScreenState();
}

class _RArrivedBookingDetailScreenState
    extends State<RArrivedBookingDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final homeCtrl = Provider.of<RetailerHomeController>(context, listen: false);
      final booking = widget.bookingData ?? homeCtrl.ongoingBookings.firstWhere(
        (b) {
          final s = (b['booking_status'] ?? b['status'] ?? '').toString().toLowerCase();
          return s.contains('accept') || s.contains('arrive') || s.contains('pick') || s.contains('ongoing');
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

  Future<void> openDialPad(String phoneNumber) async {
    final Uri url = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      debugPrint("Can't open dial pad.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final userController = Provider.of<UserController>(context, listen: false);
    final String loggedInUserId = userController.getUserId;
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
    
    // Driver info
    final rawDriver = booking['driver'] ?? booking['driver_id'];
    final Map<String, dynamic>? driverObj = rawDriver is Map ? Map<String, dynamic>.from(rawDriver) : null;
    final String driverName = driverObj?['full_name']?.toString() ?? driverObj?['name']?.toString() ?? booking['name']?.toString() ?? 'Assigning driver...';
    final String driverProfileImage = driverObj?['profile_image']?.toString() ?? driverObj?['photo']?.toString() ?? booking['profile']?.toString() ?? '';
    final String driverPhone = driverObj?['phone_number']?.toString() ?? driverObj?['phone']?.toString() ?? booking['driver_phone']?.toString() ?? '';
    final String vehicleNumber = booking['vehicle_number']?.toString() ?? driverObj?['registration_number']?.toString() ?? driverObj?['vehicle_number']?.toString() ?? booking['registration_number']?.toString() ?? '';
    final String vehicleName = booking['requested_vehicle_name']?.toString() ?? driverObj?['vehicle_name']?.toString() ?? booking['vehicle_name']?.toString() ?? '';
    
    // Ride Details
    final String? _otpRaw = [
      booking['start_pin']?.toString().trim(),
      booking['otp']?.toString().trim(),
      userController.startPin.trim(),
    ].firstWhere((v) => v != null && v.isNotEmpty, orElse: () => '');
    final String otp = _otpRaw ?? '';
    final String pickupAddress = booking['pickup_location']?['address']?.toString() ?? booking['pickup']?.toString() ?? 'Pickup location not specified';
    final String dropAddress = booking['dropoff_location']?['address']?.toString() ?? booking['drop']?.toString() ?? 'Dropoff location not specified';
    // extra_drops includes the final drop as its last entry — only the earlier
    // entries are intermediate stops (dropAddress above already covers the last one).
    final List<dynamic> _allExtraDrops = booking['extra_drops'] is List ? booking['extra_drops'] as List : [];
    final List<dynamic> intermediateStops = _allExtraDrops.length > 1 ? _allExtraDrops.sublist(0, _allExtraDrops.length - 1) : [];
    final String fare = booking['booking_price'] != null ? '₹${booking['booking_price']}' : (booking['price']?.toString() ?? '');

    // Backend sends the standard Mongoose `createdAt` ISO timestamp — there is
    // no `created_at` field (snake_case) on the booking payload. Prefer the
    // full detail response, fall back to the list-item snapshot passed in
    // before the detail API overwrites it.
    final String _rawBookingDateTime = WalletDateTimeHelper.apiToFigmaDateTime(
      (booking['createdAt'] ?? widget.bookingData?['createdAt'])?.toString(),
    );
    final String bookingDateTime = _rawBookingDateTime == '-' ? '' : _rawBookingDateTime;

    // Parse lat/lng for map
    final double? pickupLat = double.tryParse(booking['pickup_location']?['latitude']?.toString() ?? '');
    final double? pickupLng = double.tryParse(booking['pickup_location']?['longitude']?.toString() ?? '');
    final double? dropLat = double.tryParse(booking['dropoff_location']?['latitude']?.toString() ?? '');
    final double? dropLng = double.tryParse(booking['dropoff_location']?['longitude']?.toString() ?? '');

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => CustomBottomNav(
              userType: UserType.retailer,
              initialIndex: 1,
            ),
          ),
          (route) => false,
        );
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              // 60% Map portion
              Container(
                height: size.height * 0.60,
                child: Stack(
                  children: [
                    MapImageScreen(
                      userId: loggedInUserId,
                      bookingId: bookingId,
                      driverId: driverObj?['_id']?.toString() ?? '',
                      vehicleName: vehicleName,
                      vehicleImage: driverObj?['profile_image']?.toString(),
                      pickupLat: pickupLat,
                      pickupLng: pickupLng,
                      dropLat: dropLat,
                      dropLng: dropLng,
                      bookingStatus: "Arrived",
                      isEmbed: true,
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      right: 10,
                      child: CommonAppBar(
                        title: AppLanguage.bookingdetailsText[language],
                        onBack: () {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CustomBottomNav(
                                userType: UserType.retailer,
                                initialIndex: 1,
                              ),
                            ),
                            (route) => false,
                          );
                        },
                        onMoreTap: () {
                          _showCancelPopup(context);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // 40% Scrollable Details card portion
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: size.width * 0.05,
                      vertical: size.height * 0.015,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Driver Info Row
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    driverName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: AppFont.fontFamily,
                                      color: AppColor.blackColor,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    "$vehicleName • $vehicleNumber",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                      fontFamily: AppFont.fontFamily,
                                    ),
                                  ),
                                  if (bookingCodeDisplay.isNotEmpty || bookingDateTime.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      [
                                        if (bookingCodeDisplay.isNotEmpty) '#$bookingCodeDisplay',
                                        if (bookingDateTime.isNotEmpty) bookingDateTime,
                                      ].join('  •  '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontFamily: AppFont.fontFamily),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => openDialPad(driverPhone),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.blue.shade100, width: 1),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.call, color: Colors.blue.shade700, size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      AppLanguage.callText[language],
                                      style: TextStyle(
                                        color: Colors.blue.shade700,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        fontFamily: AppFont.fontFamily,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // OTP Section (Only visible while driver has not started the ride)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Ride Start OTP:",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange.shade800,
                                  fontSize: 14,
                                  fontFamily: AppFont.fontFamily,
                                ),
                              ),
                              otp.isNotEmpty
                                  ? Text(
                                      otp,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: Colors.orange.shade900,
                                        letterSpacing: 2,
                                        fontFamily: AppFont.fontFamily,
                                      ),
                                    )
                                  : SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Route Details
                        Text(
                          AppLanguage.detailText[language],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            fontFamily: AppFont.fontFamily,
                            color: AppColor.blackColor,
                          ),
                        ),
                        const SizedBox(height: 10),
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
                                Container(
                                  width: 1.5,
                                  height: 35,
                                  color: Colors.grey.shade300,
                                ),
                                Image.asset(
                                  AppImage.redlocation,
                                  height: 16,
                                  width: 14,
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
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontFamily: AppFont.fontFamily,
                                      color: AppColor.blackColor,
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
                                  const SizedBox(height: 18),
                                  Text(
                                    dropAddress,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontFamily: AppFont.fontFamily,
                                      color: AppColor.blackColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Final Charge (Only Total Price, no details)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                AppLanguage.totalText[language],
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  fontFamily: AppFont.fontFamily,
                                  color: AppColor.thirdTextColor,
                                ),
                              ),
                              Text(
                                fare,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppColor.primaryColor,
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCancelPopup(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    double topPosition;
    if (size.height < 600) {
      topPosition = size.height * 0.08;
    } else if (size.height < 800) {
      topPosition = size.height * 0.14;
    } else {
      topPosition = size.height * 0.13;
    }

    showMenu(
      context: context,
      color: AppColor.secondaryColor,
      elevation: 1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          bottomLeft: Radius.circular(12),
          topRight: Radius.circular(0),
          bottomRight: Radius.circular(0),
        ),
      ),
      position: RelativeRect.fromLTRB(
        overlay.size.width - 120,
        topPosition,
        0,
        overlay.size.height,
      ),
      items: [
        PopupMenuItem(
          height: 44,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: size.width * 0.48,
            child: Center(
              child: Text(
                'Help & Support',
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
            Get.to(() => const RHelpAndSupportscreen());
          },
        ),
        PopupMenuItem(
          height: 44,
          padding: EdgeInsets.zero,
          enabled: false,
          child: SizedBox(
            width: size.width * 0.48,
            child: Center(
              child: Text(
                'Cannot cancel — driver arrived',
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: AppFont.fontFamily,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
