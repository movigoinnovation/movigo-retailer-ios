import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/get_navigation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:movigo/view/customer_screen/coins/coin_wallet_screen.dart';
import 'package:keep_screen_on/keep_screen_on.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/socket_connection/socket_provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/helper/Media_Image_viewer/media_viewer_helper.dart';
import 'package:movigo/helper/date_time_format/date_time_format.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_config_provider.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'booking_detail_screen.dart';
import 'cancel_ride_screen.dart';
import 'package:movigo/view/customer_screen/wallet_screen/add_money_screen.dart';

class ConfirmBookingScreen extends StatefulWidget {
  final Map<String, dynamic> bookingData;
  const ConfirmBookingScreen({super.key, required this.bookingData});

  @override
  State<ConfirmBookingScreen> createState() => _ConfirmBookingScreenState();
}

class _ConfirmBookingScreenState extends State<ConfirmBookingScreen> {
  final ScrollController _scrollController = ScrollController();
  Timer? _countdownTimer;
  Timer? _statusTimer;
  String? _createdBookingId;

  int _remainingSeconds = 300;
  bool _showTimer = false;
  int _statusHitCount = 0;
  String userId = "";

  String userType = "";

  // Coins
  int _coinBalance = 0;
  int _coinsToApply = 0;

  @override
  void initState() {
    super.initState();
    final userController = Provider.of<UserController>(context, listen: false);
    userId = userController.getUserId;

    setState(() {
      userType = userController.getUserType;
    });

    if (userType == "Retailer") {
      _loadCoinBalance();
    }

    debugPrint("========== CONFIRM BOOKING DATA ==========");
    debugPrint("Booking Type => ${widget.bookingData['booking_type']}");
    debugPrint("Vehicle Data => ${widget.bookingData['vehicle']}");
    debugPrint(
      "Sub Vehicle => ${widget.bookingData['sub_vehicle']}",
    );
    debugPrint("Pickup => ${widget.bookingData['pickup']}");
    debugPrint("Drop => ${widget.bookingData['drop']}");
    debugPrint("Pickup Date => ${widget.bookingData['pickup_date']}");
    debugPrint("Pickup Slot => ${widget.bookingData['pickup_slot']}");
    debugPrint("Pickup Shift => ${widget.bookingData['pickup_shift']}");
    debugPrint("Item Category => ${widget.bookingData['item_category']}");
    debugPrint("Need Helper => ${widget.bookingData['need_helper']}");
    debugPrint("Note => ${widget.bookingData['note']}");
    final images = widget.bookingData['images'] as List?;
    debugPrint("Images Count => ${images?.length ?? 0}");
    debugPrint("==========================================");
  }

  // Future<void> createOrder(amount) async {
  //   log("Called");
  //   String razorpayKey =
  //       AppConstant.razorpayKey; // Replace with your Razorpay key
  //   const String url = 'https://api.razorpay.com/v1/orders';
  //   final headers = {
  //     'Content-Type': 'application/json',
  //     'Authorization':
  //         'Basic ${base64Encode(utf8.encode('$razorpayKey:${AppConstant.razorpaySecretKey}'))}',
  //   };
  //   final body = jsonEncode({
  //     'amount': amount * 100, // Amount in paise (1000000 means ₹1000)
  //     'currency': 'INR',
  //     'receipt': 'Receipt no. 1',
  //     'notes': {
  //       'notes_key_1': 'Tea, Earl Grey, Hot',
  //       'notes_key_2': 'Tea, Earl Grey… decaf.',
  //     }
  //   });
  //   log("Reached 434");
  //   try {
  //     final response =
  //         await http.post(Uri.parse(url), headers: headers, body: body);
  //     log("Reached 439 ${response.body}");
  //     if (response.statusCode == 200) {
  //       final orderData = jsonDecode(response.body);
  //       String orderId = orderData['id'];
  //       // Proceed to Razorpay Checkout
  //       paymentApi(amount, orderId);
  //     } else {}
  //   } catch (e) {}
  // }

