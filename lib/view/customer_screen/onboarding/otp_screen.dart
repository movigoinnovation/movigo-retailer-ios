import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'login_screen.dart';

class OtpScreen extends StatefulWidget {
  final String? mobile;
  final String? prefillOtp;
  const OtpScreen({super.key, this.mobile, this.prefillOtp});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  TextEditingController otpController = TextEditingController();
  late final PinTheme defaultPinTheme;

  bool resendText = true;
  Timer? _timer;
  int _secondsRemaining = 120;

  @override
  void initState() {
    super.initState();
    startTimer();

    defaultPinTheme = PinTheme(
      margin: const EdgeInsets.only(left: 12),
      width: 81,
      height: 70,
      textStyle: const TextStyle(
        fontSize: 22,
        fontFamily: AppFont.fontFamily,
        fontWeight: FontWeight.w400,
        color: AppColor.primaryColor,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(9),
      ),
    );
  }

  String get timerText {
    final minutes = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _timer?.cancel();
    otpController.dispose();
    super.dispose();
  }

  void startTimer() {
    _timer?.cancel();
    setState(() {
      resendText = true;
      _secondsRemaining = 120;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          resendText = false;
          _timer?.cancel();
        }
      });
    });
  }

  forgotOtpUserValidation(String otp) async {
    if (otp.isEmpty) {
      SnackBarToastMessage.showSnackBar(
          context, AppLanguage.otpMessage[language]);
      return false;
    } else if (otp.length != 4) {
      SnackBarToastMessage.showSnackBar(
          context, AppLanguage.otpMinLenthMessage[language]);
      return false;
    } else {
      final apiProvider = Provider.of<PostApiProvider>(context, listen: false);
      apiProvider.otpVerificationApiCalling(
          context, otpController.text.trim(), widget.mobile ?? '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: size.width * 0.07),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // SizedBox(height: size.height * 0.08),
                  // Text(
                  //   AppLanguage.splashText[language],
                  //   style: const TextStyle(
                  //     color: AppColor.themeColor,
                  //     fontFamily: AppFont.fontFamily1,
                  //     fontWeight: FontWeight.w500,
                  //     fontSize: 32,
                  //   ),
                  // ),
                  // SizedBox(height: size.height * 0.04),

                  SizedBox(height: size.height * 0.03),

                  /// App Logo
                  Image.asset(
                    AppImage.applogo3,
                    height: size.width * 0.35,
                    width: size.width * 0.50,
                    fit: BoxFit.cover,
                  ),

                  SizedBox(height: size.height * 0.01),
                  Text(
                    AppLanguage.verifyText[language],
                    style: const TextStyle(
                      color: AppColor.blackColor,
                      fontFamily: AppFont.fontFamily,
                      fontWeight: FontWeight.w500,
                      fontSize: 24,
                    ),
                  ),
                  SizedBox(height: size.height * 0.012),
                  SizedBox(
                    width: size.width * 0.90,
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: const TextStyle(
                          color: AppColor.textColorTwo,
                          fontFamily: AppFont.fontFamily,
                          fontWeight: FontWeight.w400,
                          fontSize: 14.5,
                          height: 1.4,
                        ),
                        children: [
                          TextSpan(
                            text: AppLanguage.weSentText[language],
                          ),
                          TextSpan(
                            text: "+91-${widget.mobile ?? ''}",
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColor.blackColor,
                            ),
                          ),
                          TextSpan(
                            text: AppLanguage.toContinueText[language],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: size.height * 0.06),
                  SizedBox(
                    width: size.width * 0.95,
                    child: Pinput(
                      length: 4,
                      autofocus: false,
                      controller: otpController,
                      defaultPinTheme: defaultPinTheme,
                      focusedPinTheme: defaultPinTheme,
                      submittedPinTheme: defaultPinTheme,
                      keyboardType: TextInputType.number,
                      hapticFeedbackType: HapticFeedbackType.lightImpact,
                      cursor: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(bottom: 13),
                            width: 15,
                            height: 2,
                            color: AppColor.primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: size.height * 0.08),
                  Consumer<PostApiProvider>(
                    builder: (context, apiprovider, child) {
                      return apiprovider.loading
                          ? const CircularProgressIndicator(
                              color: AppColor.themeColor)
                          : AppButton(
                              text: AppLanguage.verifyContText[language],
                              onPress: () {
                                FocusScope.of(context).unfocus();
                                forgotOtpUserValidation(otpController.text);
                              },
                            );
                    },
                  ),
                  SizedBox(height: size.height * 0.06),
                  Consumer<PostApiProvider>(
                    builder: (context, apiprovider, child) {
                      return GestureDetector(
                        onTap: !resendText
                            ? () {
                                startTimer();
                                apiprovider.resendOtpApiCalling(
                                  context,
                                  widget.mobile ?? '',
                                );
                              }
                            : null,
                        child: Text(
                          resendText
                              ? timerText
                              : AppLanguage.resendOtpText[language],
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 14,
                            fontFamily: AppFont.fontFamily,
                            fontWeight: FontWeight.w500,
                            decoration: resendText
                                ? TextDecoration.none
                                : TextDecoration.underline,
                            decorationColor: Colors.red,
                          ),
                        ),
                      );
                    },
                  ),
                  SizedBox(height: size.height * 0.22),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LoginScreen(
                            mobile: widget.mobile,
                          ),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          AppLanguage.haveAnotherText[language],
                          style: const TextStyle(
                            color: AppColor.textColorTwo,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFamily: AppFont.fontFamily,
                          ),
                        ),
                        SizedBox(width: size.width * 0.01),
                        Text(
                          AppLanguage.changeText[language],
                          style: const TextStyle(
                            color: AppColor.primaryColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFamily: AppFont.fontFamily,
                            decoration: TextDecoration.underline,
                            decorationThickness: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: size.height * 0.03),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
