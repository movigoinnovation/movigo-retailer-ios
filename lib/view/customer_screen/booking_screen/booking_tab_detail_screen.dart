import 'package:cached_network_image/cached_network_image.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/get_navigation.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:movigo/view/customer_screen/booking_screen/track_driver_screen.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:movigo/Controller/get_booking_details_provider.dart';
import 'package:movigo/helper/date_time_format/date_time_format.dart';
import 'package:movigo/Provider/socket_connection/socket_provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/helper/MapImage_screen.dart';
import 'package:movigo/helper/Media_Image_viewer/media_viewer_helper.dart';
import 'package:movigo/helper/shimmer/getbookingdetails_shimmer.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_config_provider.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_header.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/view/customer_screen/create_booking_screen/bookingHelpAndSupport.dart';
import 'package:movigo/view/customer_screen/create_booking_screen/cancellation_policy_screen.dart';
import 'chat_screen.dart';
import 'invoice_download.dart';

class BookingTabDetailScreen extends StatefulWidget {
  final String? bookingId;
  final String? bookingStatus;

  const BookingTabDetailScreen({
    super.key,
    required this.bookingId,
    required this.bookingStatus,
  });

  @override
  State<BookingTabDetailScreen> createState() => _BookingTabDetailScreenState();
}

class _BookingTabDetailScreenState extends State<BookingTabDetailScreen> {
  final GlobalKey _invoiceKey = GlobalKey();
  String? supportNumber;
  String userId = '';

