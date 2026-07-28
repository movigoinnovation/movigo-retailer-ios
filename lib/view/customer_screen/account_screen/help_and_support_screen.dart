import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:movigo/Controller/helpline_controller.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';

import 'package:movigo/utilities/app_header.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/utilities/common_text_field.dart';

class HelpAndSupportscreen extends StatefulWidget {
  const HelpAndSupportscreen({super.key});

  @override
  State<HelpAndSupportscreen> createState() => _HelpAndSupportscreenState();
}

class _HelpAndSupportscreenState extends State<HelpAndSupportscreen> {
  /// CONTROLLERS
  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<HelplineController>(context, listen: false)
          .getHelplines(context);
    });
  }

  Future<void> _loadUserData() async {
    final userController = Provider.of<UserController>(context, listen: false);
    await userController.getUserDetails();

    if (!mounted) return;

    setState(() {
      fullNameController.text = userController.getUserName;
      emailController.text = userController.getUserEmail;
    });
  }

  Future<void> openDialPad(String phoneNumber) async {
    // Remove spaces and dashes etc.
    final String cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');

    final Uri uri = Uri.parse("tel:$cleanedNumber");

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

  bool helpSupportValidation(
      String fullName, String email, String description) {
    if (fullName.isEmpty) {
      SnackBarToastMessage.showSnackBar(
          context, AppLanguage.fullNameMessage[language]);
      return false;
    } else if (email.isEmpty) {
      SnackBarToastMessage.showSnackBar(
          context, AppLanguage.emailMessage[language]);
      return false;
    } else if (!AppConstant.emailValidatorRegExp.hasMatch(email)) {
      SnackBarToastMessage.showSnackBar(
          context, AppLanguage.emailValidMessage[language]);
      return false;
    } else if (description.isEmpty) {
      SnackBarToastMessage.showSnackBar(
          context, AppLanguage.descriptionMessage[language]);
      return false;
    }

    final apiprovider = Provider.of<PostApiProvider>(context, listen: false);
    apiprovider.contactUsApiCalling(
      context,
      fullNameController.text.trim(),
      emailController.text.trim(),
      descriptionController.text.trim(),
    );

    return true;
  }

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    super.dispose();
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
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: size.width * 0.04),
              child: CommonAppBar(
                title: AppLanguage.helpSupoortText[language],
                onBack: () => Navigator.of(context).maybePop(),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(height: size.height * 0.02),
                      _label(AppLanguage.fullNameText[language], size),
                      CommonTextField(
                        controller: fullNameController,
                        hintText: AppLanguage.enterFullNText[language],
                        readOnly: true,
                      ),
                      _gap(size),
                      _label(AppLanguage.emailText[language], size),
                      CommonTextField(
                        controller: emailController,
                        hintText: AppLanguage.enterEmailText[language],
                        keyboardType: TextInputType.emailAddress,
                        readOnly: true,
                      ),
                      _gap(size),
                      _label(AppLanguage.descriptionText[language], size),
                      CommonTextField(
                        controller: descriptionController,
                        hintText: AppLanguage.writeText[language],
                        isMultiline: true,
                        height: 0.15,
                      ),
                      SizedBox(height: size.height * 0.06),
                      Center(
                        child: Consumer<PostApiProvider>(
                          builder: (context, apiprovider, child) {
                            return apiprovider.loading
                                ? const CircularProgressIndicator(
                                    color: AppColor.themeColor)
                                : AppButton(
                                    text: AppLanguage.sendText[language],
                                    onPress: () {
                                      FocusScope.of(context).unfocus();
                                      helpSupportValidation(
                                        fullNameController.text.trim(),
                                        emailController.text.trim(),
                                        descriptionController.text.trim(),
                                      );
                                    },
                                  );
                          },
                        ),
                      ),
                      SizedBox(height: size.height * 0.015),
                      // ── WhatsApp support button ────────────────────────────
                      GestureDetector(
                        onTap: () async {
                          const whatsappNumber = '919203718008';
                          final message = Uri.encodeComponent('Hi Movigo Support, I need help with my account.');
                          final url = Uri.parse('https://wa.me/$whatsappNumber?text=$message');
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF25D366).withOpacity(0.4)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 20),
                              SizedBox(width: 8),
                              Text('Chat on WhatsApp',
                                  style: TextStyle(
                                      color: Color(0xFF25D366),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: size.height * 0.04),
                      Row(
                        children: [
                          const Expanded(child: Divider(thickness: 1.5)),
                          Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: size.width * 0.03),
                            child: const Text(
                              "Or call Us",
                              style: TextStyle(
                                fontFamily: AppFont.fontFamily,
                                fontSize: 14,
                                color: AppColor.textColorTwo,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider(thickness: 1.5)),
                        ],
                      ),
                      SizedBox(height: size.height * 0.03),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(size.width * 0.04),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColor.greyColor),
                          color: AppColor.greygreyColor,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            /// TITLE
                            Row(
                              children: [
                                Container(
                                  // height: size.height * 0.04,
                                  // width: size.height * 0.04,
                                  child: Image.asset(AppImage.callhelper1,
                                      height: 35, width: 35),
                                ),
                                SizedBox(width: size.width * 0.03),
                                const Text(
                                  "Helpline Numbers",
                                  style: TextStyle(
                                    fontFamily: AppFont.fontFamily,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColor.blackColor,
                                  ),
                                ),
                              ],
                            ),

                            SizedBox(height: size.height * 0.008),

                            const Text(
                              "Select a number to call",
                              style: TextStyle(
                                  fontFamily: AppFont.fontFamily,
                                  fontSize: 12,
                                  color: AppColor.textColorTwo,
                                  fontWeight: FontWeight.w400),
                            ),

                            SizedBox(height: size.height * 0.02),

                            /// NUMBERS LIST
                            Consumer<HelplineController>(
                              builder: (context, controller, _) {
                                if (controller.isLoading) {
                                  return const Center(
                                    child: CircularProgressIndicator(
                                        color: AppColor.themeColor),
                                  );
                                }

                                if (controller.helplineList.isEmpty) {
                                  return const Center(
                                    child:
                                        Text("No helpline numbers available"),
                                  );
                                }

                                return Column(
                                  children: controller.helplineList.map((item) {
                                    final String title =
                                        item['helpline_label']?.toString() ??
                                            'Support';

                                    final String number =
                                        item['helpline_number']?.toString() ??
                                            '';

                                    return InkWell(
                                      onTap: () {
                                        if (number.isNotEmpty) {
                                          openDialPad(number); // 📞 CALL
                                        } else {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text(
                                                    "Number not available")),
                                          );
                                        }
                                      },
                                      child: Container(
                                        margin: EdgeInsets.only(
                                            bottom: size.height * 0.015),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: size.width * 0.04,
                                          vertical: size.height * 0.018,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color: AppColor.greyColor),
                                          color: AppColor.secondaryColor,
                                        ),
                                        child: Row(
                                          children: [
                                            Image.asset(
                                              AppImage.callhelper2,
                                              height: 40,
                                              width: 40,
                                            ),
                                            SizedBox(width: size.width * 0.04),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  title,
                                                  style: const TextStyle(
                                                    fontFamily:
                                                        AppFont.fontFamily,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColor.blackColor,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  number,
                                                  style: const TextStyle(
                                                    fontFamily:
                                                        AppFont.fontFamily,
                                                    fontSize: 14,
                                                    color: AppColor.themeColor,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: size.height * 0.10),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gap(Size size) => SizedBox(height: size.height * 0.025);

  Widget _label(String text, Size size) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: size.height * 0.008),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            fontFamily: AppFont.fontFamily,
            color: AppColor.nineTextColor,
          ),
        ),
      ),
    );
  }

//
}
