import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';

class AddMoneyScreen extends StatefulWidget {
  const AddMoneyScreen({super.key});

  @override
  State<AddMoneyScreen> createState() => _AddMoneyScreenState();
}

class _AddMoneyScreenState extends State<AddMoneyScreen> {
  final TextEditingController _amountController = TextEditingController();
  int selectedAmount = 500;
  Map<String, dynamic>? _pendingOrder;

  final List<int> quickAmounts = [100, 250, 500, 1000, 2500];

  @override
  void initState() {
    super.initState();
    _amountController.text = selectedAmount.toString();
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
  Future<void> paymentApi(amount) async {
    final user = Provider.of<UserController>(context, listen: false);
    final apiProvider = Provider.of<PostApiProvider>(context, listen: false);
    final int amountValue = int.tryParse(amount.toString()) ?? 0;
    if (amountValue < 1) {
      SnackBarToastMessage.showSnackBar(context, 'Enter a valid amount');
      return;
    }

    final orderData = await apiProvider.createDepositOrder(
      context,
      amount: amountValue.toString(),
    );
    final razorpayKey = AppConstant.razorpayKeyFromOrder(orderData);
    if (orderData == null || razorpayKey.isEmpty || orderData['order_id'] == null) {
      SnackBarToastMessage.showSnackBar(context, 'Unable to create payment order');
      return;
    }
    _pendingOrder = orderData;

    Razorpay razorpay = Razorpay();
    var options = {
      "image": "https://movigoinnovations.com/app/server/uploads/movigo_black.png",
      'key': razorpayKey,
      'amount': orderData['amount_paise'] ?? orderData['amount'] ?? (amountValue * 100),
      'order_id': orderData['order_id'],
      'name': 'Movigo Customer App',
      'description': 'Wallet Recharge',
      'retry': {'enabled': true, 'max_count': 1},
      'send_sms_hash': true,
      'prefill': {
        'contact': user.getUserMobile.isNotEmpty ? user.getUserMobile : '',
        'email': user.getUserEmail.isNotEmpty ? user.getUserEmail : 'customer@movigo.com',
      },
      'external': {'wallets': ['paytm']},
      'theme': {'color': '#124D85'}
    };
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, handlePaymentErrorResponse);
    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, handlePaymentSuccessResponse);
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, handleExternalWalletSelected);
    razorpay.open(options);
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

    final apiProvider = Provider.of<PostApiProvider>(context, listen: false);
    final orderId = response.orderId ?? _pendingOrder?['order_id']?.toString() ?? '';
    final paymentId = response.paymentId ?? '';
    final signature = response.signature ?? '';
    final success = await apiProvider.verifyDeposit(
      context,
      orderId: orderId,
      paymentId: paymentId,
      signature: signature,
      amount: selectedAmount.toString(),
    );

    if (success && context.mounted) {
      Get.back(result: true);
    }
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.white,
          scrolledUnderElevation: 0,
          toolbarHeight: size.height * 0.12,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: Padding(
            padding: EdgeInsets.only(top: size.height * 0.015),
            child: Row(
              children: [
                SizedBox(width: size.width * 0.035),
                InkWell(
                  onTap: () => Get.back(),
                  child: Image.asset(
                    AppImage.backimage,
                    height: size.height * 0.045,
                  ),
                ),
                SizedBox(width: size.width * 0.04),
                Text(
                  AppLanguage.addMoneyText[language],
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppFont.fontFamily,
                    color: AppColor.blackColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        body: Padding(
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: size.height * 0.03),
              Text(
                AppLanguage.creditAText[language],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  fontFamily: AppFont.fontFamily,
                  color: Color(0xff383838),
                ),
              ),
              SizedBox(height: size.height * 0.015),
              Container(
                height: size.height * 0.06,
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.04),
                decoration: BoxDecoration(
                  color: const Color(0xffF6F6F6),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontSize: 15,
                    fontFamily: AppFont.fontFamily,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: AppLanguage.enterAmountText[language],
                    hintStyle: const TextStyle(
                      fontSize: 15,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.hintTextColor,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                  ),
                  onChanged: (value) {
                    setState(() {
                      if (value.isEmpty) {
                        selectedAmount = 0;
                      } else {
                        selectedAmount = int.tryParse(value) ?? 0;
                      }
                    });
                  },
                ),
              ),
              SizedBox(height: size.height * 0.03),
              Text(
                AppLanguage.quickText[language],
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppFont.fontFamily,
                  color: AppColor.secondTextColor,
                ),
              ),
              SizedBox(height: size.height * 0.015),
              Wrap(
                spacing: size.width * 0.03,
                runSpacing: size.height * 0.015,
                children: quickAmounts.map((amount) {
                  final bool isSelected = selectedAmount == amount;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        selectedAmount = amount;
                        _amountController.text = amount.toString();

                        paymentApi(selectedAmount);
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: size.width * 0.05,
                        vertical: size.height * 0.01,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColor.themeColor : Colors.white,
                        borderRadius: BorderRadius.circular(124),
                        border: Border.all(
                          color: AppColor.themeColor,
                          width: 1.24,
                        ),
                      ),
                      child: Text(
                        amount.toString(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: AppFont.fontFamily,
                          color:
                              isSelected ? Colors.white : AppColor.themeColor,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const Spacer(),
              Padding(
                padding: EdgeInsets.only(bottom: size.height * 0.04),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedAmount > 0 ? "₹$selectedAmount" : "₹",
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            fontFamily: AppFont.fontFamily,
                            color: AppColor.blackColor,
                          ),
                        ),
                        SizedBox(height: size.height * 0.005),
                        Text(
                          AppLanguage.payOnlineText[language],
                          style: const TextStyle(
                            fontSize: 14,
                            fontFamily: AppFont.fontFamily,
                            color: AppColor.secondTextColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Consumer<PostApiProvider>(
                      builder: (context, apiProvider, _) {
                        return SizedBox(
                          width: size.width * 0.4,
                          height: size.height * 0.055,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColor.themeColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: apiProvider.loading
                                ? null
                                : () async {
                                    FocusScope.of(context).unfocus();

                                    if (selectedAmount < 100) {
                                      SnackBarToastMessage.showSnackBar(
                                        context,
                                        "Please enter an amount of at least ₹100.",
                                      );
                                      return;
                                    }

                                    paymentApi(selectedAmount);
                                  },
                            child: apiProvider.loading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    AppLanguage.addText[language],
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: AppFont.fontFamily,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
