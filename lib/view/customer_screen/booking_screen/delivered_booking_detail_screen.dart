import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/get_navigation.dart';

import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_header.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';

import 'chat_screen.dart';

class DeliveredBookingDetailScreen extends StatefulWidget {
  const DeliveredBookingDetailScreen({super.key});

  @override
  State<DeliveredBookingDetailScreen> createState() =>
      _DeliveredBookingDetailScreenState();
}

class _DeliveredBookingDetailScreenState
    extends State<DeliveredBookingDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
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
                    title: AppLanguage.bookingdText[language],
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
                        AppLanguage.deliveredText[language],
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFamily: AppFont.fontFamily,
                            color: AppColor.successCOlor),
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
                        AppLanguage.bookingIdText[language],
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: AppFont.fontFamily,
                            color: AppColor.fourTextColor),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            AppLanguage.octText[language],
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                fontFamily: AppFont.fontFamily,
                                color: AppColor.secondTextColor),
                          ),
                          Text(
                            AppLanguage.timeTextt[language],
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
                          SizedBox(
                            height: size.height * 0.04,
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
                              AppLanguage.prestonText[language],
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                fontFamily: AppFont.fontFamily,
                                color: AppColor.selectTpeColor,
                              ),
                            ),
                            SizedBox(
                              height: size.height * 0.03,
                            ),
                            Text(
                              AppLanguage.thorText[language],
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
                        child: Image.asset(
                          AppImage.profiletwo, // driver profile image
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
                              AppLanguage.jaxsonText[language],
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
                                  AppLanguage.minitText[language],
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
                                Container(
                                  height: size.height * 0.055,
                                  width: size.width * 0.32,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: AppColor.primaryColor,
                                      width: 1,
                                    ),
                                  ),
                                  child: InkWell(
                                    onTap: () {},
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Image.asset(
                                          AppImage.calltwo,
                                          height: 20,
                                          width: 20,
                                        ),
                                        SizedBox(width: size.width * 0.02),
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
                                SizedBox(width: size.width * 0.03),
                                Container(
                                  height: size.height * 0.055,
                                  width: size.width * 0.32,
                                  decoration: BoxDecoration(
                                    color: AppColor.successCOlor,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: InkWell(
                                    onTap: () {
                                      Get.to(() => ChatScreen(
                                        bookingId: '',
                                        otherUserId: '',
                                        userId: '',
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
                                        SizedBox(width: size.width * 0.02),
                                        Text(
                                          AppLanguage.messageText[language],
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: AppFont.fontFamily,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  /// CALL & MESSAGE BUTTONS

                  SizedBox(height: size.height * 0.035),

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
                    height: size.height * 0.16,
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
                    height: size.height * 0.04,
                  ),

                  Container(
                    width: size.width,
                    height: size.height * 0.19,
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
                            height: size.height * 0.015,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                AppLanguage.baseText[language],
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: AppFont.fontFamily,
                                    color: AppColor.thirdTextColor),
                              ),
                              Text(
                                AppLanguage.baseTextPirce[language],
                                style: TextStyle(
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                AppLanguage.distanceText[language],
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: AppFont.fontFamily,
                                    color: AppColor.thirdTextColor),
                              ),
                              Text(
                                AppLanguage.distancePriceText[language],
                                style: TextStyle(
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                AppLanguage.helperChText[language],
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: AppFont.fontFamily,
                                    color: AppColor.thirdTextColor),
                              ),
                              Text(
                                AppLanguage.helperChPriceText[language],
                                style: TextStyle(
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
                                AppLanguage.totalPriceText[language],
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
                    height: size.height * 0.03,
                  ),

                  Container(
                    height: 53,
                    width: size.width * 0.4,
                    decoration: BoxDecoration(
                      color: Color(0xff2AB0FC),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: InkWell(
                      onTap: () {
                        // message action
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
                            style: TextStyle(
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
                    height: size.height * 0.15,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