  // paymentApi(amount, orderId) {
  paymentApi(amount) {
    final user = Provider.of<UserController>(context, listen: false);
    if (amount == 0) {
      print('602 0 amount');
      // joinAndPay('12345', 1);
    } else {
      // print('amount340${double.parse(widget.amount)}');

      Razorpay razorpay = Razorpay();
      var options = {
        "image":
            "https://movigoinnovations.com/app/server/uploads/movigo_black.png",
        'key': AppConstant.razorpayKeyFromOrder(null),
        'amount': amount * 100,
        'name': 'Movigo Customer App',
        // 'order_id': orderId,
        'description': 'Become Premium Member',
        'retry': {'enabled': true, 'max_count': 1},
        'send_sms_hash': true,
        'prefill': {
          'contact': user.getUserMobile.isNotEmpty ? user.getUserMobile : '',
          'email': user.getUserEmail.isNotEmpty
              ? user.getUserEmail
              : 'test@razorpay.com',
        },
        'external': {
          'wallets': ['paytm']
        },
        'theme': {'color': '#124D85'}
      };
      razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, handlePaymentErrorResponse);
      razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, handlePaymentSuccessResponse);
      razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, handleExternalWalletSelected);
      razorpay.open(options);
      // Navigator.push(
      //     context,
      //     MaterialPageRoute(
      //         builder: (context) => ProceedToPay()));
    }
  }

  void handlePaymentErrorResponse(
    PaymentFailureResponse response,
  ) {
    /*
    * PaymentFailureResponse contains three values:
    * 1. Error Code
    * 2. Error Description
    * 3. Metadata
    * */

    SnackBarToastMessage.showSnackBar(context, "Payment Failed");
    // showAlertDialog(context, "Payment Failed",
    //     "Code: ${response.code}\nDescription: ${response.message}\nMetadata:${response.error.toString()}");
  }

  Future<void> handlePaymentSuccessResponse(
      PaymentSuccessResponse response) async {
    /*
    * Payment Success Response contains three values:
    * 1. Order ID
    * 2. Payment ID
    * 3. Signature
    * */
    print("============================${response.data.toString()}");

    // buySubscriptionApiCall(chatAmount, response.paymentId);
    // final apiProvider = Provider.of<PostApiProvider>(context, listen: false);
    // final success = await apiProvider.addWalletAmountApi(
    //   context,
    //   amount: selectedAmount.toString(),
    //   // transactionId: response.paymentId ?? "",
    // );

    // if (success && context.mounted) {
    //   Get.back(result: true);
    // }
    // joinAndPay(response.paymentId, 1);
    // showAlertDialog(
    //     context, "Payment Successful", "Payment ID: ${response.paymentId}");
  }

  void handleExternalWalletSelected(ExternalWalletResponse response) {
    SnackBarToastMessage.showSnackBar(
        context, "External Wallet Selected${response.walletName}");
    // showAlertDialog(
    //     context, "External Wallet Selected", "${response.walletName}");
  }

  Future<void> _loadCoinBalance() async {
    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final res = await provider.getCoinsBalanceApi(context);
    if (mounted && res != null && res['data'] != null) {
      setState(() {
        _coinBalance = (res['data']['coin_balance'] ?? 0) as int;
        _coinsToApply = 0;
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _statusTimer?.cancel();
    super.dispose();
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

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  //=========== Booking Flow and Timer ==========//
  void _startBookingFlow(String bookingId) {
    _createdBookingId = bookingId; // ✅ BOOKING ID

    KeepScreenOn.turnOn(); // 👈 Screen ON

    //  SCROLL TO TOP
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });

    setState(() {
      _showTimer = true;
      _remainingSeconds = 300;
    });
    final socketProvider = Provider.of<SocketProvider>(context, listen: false);

    socketProvider.emitBookingStatus(
      userId: userId,
      bookingId: bookingId,
    );

    /// ⏱ Countdown timer
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        timer.cancel();
        _onTimerExpired(); // 👈 Cancell booking
      }
    });

    /// 🔁 Status polling fallback every 5 sec (catches missed socket events)
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_dialogShown) {
        _statusTimer?.cancel();
        return;
      }
      final socketProvider =
          Provider.of<SocketProvider>(context, listen: false);
      socketProvider.emitBookingStatus(
        userId: userId,
        bookingId: bookingId,
      );
    });
  }

  bool _dialogShown = false;

  // =========== Time Cancel  ===========
  Future<void> _onTimerExpired() async {
    if (_createdBookingId == null) return;
    if (_dialogShown) return; // driver already accepted

    debugPrint("⏱ TIMER EXPIRED — AUTO CANCELLING BOOKING: $_createdBookingId");

    final postApi = Provider.of<PostApiProvider>(context, listen: false);

    await postApi.cancelBookingApi(
      context,
      bookingId: _createdBookingId!,
      cancellationReason: "Auto Cancelled",
      cancelledBy: "System", // 👈  pass
    );

    if (!mounted) return;

    _showAutoCancelledDialog(); // 👈 popup
  }

  // =========== NO DRIVER AVAILABLE POPUP ===========
  void _showAutoCancelledDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (dialogContext) {
        final size = MediaQuery.of(dialogContext).size;

        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: size.width * 0.85,
              padding: EdgeInsets.symmetric(
                horizontal: size.width * 0.06,
                vertical: size.height * 0.03,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 🚫 No-driver icon
                  Container(
                    height: 72,
                    width: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.shade50,
                    ),
                    child: const Icon(
                      Icons.no_transfer,
                      size: 44,
                      color: Colors.red,
                    ),
                  ),
                  SizedBox(height: size.height * 0.025),
                  const Text(
                    "No Driver Available",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.blackColor,
                    ),
                  ),
                  SizedBox(height: size.height * 0.015),
                  const Text(
                    "No driver is available currently. Please try again.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.hintTextColor,
                    ),
                  ),
                  SizedBox(height: size.height * 0.03),
                  AppButton(
                    text: "OK",
                    onPress: () {
                      Navigator.of(dialogContext).pop();
                      // Go to home screen
                      Get.offAll(() => const CustomBottomNav(
                            userType: UserType.retailer,
                            initialIndex: 1, // home tab
                          ));
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusProvider = Provider.of<SocketProvider>(context);

    if (statusProvider.isDriverAccepted == true && !_dialogShown) {
      _dialogShown = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint("✅ DRIVER ACCEPTED — STOP TIMER & SHOW POPUP");
        _showDriverConfirmedDialog();
      });
    }
    final size = MediaQuery.of(context).size;

    final vehicle = widget.bookingData['vehicle'];
    final Map<String, dynamic>? subVehicle =
        (vehicle['sub_types'] as List?)?.firstWhere(
      (e) => e['_id'] == widget.bookingData['sub_vehicle']?['id'],
      orElse: () => null,
    );
    final Map<String, dynamic>? price =
        widget.bookingData['price_estimate'] as Map<String, dynamic>?;

    final String supportNumber = price != null && price['supportNumber'] != null
        ? price['supportNumber'].toString()
        : "";
    final Map<String, dynamic>? breakup =
        price != null ? price['price_breakup'] as Map<String, dynamic>? : null;

    final double distanceInKm =
        (widget.bookingData['price_estimate']?['distance_in_km'] ?? 0)
            .toDouble();

    final double vehiclePrice = (vehicle['price_per_km'] ?? 0).toDouble();

    final double baseFare = (breakup?['base_fare'] ?? 0).toDouble();
    final double distanceCharge = (breakup?['distance_charge'] ?? 0).toDouble();
    // GST removed — total_amount is the final fare (no tax added)
    final double totalAmount = (breakup?['total_amount'] ?? 0).toDouble();

    price != null ? price['price_breakup'] : null;

    //  "price_breakup": {
    //         "base_fare": 100,
    //         "distance_charge": 0,
    //         "sub_total": 100,
    //         "total_amount": 118,
    //         "platform_commission": 10,
    //         "driver_earning": 90
    //     },

    // final vehicle = widget.bookingData['vehicle'];
    final pickup = widget.bookingData['pickup'];
    final drop = widget.bookingData['drop'];
    final category = widget.bookingData['item_category'];
    final images = widget.bookingData['images'] as List? ?? [];
    final String note = widget.bookingData['note'] ?? '';

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return PopScope(
      canPop: _createdBookingId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _createdBookingId != null) {
          Get.offAll(() => const CustomBottomNav(userType: UserType.retailer, initialIndex: 1));
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Container(
              height: size.height * 0.35,
              width: size.width,
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(AppImage.liveimage),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  SizedBox(height: size.height * 0.03),
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: size.width * 0.05),
                      // child: Row(
                      //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      //   children: [
                      //     // InkWell(
                      //     //   onTap: () {
                      //     //     if (_createdBookingId != null) {
                      //     //       Get.offAll(() => const CustomBottomNav(
                      //     //             userType: UserType.individual,
                      //     //             initialIndex: 1,
                      //     //           ));
                      //     //     } else {
                      //     //       Navigator.pop(context);
                      //     //     }
                      //     //   },
                      //     //   child: Image.asset(
                      //     //     AppImage.backimage,
                      //     //     height: 40,
                      //     //     width: 40,
                      //     //   ),
                      //     // ),
                      //     _showTimer
                      //         ? Text(
                      //             _formatTime(_remainingSeconds),
                      //             style: const TextStyle(
                      //               fontSize: 30,
                      //               fontWeight: FontWeight.w700,
                      //               fontFamily: AppFont.fontFamily,
                      //             ),
                      //           )
                      //         : const SizedBox(width: 60),
                      //     _showTimer
                      //         ? InkWell(
                      //             child: Image.asset(
                      //               AppImage.threedot,
                      //               height: 40,
                      //               width: 40,
                      //             ),
                      //           )
                      //         : const SizedBox(width: 40),
                      //   ],
                      // ),

                      child: SizedBox(
                        width: double.infinity,
                        child: Center(
                          child: _showTimer
                              ? Text(
                                  _formatTime(_remainingSeconds),
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: AppFont.fontFamily,
                                  ),
                                )
                              : const SizedBox(),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: size.height * 0.1),
                  Container(
                    width: size.width,
                    padding: EdgeInsets.symmetric(
                      horizontal: size.width * 0.05,
                      vertical: size.height * 0.03,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(28),
                        topRight: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: size.height * 0.02,
                        ),
                        Text(
                          _showTimer
                              ? "Finding Your Driver"
                              : AppLanguage.reviewdetailText[language],
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              fontFamily: AppFont.fontFamily,
                              color: AppColor.blackColor),
                        ),

                        SizedBox(
                          height: size.height * 0.004,
                        ),
                        Text(
                          "Price per km: ₹${vehiclePrice.toInt()}",
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColor.primaryColor,
                          ),
                        ),
                        SizedBox(height: size.height * 0.02),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  height: size.width * 0.12,
                                  width: size.width * 0.12,
                                  child: Image.network(
                                    subVehicle != null &&
                                            subVehicle['image'] != null
                                        ? "${AppConfigProvider.imgUrl}${subVehicle['image']}"
                                        : "${AppConfigProvider.imgUrl}${vehicle['image']}",
                                    fit: BoxFit.cover,
                                    cacheWidth: 100,
                                    errorBuilder: (_, __, ___) {
                                      return Image.asset(AppImage.dummyimage);
                                    },
                                  ),
                                ),
                                SizedBox(width: size.width * 0.03),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: MediaQuery.of(context).size.width *
                                          42 /
                                          100,
                                      child: Text(
                                        subVehicle != null
                                            ? subVehicle['name']
                                            : vehicle['name'],
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: AppFont.fontFamily,
                                          color: AppColor.blackColor,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: MediaQuery.of(context).size.width *
                                          42 /
                                          100,
                                      child: Text(
                                        vehicle['name'] ?? '',
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: AppFont.fontFamily,
                                          color: AppColor.blackColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  BookingDateTimeHelper.uiDateToFigma(
                                    widget.bookingData['pickup_date'],
                                  ),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppColor.secondTextColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  BookingTimeHelper.toFigma(
                                    widget.bookingData['pickup_slot'],
                                  ),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppColor.secondTextColor,
                                  ),
                                ),
                              ],
                            ),
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
                                      6,
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
                                    pickup['address'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: AppColor.selectTpeColor,
                                    ),
                                  ),
                                  SizedBox(height: size.height * 0.03),
                                  Text(
                                    drop['address'] ?? '',
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
                          height: size.height * 0.02,
                        ),
                        Text(
                          "Total Distance: ${distanceInKm.toString()}km",
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              fontFamily: AppFont.fontFamily,
                              color: AppColor.thirdTextColor),
                        ),
                        SizedBox(
                          height: size.height * 0.02,
                        ),
                        if (widget.bookingData['need_helper'] == true &&
                            (widget.bookingData['total_helpers'] ?? 0) > 0) ...[
                          Text(
                            "Helper Included : ${widget.bookingData['total_helpers'] ?? 0}",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: AppFont.fontFamily,
                              color: AppColor.blackColor,
                            ),
                          ),
                          SizedBox(height: size.height * 0.01),
                          const Text(
                            "20kg for 1 helpers",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              fontFamily: AppFont.fontFamily,
                              color: AppColor.greyColor,
                            ),
                          ),
                          SizedBox(height: size.height * 0.02),
                        ],
                        Text(
                          category['name'] ?? '',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFamily: AppFont.fontFamily,
                              color: AppColor.blackColor),
                        ),
                        SizedBox(
                          height: size.height * 0.01,
                        ),
                        if (note.trim().isNotEmpty) ...[
                          Text(
                            note,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              fontFamily: AppFont.fontFamily,
                              color: Color(0xff6E6E6E),
                            ),
                          ),
                          SizedBox(height: size.height * 0.04),
                        ],
                        if (images.isNotEmpty) ...[
                          SizedBox(
                            height: size.height * 0.16,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: images.length, // 🔥 show all images
                              itemBuilder: (context, index) {
                                return Container(
                                  width: size.width * 0.42,
                                  margin:
                                      EdgeInsets.only(right: size.width * 0.03),
                                  child: InkWell(
                                    onTap: () {
                                      MediaViewerHelper.openLocalImages(
                                        context: context,
                                        images:
                                            images.whereType<File>().toList(),
                                        startIndex: index,
                                      );
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.file(
                                        images[index],
                                        fit: BoxFit.cover,
                                        cacheWidth: 400,
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
                        //   height: size.height * 0.04,
                        // ),
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
                                      breakup != null
                                          ? "₹${baseFare.toStringAsFixed(2)}"
                                          : "₹0",
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
                                      price != null
                                          ? "₹${distanceCharge.toStringAsFixed(2)}"
                                          : "₹0",
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
                                      "₹${totalAmount.toStringAsFixed(2)}",
                                      style: const TextStyle(
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
                          height: size.height * 0.03,
                        ),

                        // ── Coins Discount Section (Retailer only, ₹100+ rides) ─────────
                        if (userType == "Retailer" && !_showTimer && totalAmount >= 100) ...[
                          _CoinsApplySection(
                            coinBalance:   _coinBalance,
                            coinsToApply:  _coinsToApply,
                            totalFare:     totalAmount,
                            onCoinsChanged: (val) => setState(() => _coinsToApply = val),
                          ),
                          SizedBox(height: size.height * 0.02),
                        ],

                        if (!_showTimer)
                          AppButton(
                            text: AppLanguage.confirmBookingText[language],
                            onPress: () {
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: Colors.transparent,
                                isScrollControlled: true,
                                builder: (_) => _PaymentBottomSheet(
                                  bookingData: widget.bookingData,
                                  coinsToApply: _coinsToApply,
                                  onBookingCreated: (bookingId) {
                                    _startBookingFlow(bookingId);
                                  },
                                ),
                              );
                            },
                          ),

                        // Cancel Ride — only visible while searching for a driver
                        if (_showTimer && _createdBookingId != null) ...[
                          SizedBox(height: size.height * 0.015),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CancelRideScreen(
                                      bookingId: _createdBookingId!,
                                      userType: userType,
                                    ),
                                  ),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: AppColor.redAppColor, width: 1.5),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15),
                              ),
                              child: const Text(
                                "Cancel Ride",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: AppFont.fontFamily,
                                  color: AppColor.redAppColor,
                                ),
                              ),
                            ),
                          ),
                        ],

                        SizedBox(
                          height: size.height * 0.20,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: GestureDetector(
          onTap: () {
            if (supportNumber.isNotEmpty) {
              openDialPad(supportNumber);
            } else {
              debugPrint("❌ Support number not available");
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
    );
  }

  // Driver pop up
  void _showDriverConfirmedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (dialogContext) {
        // 👈 important
        final size = MediaQuery.of(dialogContext).size;

        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: size.width * 0.85,
              padding: EdgeInsets.symmetric(
                horizontal: size.width * 0.06,
                vertical: size.height * 0.03,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(AppImage.Success, height: 80, width: 80),
                  SizedBox(height: size.height * 0.025),
                  Text(
                    AppLanguage.driverText[language],
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.blackColor,
                    ),
                  ),
                  SizedBox(height: size.height * 0.015),
                  Text(
                    AppLanguage.drivereAccText[language],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.hintTextColor,
                    ),
                  ),
                  SizedBox(height: size.height * 0.03),
                  AppButton(
                    text: AppLanguage.viewDetailsText[language],
                    onPress: () {
                      // ✅ Close dialog
                      Navigator.of(dialogContext).pop();
                      Navigator.of(dialogContext).pop();

                      final statusProvider =
                          Provider.of<SocketProvider>(context, listen: false);
                      statusProvider.setDriverAccepted(false);
                      // ✅ Navigate
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BookingDetailScreen(
                            bookingId: _createdBookingId!,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

//
}

// ── Coins Apply Section ───────────────────────────────────────────────────────

class _CoinsApplySection extends StatelessWidget {
  final int coinBalance;
  final int coinsToApply;
  final double totalFare;
  final ValueChanged<int> onCoinsChanged;

  static const int _minRedeem = 10;
  static const int _maxRedeem = 30;

  const _CoinsApplySection({
    required this.coinBalance,
    required this.coinsToApply,
    required this.totalFare,
    required this.onCoinsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final int maxApplicable = coinBalance.clamp(0, _maxRedeem);
    final bool eligible     = coinBalance >= _minRedeem;
    final bool isApplying   = coinsToApply > 0;
    final bool hasRange     = maxApplicable > _minRedeem;
    final double finalFare  = (totalFare - coinsToApply).clamp(0, double.infinity);

    if (!eligible) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xffDEE2E6)),
        ),
        child: Row(
          children: [
            const Text('🪙', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                coinBalance == 0
                    ? 'Complete orders to earn coins and use them as a discount here.'
                    : 'Earn at least $_minRedeem coins to redeem on a ride. You have $coinBalance.',
                style: const TextStyle(fontSize: 12.5, color: AppColor.greyColor, fontFamily: AppFont.fontFamily),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: coinsToApply > 0 ? const Color(0xFF1E88E5).withOpacity(0.5) : const Color(0xffDEE2E6),
          width: coinsToApply > 0 ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🪙', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text(
                'Use Coins as Discount',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily, color: AppColor.blackColor),
              ),
              const Spacer(),
              Text(
                '$coinBalance available',
                style: const TextStyle(fontSize: 12, color: AppColor.greyColor, fontFamily: AppFont.fontFamily),
              ),
              const SizedBox(width: 8),
              Switch(
                value: isApplying,
                activeThumbColor: const Color(0xFF1E88E5),
                onChanged: (v) => onCoinsChanged(v ? _minRedeem.clamp(0, maxApplicable) : 0),
              ),
            ],
          ),
          if (isApplying) ...[
            const SizedBox(height: 4),
            if (hasRange) ...[
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor:   const Color(0xFF1E88E5),
                  inactiveTrackColor: Colors.grey.shade200,
                  thumbColor:         const Color(0xFF1E88E5),
                  overlayColor:       const Color(0xFF1E88E5).withOpacity(0.12),
                  trackHeight:        4,
                ),
                child: Slider(
                  value: coinsToApply.toDouble().clamp(_minRedeem.toDouble(), maxApplicable.toDouble()),
                  min:  _minRedeem.toDouble(),
                  max:  maxApplicable.toDouble(),
                  divisions: maxApplicable - _minRedeem,
                  onChanged: (v) => onCoinsChanged(v.round()),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$_minRedeem 🪙', style: const TextStyle(fontSize: 11, color: AppColor.greyColor, fontFamily: AppFont.fontFamily)),
                  Text(
                    'Using $coinsToApply coins — saves you ₹$coinsToApply',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF1E88E5), fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily),
                  ),
                  Text('$maxApplicable 🪙', style: const TextStyle(fontSize: 11, color: AppColor.greyColor, fontFamily: AppFont.fontFamily)),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Using $coinsToApply coins — saves you ₹$coinsToApply',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF1E88E5), fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily),
                ),
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('You Pay', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily, color: AppColor.blackColor)),
                  Text('₹${finalFare.toStringAsFixed(2)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFamily: AppFont.fontFamily, color: Colors.green.shade700)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentBottomSheet extends StatefulWidget {
  final Map<String, dynamic> bookingData;
  final Function(String bookingId) onBookingCreated;
  final int coinsToApply;

  const _PaymentBottomSheet({
    Key? key,
    required this.bookingData,
    required this.onBookingCreated,
    this.coinsToApply = 0,
  }) : super(key: key);

  @override
  State<_PaymentBottomSheet> createState() => _PaymentBottomSheetState();
}

class _PaymentBottomSheetState extends State<_PaymentBottomSheet> {
  // Step 1: choose WHERE to pay (Pickup or Drop or Online)
  // Step 2: choose HOW to pay (Cash or UPI) — only shown for Pickup/Drop
  int _step = 1;
  String _paymentLocation = ""; // "Pickup", "Drop", or "Online"
  String _paymentMode = "";     // "Cash", "UPI", or "Online"

  bool isLoading = false;
  String userType = "";

  // Razorpay for Online payment
  Razorpay? _razorpay;
  bool _razorpayPending = false;

  @override
  void initState() {
    super.initState();
    final userController = Provider.of<UserController>(context, listen: false);
    setState(() {
      userType = userController.getUserType;
    });
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onRazorpaySuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _onRazorpayError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _razorpay?.clear();
    super.dispose();
  }

  // ── Online payment via Razorpay ───────────────────────────────────────────
  void _openRazorpayWithOrder(Map<String, dynamic> orderData) {
    final user = Provider.of<UserController>(context, listen: false);
    final options = {
      'key':      AppConstant.razorpayKeyFromOrder(orderData),
      'amount':   orderData['amount_paise'] ?? orderData['total_paise'] ?? 0,
      'order_id': orderData['order_id'] ?? '',
      'name':     'Movigo',
      'description': 'Booking Payment (incl. 2% processing fee)',
      'image': 'https://movigoinnovations.com/app/server/uploads/movigo_black.png',
      'prefill': {
        'contact': user.getUserMobile.isNotEmpty ? user.getUserMobile : '',
        'email':   user.getUserEmail.isNotEmpty  ? user.getUserEmail  : 'customer@movigo.com',
        'name':    user.getUserName.isNotEmpty   ? user.getUserName   : '',
      },
      'theme': {'color': '#124D85'},
      'retry': {'enabled': true, 'max_count': 2},
    };
    _razorpay!.open(options);
  }

  void _openRazorpay(double amount) {
    final user = Provider.of<UserController>(context, listen: false);
    final int amountPaise = (amount * 100).round();
    final options = {
      'key': AppConstant.razorpayKeyFromOrder(null),
      'amount': amountPaise,
      'name': 'Movigo',
      'description': 'Booking Payment',
      'image': 'https://movigoinnovations.com/app/server/uploads/movigo_black.png',
      'prefill': {
        'contact': user.getUserMobile.isNotEmpty ? user.getUserMobile : '',
        'email': user.getUserEmail.isNotEmpty ? user.getUserEmail : 'customer@movigo.com',
        'name': user.getUserName.isNotEmpty ? user.getUserName : '',
      },
      'theme': {'color': '#124D85'},
      'retry': {'enabled': true, 'max_count': 2},
    };
    _razorpay!.open(options);
  }

  Future<void> _onRazorpaySuccess(PaymentSuccessResponse response) async {
    if (!_razorpayPending) return;
    _razorpayPending = false;

    setState(() => isLoading = true);
    // Use Razorpay paymentId as the transaction ID
    final bookingData = widget.bookingData;
    bookingData['transaction_id'] = response.paymentId ?? '';

    final success = await _createBookingWithTransactionId(
      context,
      transactionId: response.paymentId ?? '',
    );

    if (mounted) setState(() => isLoading = false);
    if (!success) {
      SnackBarToastMessage.showSnackBar(
          context, "Payment received but booking failed. Contact support.");
    }
  }

  void _onRazorpayError(PaymentFailureResponse response) {
    _razorpayPending = false;
    if (mounted) {
      SnackBarToastMessage.showSnackBar(context, "Payment failed. Please try again.");
    }
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    _razorpayPending = false;
    if (mounted) {
      SnackBarToastMessage.showSnackBar(context,
          "External wallet selected: ${response.walletName}");
    }
  }

  Future<void> _refreshPriceEstimate(BuildContext context) async {
    final postApi = Provider.of<PostApiProvider>(context, listen: false);
    final bookingData = widget.bookingData;
    final double rawDistance = num.tryParse(
            bookingData['raw_distance_km']?.toString() ??
            bookingData['price_estimate']?['distance_in_km']?.toString() ??
            '0.0')
        ?.toDouble() ??
        0.0;
    final res = await postApi.priceEstimateApi(
      context,
      vehicleTypeId: bookingData['vehicle']['id'].toString(),
      pickupLat: bookingData['pickup']['lat'],
      pickupLng: bookingData['pickup']['lng'],
      dropLat: bookingData['drop']['lat'],
      dropLng: bookingData['drop']['lng'],
      requestedVehicleName: bookingData['vehicle']?['name']?.toString() ?? '',
      vehicleKey: bookingData['vehicle']?['vehicleKey']?.toString() ?? bookingData['vehicle']?['requiredTag']?.toString() ?? bookingData['vehicle']?['required_tag']?.toString() ?? '',
      requiredTag: bookingData['vehicle']?['requiredTag']?.toString() ?? bookingData['vehicle']?['required_tag']?.toString() ?? '',
      rawDistanceKm: rawDistance,
    );
    if (res != null && mounted) {
      setState(() {
        widget.bookingData['price_estimate'] = res;
      });
    }
  }

  Future<bool> _createBookingWithTransactionId(
    BuildContext context, {
    required String transactionId,
  }) async {
    final bookingData = widget.bookingData;
    final postApi = Provider.of<PostApiProvider>(context, listen: false);
    final user = Provider.of<UserController>(context, listen: false);

    final List<File> fileImages =
        (bookingData['images'] as List?)?.whereType<File>().toList() ?? [];
    final List<XFile> xFiles =
        fileImages.map((file) => XFile(file.path)).toList();

    final bool isRetailer = userType == "Retailer";

    // Backend accepts: payment_mode = "Online" | "Cash"
    // "UPI" and "Cash" both map to "Cash" (driver collects offline)
    // "Online" = paid via Razorpay to company
    final String mode = _paymentLocation == "Online" ? "Online" : "Cash";

    final double rawDistance = num.tryParse(
            bookingData['raw_distance_km']?.toString() ??
            bookingData['price_estimate']?['distance_in_km']?.toString() ??
            '0.0')
        ?.toDouble() ??
        0.0;

    final success = isRetailer
        ? await postApi.createBookingRetailerApi(
            context,
            vehicleTypeId: bookingData['vehicle']['id'].toString(),
            subVehicleTypeId: bookingData['sub_vehicle']['id'].toString(),
            bookingType: bookingData['booking_type'] ?? "Now",
            transactionId: transactionId,
            customerName: user.getUserName,
            customerPhone: user.getUserMobile,
            pickupAddress: bookingData['pickup']['address'],
            pickupLat: bookingData['pickup']['lat'],
            pickupLng: bookingData['pickup']['lng'],
            dropAddress: bookingData['drop']['address'],
            dropLat: bookingData['drop']['lat'],
            dropLng: bookingData['drop']['lng'],
            pickupDate: BookingDateTimeHelper.uiToApiDate(bookingData['pickup_date']),
            pickupShift: "",
            pickupSlot: bookingData['pickup_slot'],
            itemCategoryId: bookingData['item_category']['id'].toString(),
            paymentMode: mode,
            note: bookingData['note'] ?? "",
            helperDescription: bookingData['helper_description'] ?? "",
            needHelper: false,
            totalHelpers: 0,
            itemImages: xFiles.isEmpty ? null : xFiles,
            rawDistanceKm: rawDistance,
            senderName: user.getUserName,
            senderPhone: user.getUserMobile,
            receiverName: (bookingData['receiver_name'] ?? "").toString(),
            receiverPhone: (bookingData['receiver_contact'] ?? "").toString(),
          )
        : await postApi.createBookingCustomerApi(
            context,
            vehicleTypeId: bookingData['vehicle']['id'].toString(),
            subVehicleTypeId: bookingData['sub_vehicle']['id'].toString(),
            transactionId: transactionId,
            bookingType: bookingData['booking_type'] ?? "Now",
            pickupAddress: bookingData['pickup']['address'],
            pickupLat: bookingData['pickup']['lat'],
            pickupLng: bookingData['pickup']['lng'],
            dropAddress: bookingData['drop']['address'],
            dropLat: bookingData['drop']['lat'],
            dropLng: bookingData['drop']['lng'],
            pickupDate: BookingDateTimeHelper.uiToApiDate(bookingData['pickup_date']),
            pickupShift: "",
            pickupSlot: bookingData['pickup_slot'],
            itemCategoryId: bookingData['item_category']['id'].toString(),
            paymentMode: mode,
            note: bookingData['note'] ?? "",
            receiverName: bookingData['receiver_name'] ?? "",
            receiverContact: bookingData['receiver_contact'] ?? "",
            helperDescription: bookingData['helper_description'] ?? "",
            needHelper: false,
            totalHelpers: 0,
            itemImages: xFiles.isEmpty ? null : xFiles,
            rawDistanceKm: rawDistance,
          );

    if (!success) return false;
    if (!mounted) return false;
    final bookingId = postApi.bookingId;
    if (bookingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking failed. Please try again.')),
      );
      return false;
    }
    Navigator.pop(context);

    // Apply coins discount if selected
    if (widget.coinsToApply > 0) {
      await postApi.applyCoinsApi(
        context,
        coinsToApply: widget.coinsToApply,
        bookingId:    bookingId,
      );
    }

    widget.onBookingCreated(bookingId);
    return true;
  }

  Future<bool> _createBooking(BuildContext context) async {
    return _createBookingWithTransactionId(
      context,
      transactionId: "", // cash bookings have no payment transaction
    );
  }

  Future<void> _attemptCreateBooking(BuildContext context) async {
    // Online payment: call backend first to create order with 2% processing fee
    if (_paymentLocation == "Online") {
      final price   = widget.bookingData['price_estimate'];
      final breakup = price != null ? price['price_breakup'] : null;
      final double totalAmount = (breakup?['total_amount'] ?? 0).toDouble();
      if (totalAmount <= 0) {
        SnackBarToastMessage.showSnackBar(context, "Invalid booking amount.");
        return;
      }

      // Create Razorpay order on backend (adds 2% processing fee)
      setState(() => isLoading = true);
      final postApi = Provider.of<PostApiProvider>(context, listen: false);
      final orderData = await postApi.createBookingPaymentOrder(
        context,
        baseFare: totalAmount.round(),
      );
      setState(() => isLoading = false);

      if (orderData == null) {
        SnackBarToastMessage.showSnackBar(
            context, "Could not initiate payment. Please try again.");
        return;
      }

      _razorpayPending = true;
      _openRazorpayWithOrder(orderData);
      return;
    }

    // Cash/UPI: create booking directly
    setState(() => isLoading = true);
    final success = await _createBooking(context);
    if (mounted) setState(() => isLoading = false);
    if (success) return;
    final postApi = Provider.of<PostApiProvider>(context, listen: false);
    final message = postApi.lastErrorMessage ?? "Unable to create booking right now.";
    SnackBarToastMessage.showSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 48),
          width: size.width,
          padding: EdgeInsets.symmetric(
            horizontal: size.width * 0.06,
            vertical: size.height * 0.03,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: size.height * 0.02),

              // Step indicator — only 2 steps if Online, else 2 for cash/upi
              if (_paymentLocation != "Online")
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _stepDot(1),
                    Container(width: 32, height: 2, color: _step >= 2 ? AppColor.themeColor : Colors.grey.shade300),
                    _stepDot(2),
                  ],
                ),

              SizedBox(height: size.height * 0.025),

              if (_step == 1) ...[
                const Text(
                  "How would you like to pay?",
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppFont.fontFamily,
                    color: AppColor.blackColor,
                  ),
                ),
                SizedBox(height: size.height * 0.008),
                const Text(
                  "Choose when and how payment will be made",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    fontFamily: AppFont.fontFamily,
                    color: AppColor.greyColor,
                  ),
                ),
                SizedBox(height: size.height * 0.03),
                _locationTile(
                  label: "Pay at Pickup",
                  subtitle: "Pay the driver in cash or UPI when he arrives",
                  icon: Icons.location_on_rounded,
                  value: "Pickup",
                ),
                SizedBox(height: size.height * 0.015),
                _locationTile(
                  label: "Pay at Drop",
                  subtitle: "Pay the driver in cash or UPI after delivery",
                  icon: Icons.flag_rounded,
                  value: "Drop",
                ),
                SizedBox(height: size.height * 0.015),
                _locationTile(
                  label: "Pay Online Now",
                  subtitle: "Pay the full amount online to Movigo securely",
                  icon: Icons.payment_rounded,
                  value: "Online",
                  accent: const Color(0xFF1565C0),
                ),
                SizedBox(height: size.height * 0.04),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _paymentLocation.isEmpty
                        ? null
                        : () {
                            if (_paymentLocation == "Online") {
                              // Skip step 2 — go straight to Razorpay
                              _attemptCreateBooking(context);
                            } else {
                              setState(() => _step = 2);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColor.themeColor,
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: isLoading
                        ? const SizedBox(height: 20, width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(
                            _paymentLocation == "Online" ? "Pay Now" : "Next",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: AppFont.fontFamily,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ] else if (_step == 2) ...[
                const Text(
                  "How will you pay the driver?",
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppFont.fontFamily,
                    color: AppColor.blackColor,
                  ),
                ),
                SizedBox(height: size.height * 0.008),
                Text(
                  "Payment at ${_paymentLocation == "Pickup" ? "pickup location" : "drop location"}",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    fontFamily: AppFont.fontFamily,
                    color: AppColor.themeColor,
                  ),
                ),
                SizedBox(height: size.height * 0.03),
                _paymentTile(
                  title: "Cash",
                  subtitle: "Pay with physical cash directly to the driver",
                  icon: Icons.payments_rounded,
                  value: "Cash",
                ),
                SizedBox(height: size.height * 0.015),
                _paymentTile(
                  title: "UPI",
                  subtitle: "Pay via UPI (GPay, PhonePe, Paytm, etc.)",
                  icon: Icons.account_balance_wallet_rounded,
                  value: "UPI",
                ),
                SizedBox(height: size.height * 0.04),
                Consumer<PostApiProvider>(
                  builder: (context, apiProvider, _) {
                    return apiProvider.loading
                        ? const Center(child: CircularProgressIndicator(color: AppColor.primaryColor))
                        : SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: (_paymentMode.isEmpty || isLoading)
                                  ? null
                                  : () async {
                                      if (isLoading) return;
                                      await _attemptCreateBooking(context);
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColor.themeColor,
                                disabledBackgroundColor: Colors.grey.shade300,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                padding: const EdgeInsets.symmetric(vertical: 15),
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                      height: 20, width: 20,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Text(
                                      "Confirm Booking",
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: AppFont.fontFamily,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          );
                  },
                ),
                SizedBox(height: size.height * 0.01),
                TextButton(
                  onPressed: () => setState(() { _step = 1; _paymentMode = ""; }),
                  child: const Text(
                    "← Back",
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.greyColor,
                    ),
                  ),
                ),
              ],

              SizedBox(height: size.height * 0.02),
            ],
          ),
        ),
        Positioned(
          top: 0,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.close, size: 18, color: Colors.black),
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepDot(int step) {
    final bool active = _step >= step;
    return Container(
      height: 28,
      width: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppColor.themeColor : Colors.grey.shade300,
      ),
      child: Center(
        child: Text(
          "$step",
          style: TextStyle(
            color: active ? Colors.white : Colors.grey.shade500,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _locationTile({
    required String label,
    required String subtitle,
    required IconData icon,
    required String value,
    Color? accent,
  }) {
    final bool selected = _paymentLocation == value;
    final Color tileColor = accent ?? AppColor.themeColor;
    return GestureDetector(
      onTap: () => setState(() => _paymentLocation = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? tileColor : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          color: selected ? tileColor.withOpacity(0.05) : Colors.white,
        ),
        child: Row(
          children: [
            Container(
              height: 42, width: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? tileColor : Colors.grey.shade100,
              ),
              child: Icon(icon, color: selected ? Colors.white : Colors.grey.shade500, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppFont.fontFamily,
                      color: selected ? tileColor : AppColor.blackColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.greyColor,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: tileColor, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _paymentTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
  }) {
    final bool selected = _paymentMode == value;
    return GestureDetector(
      onTap: () => setState(() => _paymentMode = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColor.themeColor : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          color: selected ? AppColor.themeColor.withOpacity(0.05) : Colors.white,
        ),
        child: Row(
          children: [
            Container(
              height: 42, width: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColor.themeColor : Colors.grey.shade100,
              ),
              child: Icon(icon, color: selected ? Colors.white : Colors.grey.shade500, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppFont.fontFamily,
                      color: selected ? AppColor.themeColor : AppColor.blackColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.greyColor,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: AppColor.themeColor, size: 22),
          ],
        ),
      ),
    );
  }
}
