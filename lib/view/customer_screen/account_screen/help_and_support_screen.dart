import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:movigo/Controller/helpline_controller.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';

import 'package:movigo/utilities/app_header.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';

class HelpAndSupportscreen extends StatefulWidget {
  const HelpAndSupportscreen({super.key});

  @override
  State<HelpAndSupportscreen> createState() => _HelpAndSupportscreenState();
}

class _HelpAndSupportscreenState extends State<HelpAndSupportscreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<HelplineController>(context, listen: false)
          .getHelplines(context);
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
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
    );
  }
}
