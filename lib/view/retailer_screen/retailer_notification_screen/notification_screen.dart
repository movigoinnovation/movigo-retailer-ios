import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';

class RNotificationScreen extends StatefulWidget {
  const RNotificationScreen({super.key});

  @override
  State<RNotificationScreen> createState() => _RNotificationScreenState();
}

class _RNotificationScreenState extends State<RNotificationScreen> {
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
                AppLanguage.notificationText[language],
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppFont.fontFamily,
                  color: AppColor.blackColor,
                ),
              ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(
              right: size.width * 0.04,
              top: size.height * 0.02,
            ),
            child: InkWell(
              onTap: () {

              },
              child: Text(
                AppLanguage.clearText[language],
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  fontFamily: AppFont.fontFamily,
                  color: AppColor.selectTpeColor,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),

      body: ListView.builder(
        padding: EdgeInsets.symmetric(
          horizontal: size.width * 0.06,
          vertical: size.height * 0.02,
        ),
        itemCount: notifications.length,
        itemBuilder: (context, index) {
          final item = notifications[index];
          return _notificationTile(
            context,
            icon: item['icon'].toString(),
            title: item['title'].toString(),
            description: item['description'].toString(),
            time: item['time'].toString(),
            showDelete: item['delete'] as bool,
          );
        },
      ),
    );
  }

  /// ================= NOTIFICATION TILE =================
  Widget _notificationTile(
      BuildContext context, {
        required String icon,
        required String title,
        required String description,
        required String time,
        required bool showDelete,
      }) {
    final size = MediaQuery.of(context).size;

    return Container(
      margin: EdgeInsets.only(bottom: size.height * 0.02),
      padding: EdgeInsets.symmetric(
        vertical: size.height * 0.015,
      ),
      decoration: const BoxDecoration(
        color: AppColor.whiteColor,
        // border: Border(
        //   bottom: BorderSide(
        //     color: Color(0xffE5E5E5),
        //     width: 1,
        //   ),
        // ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Padding(
            padding:  EdgeInsets.only(top: size.height * 0.01 ),
            child: Image.asset(
              icon,
              height: size.height * 0.032,
              width: size.height * 0.032,
            ),
          ),

          SizedBox(width: size.width * 0.04),


          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: AppFont.fontFamily,
                    color: AppColor.thirdTextColor,
                  ),
                ),
                // SizedBox(height: size.height * 0.006),
                // Text(
                //   description,
                //   style: TextStyle(
                //     fontSize: 12,
                //     fontWeight: FontWeight.w500,
                //     fontFamily: AppFont.fontFamily,
                //     color: AppColor.eigthColor,
                //   ),
                // ),
                SizedBox(height: size.height * 0.006),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: AppFont.fontFamily,
                    fontWeight: FontWeight.w500,

                    color: AppColor.eigthColor,
                  ),
                ),
              ],
            ),
          ),


          if (showDelete)
            Padding(
              padding: EdgeInsets.only(left: size.width * 0.02),
              child: Image.asset(
                AppImage.deletered,
                height: size.height * 0.03,
              ),
             ),
        ],
      ),
    );
  }

  /// ================= DATA =================
  final notifications = [
    {
      "icon": AppImage.notigreen,
      "title": "Your item has been delivered successfully.",
      "description": "",
      "time": "25 Jan, 2025 â€¢ 09:18 AM",
      "delete": false,
    },
    {
      "icon": AppImage.notigreen,
      "title": "Your booking has been cancelled successfully.",
      "description": "",
      "time": "25 Jan, 2025 â€¢ 09:18 AM",
      "delete": false,
    },
    {
      "icon": AppImage.notigreen,
      "title": "Refund completed.",
      "description": "Amount added to your wallet.",
      "time": "25 Jan, 2025 â€¢ 09:18 AM",
      "delete": true,
    },
    {
      "icon": AppImage.notigreen,
      "title": "Payment failed.",
      "description": "Please try again.",
      "time": "25 Jan, 2025 â€¢ 09:18 AM",
      "delete": false,
    },
    {
      "icon": AppImage.notigreen,
      "title": "Your captain is on the way to the pickup location.",
      "description": "",
      "time": "25 Jan, 2025 â€¢ 09:18 AM",
      "delete": false,
    },
    {
      "icon": AppImage.notigreen,
      "title": "A coupon has been assigned to your account.",
      "description": "",
      "time": "25 Jan, 2025 â€¢ 09:18 AM",
      "delete": false,
    },
    {
      "icon": AppImage.notigreen,
      "title": "Welcome!",
      "description": "You have logged in successfully.",
      "time": "25 Jan, 2025 â€¢ 09:18 AM",
      "delete": false,
    },
  ];
}
