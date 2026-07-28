import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:provider/provider.dart';

import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/contentService.dart';
import 'package:movigo/helper/contentScreen.dart';
import 'package:movigo/helper/custom_input_field.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';

class LoginScreen extends StatefulWidget {
  final String? mobile;
  /// Pass 'Customer' or 'Retailer' so login sends the correct user_type.
  /// Defaults to empty string — backend fallback order: Customer→Retailer→Driver.
  final String userType;
  const LoginScreen({super.key, this.mobile, this.userType = ''});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController mobileController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isTermsAccepted = true; // Auto-accepted — user can read T&C via link
  String termsandconditionstype = '';

  @override
  void initState() {
    super.initState();
    loadContentData();

    if (widget.mobile != null) {
      mobileController.text = widget.mobile!;
    }
  }

  void loadContentData() {
    fetchAllContent((List data) {
      for (var item in data) {
        if (item['content_type'] == 2) {
          termsandconditionstype = item['content_url'];
        }
      }
      setState(() {});
    });
  }

  signInUserValidation(String mobileNumber) async {
    print("mobileNumber $mobileNumber");
    if (mobileNumber.isEmpty) {
      SnackBarToastMessage.showSnackBar(
          context, AppLanguage.mobileNumberMessage[language]);
      return false;
    } else if (mobileNumber.length != 10) {
      SnackBarToastMessage.showSnackBar(
          context, AppLanguage.mobilevalidMessage[language]);
      return false;
    } else if (!_isTermsAccepted) {
      SnackBarToastMessage.showSnackBar(
          context, AppLanguage.termsconditionMessage[language]);
      return false;
    } else {
      final apiProvider = Provider.of<PostApiProvider>(context, listen: false);
      apiProvider.loginUserApiCall(context, mobileController.text, userType: widget.userType);
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

    return PopScope(
      canPop: false,
      child: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.07),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(height: size.height * 0.03),

                      /// App Logo
                      Image.asset(
                        AppImage.applogo3,
                        height: size.width * 0.35,
                        width: size.width * 0.50,
                        fit: BoxFit.cover,
                      ),

                      SizedBox(height: size.height * 0.01),

                      /// TITLE
                      Text(
                        AppLanguage.letsText[language],
                        style: const TextStyle(
                          color: AppColor.blackColor,
                          fontFamily: AppFont.fontFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: 24,
                        ),
                      ),

                      SizedBox(height: size.height * 0.012),

                      /// SUBTITLE
                      Text(
                        AppLanguage.singText[language],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColor.textColorTwo,
                          fontFamily: AppFont.fontFamily,
                          fontWeight: FontWeight.w400,
                          fontSize: 16,
                          height: 1.4,
                        ),
                      ),

                      SizedBox(height: size.height * 0.06),

                      CustomInputField(
                        controller: mobileController,
                        hintText: AppLanguage.hintMobText[language],
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        prefixText: '+91',
                      ),
                      SizedBox(height: size.height * 0.03),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          /// ✅ CUSTOM SIZE + BORDER COLOR + BORDER WIDTH
                          Center(
                            child: Transform.scale(
                              scale: 1.2,
                              child: Center(
                                child: Checkbox(
                                  value: _isTermsAccepted,
                                  activeColor: AppColor
                                      .primaryColor, // tick + fill color
                                  checkColor: Colors.white, // tick color

                                  /// 🔥 BORDER CONTROL
                                  side: const BorderSide(
                                    color: AppColor
                                        .textColorTwo, // box border color
                                    width: 0.5, // box border
                                  ),

                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: const VisualDensity(
                                    horizontal: VisualDensity.minimumDensity,
                                    vertical: VisualDensity.minimumDensity,
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      _isTermsAccepted = value ?? false;
                                    });
                                  },
                                ),
                              ),
                            ),
                          ),

                          SizedBox(width: size.width * 0.045),

                          /// TEXT
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isTermsAccepted = true;
                                });
                              },
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(
                                    fontFamily: AppFont.fontFamily,
                                    fontSize: 12,
                                    color: AppColor.textColorTwo,
                                  ),
                                  children: [
                                    const TextSpan(
                                      text: "By logging in, you agree to our ",
                                    ),
                                    TextSpan(
                                      text: "Terms & Conditions",
                                      style: const TextStyle(
                                        color: AppColor.primaryColor,
                                        fontWeight: FontWeight.w500,
                                        decoration: TextDecoration.underline,
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () {
                                          debugPrint(
                                              "Terms & Conditions clicked");
                                          if (termsandconditionstype.isEmpty)
                                            return;

                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => ContentScreen(
                                                contenttype:
                                                    termsandconditionstype,
                                                header: "Terms & Conditions",
                                              ),
                                            ),
                                          );
                                        },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: size.height * 0.08),

                      Consumer<PostApiProvider>(
                        builder: (context, apiprovider, child) {
                          return apiprovider.loading
                              ? const CircularProgressIndicator(
                                  color: AppColor.themeColor)
                              : AppButton(
                                  text: AppLanguage.sendOtpText[language],
                                  onPress: () {
                                    FocusScope.of(context).unfocus();
                                    signInUserValidation(
                                      mobileController.text.trim(),
                                    );
                                  },
                                );
                        },
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
  }
}
