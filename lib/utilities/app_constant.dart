import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_color.dart';

int language = 0;

class AppConstant {
  // Razorpay key is supplied by backend order APIs from server .env.
  // Do not hardcode test/live keys in the mobile app.
  static String razorpayKey = "";

  // Fallback used by Rate App / Share App when the admin panel hasn't
  // configured a content_type 3/4/5 override — always opens something
  // instead of silently no-oping.
  static const String appPlayStoreUrl =
      'https://play.google.com/store/apps/details?id=com.app.movigocustomer';

  // iOS App Store listing for the Movigo Retailer app (App Store ID 6793887251).
  // Used on iOS wherever appPlayStoreUrl is used on Android.
  static const String appAppStoreUrl =
      'https://apps.apple.com/app/id6793887251';

  static String razorpayKeyFromOrder(Map<String, dynamic>? orderData) {
    if (orderData == null) return razorpayKey;
    final dynamic key = orderData["razorpay_key"] ?? orderData["key"] ?? orderData["key_id"];
    return key?.toString() ?? razorpayKey;
  }
  static String token = '';
  static double? currentLat;
  static double? currentLng;
  static const String apiBaseUrl = 'https://movigoinnovations.com/app/server/api/v1/app/';
  static String googleApiKey = "AIzaSyA9I1NRnopqt9CFYFseGb8wETrTtbaxaV0";

  // Server endpoints — change these if the server URL changes
  static const String serverBaseUrl  = 'https://movigoinnovations.com';
  static const String socketPath     = '/app/server/socket.io';

  static const int appStatus = 0;
  static String playerID = "123456";
  static var deviceType = Platform.isAndroid ? 'android' : 'ios';

  static const TextStyle appBarTitleStyle = TextStyle(
    fontSize: 22,
    color: AppColor.primaryColor,
    fontWeight: FontWeight.w600,
  );
  static final RegExp emailValidatorRegExp =
      RegExp(r"^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+");

  static const TextStyle textFieldStyle = TextStyle(
      color: AppColor.primaryColor, fontWeight: FontWeight.w500, fontSize: 14);
  static const TextStyle textFieldHintStyle = TextStyle(
      color: AppColor.textFieldColor,
      fontWeight: FontWeight.w500,
      fontSize: 14);
  // Defination of max length
  static const int emailMaxLength = 50;
  static const int passwordMaxLength = 16;
  static const int fullNameMaxLength = 50;
  static const int mobileMaxLenth = 10;
  static const int messageMaxLenth = 250;
  static const int firstandlastnameMaxLenth = 25;
  static const int referralcodeMaxLenth = 10;
  static const int searchMaxLenth = 100;
  static const int cardNumberMaxLength = 16;

  static const int textAreaMinline = 6;
  static const int textAreaLength = 300;

  static int selectedRole = 1;
  static int selectedFooterIndex = 1;

  static const TextStyle textFilledHeading =
      TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w500);
  static const SystemUiOverlayStyle systemUiOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );

  //Profile screen indexes
  static int profileTabIndex = 0;
  static int walletselectIndex = 0;
  static int hustleSelectIndex = 0;
}

class SuccessClass {
  final String title;
  final String message;

  SuccessClass({required this.title, required this.message});
}

class ContentClass {
  final String header;
  final String contenttype;

  ContentClass({required this.header, required this.contenttype});
}

enum BottomMenus { notification, home, profile }

///Movigo app userType manage for bottam navigation
enum UserType {
  individual,
  retailer, customer,
}