  @override
  void initState() {
    super.initState();

    final userController = Provider.of<UserController>(context, listen: false);
    userId = userController.getUserId;

    debugPrint("🆔 Booking ID : ${widget.bookingId}");
    debugPrint("📌 Booking Status : ${widget.bookingStatus}");

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<BookingDetailController>(
        context,
        listen: false,
      ).getBookingDetail(
        context,
        bookingId: widget.bookingId!,
      );
    });
  }

  String _getStatusText(String? status) {
    switch (status) {
      case 'Accepted':
        return 'Accepted';
      case 'OnTheWay':
        return 'On The Way';
      case 'Arrived':
      case 'ArrivedAtPickup':
        return 'Arrived';
      case 'PickedUp':
      case 'Picked Up':
        return 'Upcoming';
      case 'Delivered':
      case 'Completed':
        return 'Completed';
      case 'Cancelled':
        return 'Cancelled';
      default:
        return status ?? '';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'Accepted':
        return AppColor.uploadColor;
      case 'OnTheWay':
        return AppColor.themeColor;
      case 'Arrived':
      case 'ArrivedAtPickup':
        return AppColor.yellowColor;
      case 'Upcoming':
      case 'PickedUp':
      case 'Picked Up':
        return AppColor.uploadColor;
      case 'Delivered':
      case 'Completed':
        return AppColor.greenColor;
      case 'Cancelled':
        return AppColor.redAppColor;
      default:
        return AppColor.greyColor;
    }
  }

  Future<void> openDialPad(String phoneNumber) async {
    final Uri uri = Uri.parse("tel:$phoneNumber");

    debugPrint("Dialing URI => $uri");

    try {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint("Dial pad error: $e");
    }
  }

  void _handleBack() {
    Get.offAll(() => const CustomBottomNav(
          userType: UserType.retailer,
          initialIndex: 1, // Booking tab
          bookingTabIndex: 0,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // SystemChrome.setSystemUIOverlayStyle(
    //   const SystemUiOverlayStyle(
    //     statusBarColor: Colors.transparent,
    //     statusBarIconBrightness: Brightness.dark,
    //   ),
    // );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: PopScope(
        canPop: false, // we handle pop manually
        onPopInvoked: (didPop) {
          if (didPop) return;
          _handleBack();
        },
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Consumer<BookingDetailController>(
            builder: (context, controller, _) {
              // 🔄 SHIMMER
              if (controller.isLoading) {
                return const BookingDetailShimmer();
              }

              final data = controller.bookingDetail;

              final pickup = data?['pickup_location'];
              final drop = data?['dropoff_location'];
              final driver = data?['driver'];
              supportNumber = data?['supportNumber'];

              final vehicle = data?['vehicle_type'];
              final subVehicle = data?['sub_vehicle_type'];
              final paymentmode = data?['payment_mode'];
              final price = data?['price_breakup'];
              final images = data?['item_images'] as List? ?? [];

              bool showTrackButton = widget.bookingStatus == 'OnTheWay' ||
                  widget.bookingStatus == 'Arrived' ||
                  widget.bookingStatus == 'ArrivedAtPickup' ||
                  widget.bookingStatus == 'PickedUp' ||
                  widget.bookingStatus == 'Picked Up';

              if (data == null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          controller.errorMessage ?? 'No booking data found',
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
                              : () => Provider.of<BookingDetailController>(
                                    context,
                                    listen: false,
                                  ).getBookingDetail(
                                    context,
                                    bookingId: widget.bookingId!,
                                  ),
                          child: Text(
                            controller.isReassigned ? 'Go back' : 'Retry',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Container(
                width: size.width,
                height: size.height,
                child: RepaintBoundary(
                  key: _invoiceKey,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: size.width * 0.05,
                        vertical: size.height * 0.005,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CommonAppBar(
                            title: AppLanguage.bookingdText[language],
                            onBack: () => Navigator.of(context).maybePop(),
                            onMoreTap: (widget.bookingStatus != 'Completed' &&
                                    widget.bookingStatus != 'Delivered' &&
                                    widget.bookingStatus != 'Cancelled' &&
                                    widget.bookingStatus != 'PickedUp' &&
                                    widget.bookingStatus != 'Picked Up' &&
                                    widget.bookingStatus != 'Ongoing')
                                ? () {
                                    _showCancelPopup(
                                      context,
                                      bookingCode:
                                          data['booking_code'].toString(),
                                      bookingStatus:
                                          data['booking_status']?.toString(),
                                    );
                                  }
                                : null,
                          ),
                          SizedBox(height: size.height * 0.01),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                AppLanguage.detailText[language],
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: AppFont.fontFamily,
                                    color: AppColor.blackColor),
                              ),
                              Text(
                                _getStatusText(widget.bookingStatus),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: AppFont.fontFamily,
                                  color: _getStatusColor(widget.bookingStatus),
                                ),
                              ),
                            ],
                          ),

                          SizedBox(
                            height: size.height * 0.04,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Booking ID #${data['booking_code']}",
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: AppFont.fontFamily,
                                    color: AppColor.fourTextColor),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    BookingDateTimeHelper.isoDateToUi(data['pickup_date']?.toString()),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: AppFont.fontFamily,
                                        color: AppColor.secondTextColor),
                                  ),
                                  Text(
                                    data['pickup_slot'] ?? '',
                                    style: const TextStyle(
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
                                  SizedBox(
                                    height: size.height * 0.04,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
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
                                      pickup?['address'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: AppColor.selectTpeColor,
                                      ),
                                    ),
                                    SizedBox(height: size.height * 0.03),
                                    Text(
                                      drop?['address'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
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
                            style: const TextStyle(
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
                                child: driver?['profile_image'] != null &&
                                        driver!['profile_image']
                                            .toString()
                                            .isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl:
                                            "${AppConfigProvider.imgUrl}${driver['profile_image']}",
                                        height: 48,
                                        width: 48,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => Center(
                                          child: LoadingAnimationWidget
                                              .staggeredDotsWave(
                                            color: AppColor.themeColor,
                                            size: 15,
                                          ),
                                        ),
                                        errorWidget: (_, __, ___) =>
                                            Image.asset(AppImage.dummyimage,
                                                fit: BoxFit.cover),
                                      )
                                    : Image.asset(
                                        AppImage.dummyimage,
                                        height: 48,
                                        width: 48,
                                        fit: BoxFit.cover,
                                      ),
                              ),

                              SizedBox(width: size.width * 0.03),

                              /// NAME + VEHICLE
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      driver?['name'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: AppFont.fontFamily,
                                        color: AppColor.blackColor,
                                      ),
                                    ),
                                    SizedBox(height: size.height * 0.005),
                                    Row(
                                      children: [
                                        Container(
                                          height: size.width * 0.12,
                                          width: size.width * 0.12,
                                          child: Image.network(
                                            "${AppConfigProvider.imgUrl}"
                                            "${subVehicle?['image'] ?? vehicle?['image']}",
                                            fit: BoxFit.cover,
                                            cacheWidth: 100,
                                            errorBuilder: (_, __, ___) {
                                              return Image.asset(
                                                  AppImage.dummyimage);
                                            },
                                          ),
                                        ),
                                        SizedBox(width: size.width * 0.03),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              subVehicle?['name'] ??
                                                  vehicle?['name'] ??
                                                  '',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                fontFamily: AppFont.fontFamily,
                                                color: AppColor.blackColor,
                                              ),
                                            ),
                                            if (subVehicle != null)
                                              Text(
                                                vehicle?['name'] ?? '',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  fontFamily:
                                                      AppFont.fontFamily,
                                                  color:
                                                      AppColor.secondTextColor,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: size.height * 0.035),
                                    Row(
                                      children: [
                                        Container(
                                          height: size.height * 0.055,
                                          width: size.width * 0.32,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                              color: AppColor.themeColor,
                                              width: 1,
                                            ),
                                          ),
                                          child: InkWell(
                                            onTap: () {
                                              if (driver != null &&
                                                  driver['phone'] != null &&
                                                  driver['phone'] != '') {
                                                openDialPad(driver['phone']);
                                              }
                                            },
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Image.asset(
                                                  AppImage.calltwo,
                                                  height: 20,
                                                  width: 20,
                                                ),
                                                SizedBox(
                                                    width: size.width * 0.02),
                                                Text(
                                                  AppLanguage
                                                      .callText[language],
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    fontFamily:
                                                        AppFont.fontFamily,
                                                    color: AppColor.themeColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: size.width * 0.03),
                                        if (widget.bookingStatus != 'Upcoming'
                                            // &&    widget.bookingStatus !=
                                            //         'Delivered'

                                            ) ...[
                                          Container(
                                            height: size.height * 0.055,
                                            width: size.width * 0.32,
                                            decoration: BoxDecoration(
                                              color: AppColor.successCOlor,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: InkWell(
                                              onTap: () {
                                                // 1) Logged-in user id (Customer)
                                                final socketProvider =
                                                    Provider.of<SocketProvider>(
                                                        context,
                                                        listen: false);
                                                final currentUserId = userId;

                                                // 2) Driver id from booking detail API
                                                final driverId = driver?['_id']
                                                        ?.toString() ??
                                                    '';

                                                // 3) Booking id from this screen
                                                final bookingId =
                                                    widget.bookingId ?? '';

                                                debugPrint(
                                                    "🧪 bookingId = $bookingId");
                                                debugPrint(
                                                    "🧪 currentUserId = $currentUserId");
                                                debugPrint(
                                                    "🧪 driverId = $driverId");

                                                debugPrint(
                                                    "➡️ Opening ChatScreen with correct params");

                                                Get.to(() => ChatScreen(
                                                      bookingId: bookingId,
                                                      userId: currentUserId,
                                                      otherUserId: driverId,
                                                      userName: driver?['name']
                                                          ?.toString(), // 👈 DRIVER NAME
                                                      bookingCode: data[
                                                              'booking_code']
                                                          ?.toString(), // 👈 BOOKING CODE
                                                    ));
                                              },
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Image.asset(
                                                    AppImage.message,
                                                    height: 20,
                                                    width: 20,
                                                  ),
                                                  SizedBox(
                                                      width: size.width * 0.02),
                                                  Text(
                                                    AppLanguage
                                                        .messageText[language],
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontFamily:
                                                          AppFont.fontFamily,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          /// CALL & MESSAGE BUTTONS

                          SizedBox(height: size.height * 0.035),

                          if (data['need_helper'] == true) ...[
                            const Text(
                              "Helper Included",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                fontFamily: AppFont.fontFamily,
                                color: AppColor.blackColor,
                              ),
                            ),
                            SizedBox(height: size.height * 0.01),
                            const Text(
                              "20kg per helper",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                fontFamily: AppFont.fontFamily,
                                color: AppColor.greyColor,
                              ),
                            ),
                            SizedBox(
                              height: size.height * 0.01,
                            ),
                          ],

                          SizedBox(
                            height: size.height * 0.01,
                          ),

                          Text(
                            data['item_category'] ?? '',
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                fontFamily: AppFont.fontFamily,
                                color: AppColor.blackColor),
                          ),

                          SizedBox(
                            height: size.height * 0.01,
                          ),

                          if ((data['note'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty) ...[
                            Text(
                              data['note'] ?? '',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: AppFont.fontFamily,
                                  color: Color(0xff6E6E6E)),
                            ),
                            SizedBox(height: size.height * 0.04),
                          ],

                          if (images.isNotEmpty) ...[
                            SizedBox(
                              height: size.height * 0.16,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: images.length,
                                itemBuilder: (context, index) {
                                  return Container(
                                    width: size.width * 0.42,
                                    margin: EdgeInsets.only(
                                        right: size.width * 0.03),
                                    child: InkWell(
                                      onTap: () {
                                        MediaViewerHelper.openImage(
                                          context: context,
                                          imageName: images[index],
                                        );
                                      },
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: CachedNetworkImage(
                                          imageUrl:
                                              "${AppConfigProvider.imgUrl}${images[index]}",
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) => Center(
                                            child: LoadingAnimationWidget
                                                .staggeredDotsWave(
                                              color: AppColor.themeColor,
                                              size: 25,
                                            ),
                                          ),
                                          errorWidget: (_, __, ___) =>
                                              Image.asset(AppImage.gift,
                                                  fit: BoxFit.cover),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            SizedBox(height: size.height * 0.04),
                          ],

                          // SizedBox(
                          //   height: size.height * 0.03,
                          // ),
                          if (widget.bookingStatus == 'Accepted')
                            Column(
                              children: [
                                Text(
                                  data['payment_mode'] ?? '',
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: AppFont.fontFamily,
                                      color: AppColor.successCOlor),
                                ),
                                SizedBox(
                                  height: size.height * 0.04,
                                ),
                              ],
                            ),

                          Container(
                            width: size.width,
                            height: size.height * 0.19,
                            decoration: BoxDecoration(
                                color: AppColor.whiteColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: const Color(
                                      0xffDEE2E6,
                                    ),
                                    width: 1)),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: size.width * 0.03),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: size.height * 0.015,
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        AppLanguage.baseText[language],
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: AppFont.fontFamily,
                                            color: AppColor.thirdTextColor),
                                      ),
                                      Text(
                                        "₹${price?['base_fare'] ?? 0}",
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: AppFont.fontFamily,
                                            color: AppColor.thirdTextColor),
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    height: size.height * 0.015,
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        AppLanguage.distanceText[language],
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: AppFont.fontFamily,
                                            color: AppColor.thirdTextColor),
                                      ),
                                      Text(
                                        "₹${price?['distance_charge'] ?? 0}",
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: AppFont.fontFamily,
                                            color: AppColor.thirdTextColor),
                                      ),
                                    ],
                                  ),
                                  // GST row removed — no tax applied
                                  SizedBox(
                                    height: size.height * 0.015,
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        AppLanguage.totalText[language],
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: AppFont.fontFamily,
                                            color: AppColor.thirdTextColor),
                                      ),
                                      Text(
                                        AppLanguage.totalPriceText[language],
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: AppFont.fontFamily,
                                            color: AppColor.thirdTextColor),
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    height: size.height * 0.017,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          SizedBox(
                            height: size.height * 0.03,
                          ),

                          if (showTrackButton)
                            AppButton(
                              text: AppLanguage.trackDriveText[language],
                              onPress: () {
                                final userController =
                                    Provider.of<UserController>(context,
                                        listen: false);

                                final String customerId =
                                    userController.getUserId;
                                // logged-in customer
                                final String bookingId =
                                    widget.bookingId ?? ''; // booking id
                                final String driverId =
                                    data?['driver']?['_id']?.toString() ?? '';
                                final dynamic dropLatRaw =
                                    drop?['latitude'] ?? pickup?['latitude'];
                                final dynamic dropLngRaw =
                                    drop?['longitude'] ?? pickup?['longitude'];
                                final dynamic pickupLatRaw =
                                    pickup?['latitude'];
                                final dynamic pickupLngRaw =
                                    pickup?['longitude'];
                                final double? targetLat = dropLatRaw is num
                                    ? dropLatRaw.toDouble()
                                    : double.tryParse(
                                        dropLatRaw?.toString() ?? "");
                                final double? targetLng = dropLngRaw is num
                                    ? dropLngRaw.toDouble()
                                    : double.tryParse(
                                        dropLngRaw?.toString() ?? "");
                                final double? pickupLat = pickupLatRaw is num
                                    ? pickupLatRaw.toDouble()
                                    : double.tryParse(
                                        pickupLatRaw?.toString() ?? "");
                                final double? pickupLng = pickupLngRaw is num
                                    ? pickupLngRaw.toDouble()
                                    : double.tryParse(
                                        pickupLngRaw?.toString() ?? "");

                                debugPrint("➡️ Open Map");
                                debugPrint("🧪 customerId = $customerId");
                                debugPrint("🧪 bookingId = $bookingId");
                                debugPrint("🧪 driverId = $driverId");

                                Get.to(() => MapImageScreen(
                                      userId: customerId,
                                      bookingId: bookingId,
                                      driverId: driverId,
                                      vehicleName: (subVehicle?['name'] ??
                                              vehicle?['name'] ??
                                              '')
                                          .toString(),
                                      vehicleImage: (subVehicle?['image'] ??
                                              vehicle?['image'] ??
                                              '')
                                          .toString(),
                                      targetLat: targetLat,
                                      targetLng: targetLng,
                                      pickupLat: pickupLat,
                                      pickupLng: pickupLng,
                                      dropLat: targetLat,
                                      dropLng: targetLng,
                                      bookingStatus: widget.bookingStatus,
                                    ));
                              },
                            ),

                          if (widget.bookingStatus == 'Completed' ||
                              widget.bookingStatus == 'Delivered')
                            Container(
                              height: 53,
                              width: size.width * 0.4,
                              decoration: BoxDecoration(
                                // ignore: prefer_const_constructors
                                color: Color(0xff2AB0FC),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: InkWell(
                                onTap: () async {
                                  await downloadInvoice(
                                    context,
                                    _invoiceKey,
                                    data['booking_code'].toString(),
                                  );
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset(
                                      AppImage.download,
                                      height: 24,
                                      width: 24,
                                    ),
                                    SizedBox(width: size.width * 0.03),
                                    Text(
                                      AppLanguage.invoiceText[language],
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: AppFont.fontFamily,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          SizedBox(
                            height: size.height * 0.18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          floatingActionButton: GestureDetector(
            onTap: () {
              if (supportNumber != null && supportNumber != '') {
                openDialPad(supportNumber!);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Support number not available")),
                );
              }
            },
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
                // padding: EdgeInsets.zero,
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
                          /// TITLE
                          InkWell(
                            onTap: () {
                              Navigator.pop(context);
                              Get.to(
                                () => bookingHelpAndSupport(
                                  bookingId: widget.bookingId!,
                                  bookingCode: bookingCode,
                                ),
                              );
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

                          /// CANCELLATION POLICY (Hide if PickedUp)
                          if (widget.bookingStatus != "PickedUp")
                            InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                Get.to(
                                  () => CancellationPolicyScreen(
                                    bookingCode: bookingCode,
                                    bookingId: widget.bookingId,
                                    confirmbook: true,
                                  ),
                                );
                              },
                              child: const Text(
                                "Cancellation Policy",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: AppFont.fontFamily,
                                  color: AppColor.primaryColor,
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
