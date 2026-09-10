// ignore_for_file: avoid_print, use_build_context_synchronously
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:movigo/view/customer_screen/onboarding/signup_screen.dart';
import 'package:provider/provider.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/fcm_token_service.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/view/customer_screen/onboarding/login_screen.dart';
import 'package:movigo/view/customer_screen/onboarding/otp_screen.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';
import 'package:movigo/Provider/common_api_helper/common_shared_prefrences.dart';
import 'package:movigo/Provider/socket_connection/socket_provider.dart';
import 'package:movigo/Provider/user_controller.dart';

class PostApiProvider with ChangeNotifier {
  String? bookingId;
  String? _lastErrorMessage;

  bool _loading = false;
  bool _secondaryLoading = false;
  bool get loading => _loading;
  bool get secondaryLoading => _secondaryLoading;
  String? get lastErrorMessage => _lastErrorMessage;

  String? _extractMessage(dynamic message) {
    if (message is List && message.isNotEmpty) {
      return message[0].toString();
    }
    if (message is String) return message;
    if (message is Map && message.isNotEmpty) {
      return message.values.first.toString();
    }
    return null;
  }

  void setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }

  void setSecondaryLoading(bool value) {
    _secondaryLoading = value;
    notifyListeners();
  }

  // Returns OTP string only if it's a valid 4-digit number, else null
  String? _isValidOtp(dynamic data) {
    if (data == null) return null;
    final s = data.toString().trim();
    if (RegExp(r'^\d{4}$').hasMatch(s)) return s;
    return null;
  }

  // ============= Login Api ================= //
  loginUserApiCall(BuildContext context, String number, {String userType = ''}) async {
    setLoading(true);

    // Use explicit userType if provided; otherwise fall back to cached value
    String resolvedUserType = 'Retailer'; // backend-controlled split app: force Retailer mode
    if (resolvedUserType.isEmpty) {
      try {
        final raw = await CacheHelper.get('user_details');
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          resolvedUserType = (decoded['user_type'] ?? '').toString();
        }
      } catch (_) {}
    }
    Map<String, String> fields = {
      'phone_number': number.toString(),
      'player_id': AppConstant.playerID.toString(),
      'device_type': AppConstant.deviceType,
    };
    if (resolvedUserType.isNotEmpty) fields['user_type'] = resolvedUserType;
    log("LOGIN REQUEST => $fields");

    final res = await postJsonData('auth/login', fields, context);

    if (res != null) {
      if (res['success'] == true) {
        // OTP sent — navigate to OTP screen
        final msg = res['message'];
        if (msg is List && msg.isNotEmpty) {
          SnackBarToastMessage.showSnackBar(context, msg[0].toString());
        } else if (msg is String) {
          SnackBarToastMessage.showSnackBar(context, msg);
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OtpScreen(
              mobile: number,
              prefillOtp: _isValidOtp(res['data']),
            ),
          ),
        );
      } else {
        // Show backend error message
        final msg = res['message'];
        if (msg is List && msg.isNotEmpty) {
          SnackBarToastMessage.showSnackBar(context, msg[0].toString());
        } else if (msg is String) {
          SnackBarToastMessage.showSnackBar(context, msg);
        }
      }
    }
    setLoading(false);
  }

  // ============= Otp Verification ============= //
  Future<void> otpVerificationApiCalling(
    BuildContext context,
    String otp,
    String mobile,
  ) async {
    setLoading(true);

    final Map<String, dynamic> fields = {
      'phone_number': mobile,
      'otp': otp,
      'user_type': 'Retailer',
    };
    // Attach cached user_type so backend finds the correct user collection
    try {
      final raw = await CacheHelper.get("user_details");
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final ut = (decoded["user_type"] ?? "").toString();
        if (ut.isNotEmpty) fields["user_type"] = ut;
      }
    } catch (_) {}

    log("OTP VERIFY REQUEST");

    final res = await postJsonData('auth/otp_verify', fields, context);

    if (!context.mounted) return;

    setLoading(false);

    if (res == null) return;

    if (res['success'] == true && res['data'] != "NA") {
      final data = res['data'];
      log("OTP VERIFY SUCCESS");

      /// ✅ Save token
      AppConstant.token = data['token'];
      log("Token stored successfully");
      FcmTokenService.updateTokenAfterLogin(); // FIX: ensure backend has latest FCM token
      final socketProvider =
          Provider.of<SocketProvider>(context, listen: false);
      socketProvider.initSocket(AppConstant.token);
      await CacheHelper.save("user_details", jsonEncode(data));

      /// ✅ Show message
      if (res['message'] is List && res['message'].isNotEmpty) {
        SnackBarToastMessage.showSnackBar(
          context,
          res['message'][0].toString(),
        );
      }

      /// ✅ Read flags
      final bool isProfileCompleted = data['is_profile_completed'] == true;

      log("PROFILE completion flag resolved");

      /// ================= NAVIGATION LOGIC =================

      if (isProfileCompleted) {
        /// 🔹 Profile already completed → Go to Home (BottomNav)
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => const CustomBottomNav(
              userType: UserType.retailer,
              initialIndex: 0,
            ),
          ),
          (route) => false,
        );
      } else {
        /// 🔹 Profile NOT completed → Go to Signup Screen

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SignupScreen(
              mobile: mobile,
            ),
          ),
        );
      }
    }
  }

  //=============== Resend OTP API =================//
  Future<void> resendOtpApiCalling(
    BuildContext context,
    String mobile,
  ) async {
    setSecondaryLoading(true);

    final Map<String, dynamic> fields = {
      'phone_number': mobile,
    };
    // Attach cached user_type so resend OTP hits the correct collection
    try {
      final raw = await CacheHelper.get("user_details");
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final ut = (decoded["user_type"] ?? "").toString();
        if (ut.isNotEmpty) fields["user_type"] = ut;
      }
    } catch (_) {}

    log("RESEND OTP REQUEST");

    final res = await postJsonData(
      'auth/resend_otp',
      fields,
      context,
    );

    setSecondaryLoading(false);

    if (res == null) return;

    if (res['success'] == true) {
      /// ✅ Show message safely
      if (res['message'] is List && res['message'].isNotEmpty) {
        SnackBarToastMessage.showSnackBar(
          context,
          res['message'][0].toString(),
        );
      }
      log("Resend OTP success");
    }
  }


  // ── Create Razorpay order for booking (2% processing fee) ──────────────────
  Future<Map<String, dynamic>?> createBookingPaymentOrder(
    BuildContext context, {
    required int baseFare,
  }) async {
    setLoading(true);
    final res = await postJsonData(
      'wallet/create_booking_payment_order',
      {'booking_fare': baseFare},
      context,
    );
    setLoading(false);
    if (res != null && res['success'] == true) return res['data'];
    return null;
  }

  // ================= CUSTOMER SIGNUP ================= //
  Future<bool> customerSignupApi(
    BuildContext context, {
    required String fullName,
    required String email,
    required String phoneNumber,
    XFile? profileImage,
  }) async {
    setLoading(true);

    log("TOKEN USED IN SIGNUP => ${AppConstant.token}");

    final Map<String, String> fields = {
      'user_type': 'Customer',
      'full_name': fullName,
      'email': email,
      'phone_number': phoneNumber,
      'player_id': AppConstant.playerID.toString(),
      'device_type': AppConstant.deviceType,
    };

    Map<String, XFile>? files;
    if (profileImage != null) {
      files = {'profile_image': profileImage};
    }

    final res = await postMultipartData(
      'auth/signup',
      fields,
      context,
      headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
        'Accept': 'application/json',
      },
      files: files,
    );

    setLoading(false);

    if (res == null) return false;

    if (res['success'] == true && res['data'] != null) {
      final data = res['data'];

      AppConstant.token = data['token'];
      await CacheHelper.save("user_details", jsonEncode(data));
      final socketProvider =
          Provider.of<SocketProvider>(context, listen: false);
      socketProvider.initSocket(AppConstant.token);

      SnackBarToastMessage.showSnackBar(
        context,
        res['message'][0].toString(),
      );

      return true;
    }

    return false;
  }

  // ================= UPDATE BUSINESS PROFILE ================= //
  Future<bool> updateBusinessProfileApi(
    BuildContext context, {
    required Map<String, String> fields,
  }) async {
    setLoading(true);
    final res = await postMultipartData(
      'user/update_business_profile',
      fields,
      context,
      headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
        'Accept': 'application/json',
      },
    );
    setLoading(false);
    if (res == null) return false;
    if (res['success'] == true && res['data'] != null) {
      await CacheHelper.save('user_details', jsonEncode(res['data']));
      return true;
    }
    return false;
  }

  // ================= RETAILER SIGNUP ================= //
  // ── Field officers (public list for the "who helped you download the app?"
  // picker on the signup screen). Returns [] on any failure — it is optional.
  Future<List<Map<String, dynamic>>> fetchFieldOfficersApi(
      BuildContext context) async {
    try {
      final res = await getData('auth/field-officers', context);
      if (res != null && res['success'] == true && res['data'] is List) {
        return (res['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> retailerSignupApi(
    BuildContext context, {
    required String businessName,
    required String retailerName,
    required String description,
    required String email,
    required String phoneNumber,
    required String address,
    required String landmark,
    XFile? profileImage,
    String? onboardedByOfficerId,
  }) async {
    setLoading(true);

    final Map<String, String> fields = {
      'user_type': 'Retailer',
      'full_name': retailerName, // retailer name
      'business_name': businessName,
      'description': description,
      'email': email,
      'phone_number': phoneNumber,
      'address': address,
      'landmark': landmark,
      'player_id': AppConstant.playerID.toString(),
      'device_type': AppConstant.deviceType,
    };

    if (onboardedByOfficerId != null && onboardedByOfficerId.isNotEmpty) {
      fields['onboarded_by_officer_id'] = onboardedByOfficerId;
    }

    Map<String, XFile>? files;
    if (profileImage != null) {
      files = {'profile_image': profileImage};
    }

    final res = await postMultipartData(
      'auth/signup',
      fields,
      context,
      headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
        'Accept': 'application/json',
      },
      files: files,
    );

    setLoading(false);

    if (res == null) return false;

    if (res['success'] == true && res['data'] != null) {
      final data = res['data'];

      AppConstant.token = data['token'];
      await CacheHelper.save("user_details", jsonEncode(data));
      final socketProvider =
          Provider.of<SocketProvider>(context, listen: false);
      socketProvider.initSocket(AppConstant.token);

      SnackBarToastMessage.showSnackBar(
        context,
        res['message'][0].toString(),
      );

      return true;
    }

    return false;
  }

  //============ contact us api===========//
  contactUsApiCalling(
    BuildContext context,
    String name,
    String email,
    String message,
  ) async {
    setLoading(true);

    final Map<String, String> fields = {
      'full_name': name.toString(),
      'email': email.toString(),
      'message': message.toString(),
    };

    if (kDebugMode) print("Line 105 $fields");

    final res = await postJsonData(
      'contact/create',
      fields,
      context,
      headers: {
        'authorization': 'Bearer ${AppConstant.token}',
      },
    );

    if (res != null) {
      if (!context.mounted) return;

      setLoading(false);

      if (res['success'] == true) {
        SnackBarToastMessage.showSnackBar(context, res['message'][language]);
      }

      Navigator.pop(
        context,
      );
    }

    setLoading(false);
  }

  //============ Booking Help & Support API ============//
  Future<bool> bookingHelpSupportApiCalling(
    BuildContext context, {
    required String description,
    required String bookingId,
    required String bookingCode,
  }) async {
    setLoading(true);

    final Map<String, dynamic> body = {
      "description": description,
      "booking_id": bookingId,
      "booking_code": bookingCode,
    };

    log("BOOKING HELP SUPPORT BODY => $body");

    final res = await postJsonData(
      'contact/create_booking_support',
      body,
      context,
      headers: {
        'authorization': 'Bearer ${AppConstant.token}',
        'Accept': 'application/json',
      },
    );

    setLoading(false);

    if (res == null) return false;

    if (res['success'] == true) {
      // ✅ Show success message
      if (res['message'] is List && res['message'].isNotEmpty) {
        SnackBarToastMessage.showSnackBar(
          context,
          res['message'][0].toString(),
        );
      }

      log("BOOKING SUPPORT DATA => ${res['data']}");
      return true;
    }

    // ❌ Error case
    final err = _extractMessage(res['message']);
    if (err != null) {
      SnackBarToastMessage.showSnackBar(context, err);
    }

    return false;
  }

  // ================= UPDATE CUSTOMER PROFILE ================= //
  Future<bool> updateCustomerProfileApi(
    BuildContext context, {
    required String fullName,
    required String email,
    required String phoneNumber,
    XFile? profileImage,
  }) async {
    setLoading(true);

    final Map<String, String> fields = {
      'user_type': 'Customer',
      'full_name': fullName,
      'email': email,
      'phone_number': phoneNumber,
    };

    Map<String, XFile>? files;
    if (profileImage != null) {
      files = {
        'profile_image': profileImage,
      };
    }

    log("UPDATE CUSTOMER PROFILE FIELDS => $fields");
    log("UPDATE CUSTOMER PROFILE FILES => ${files?.keys}");

    final res = await postMultipartData(
      'user/customer_update_profile',
      fields,
      context,
      headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
        'Accept': 'application/json',
      },
      files: files,
    );

    setLoading(false);

    if (res == null) return false;

    if (res['success'] == true) {
      /// ✅ Save updated user data
      if (res['data'] != null) {
        await CacheHelper.save(
          "user_details",
          jsonEncode(res['data']),
        );

        /// Update token if API sends new token
        if (res['data']['token'] != null) {
          AppConstant.token = res['data']['token'];
        }
      }

      /// ✅ Show success message
      if (res['message'] is List && res['message'].isNotEmpty) {
        SnackBarToastMessage.showSnackBar(
          context,
          res['message'][0].toString(),
        );
      }

      return true;
    }

    return false;
  }

  // ================= UPDATE RETAILER PROFILE ================= //
  Future<bool> updateRetailerProfileApi(
    BuildContext context, {
    required String businessName,
    required String fullName,
    required String email,
    required String phoneNumber,
    required String address,
    required String landmark,
    required String description,
    XFile? profileImage,
  }) async {
    setLoading(true);

    final Map<String, String> fields = {
      'user_type': 'Retailer',
      'business_name': businessName,
      'full_name': fullName,
      'email': email,
      'phone_number': phoneNumber,
      'address': address,
      'landmark': landmark,
      'description': description,
    };

    Map<String, XFile>? files;
    if (profileImage != null) {
      files = {'profile_image': profileImage};
    }

    final res = await postMultipartData(
      'user/customer_update_profile',
      fields,
      context,
      headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
        'Accept': 'application/json',
      },
      files: files,
    );

    setLoading(false);

    if (res == null) return false;

    if (res['success'] == true) {
      if (res['data'] != null) {
        await CacheHelper.save("user_details", jsonEncode(res['data']));

        if (res['data']['token'] != null) {
          AppConstant.token = res['data']['token'];
        }
      }

      if (res['message'] is List && res['message'].isNotEmpty) {
        SnackBarToastMessage.showSnackBar(
          context,
          res['message'][0].toString(),
        );
      }

      return true;
    }

    return false;
  }

  //============ delete account api===========//
  deleteAccountApiCalling(
    BuildContext context,
    String message,
  ) async {
    setLoading(true);

    final Map<String, String> fields = {
      'reason': message.toString(),
    };

    if (kDebugMode) print("Line 105 $fields");

    final res = await postJsonData(
      'user/delete_account',
      fields,
      context,
      headers: {
        'authorization': 'Bearer ${AppConstant.token}',
      },
    );

    if (res != null) {
      await CacheHelper.clearAll();
      AppConstant.token = '';
      AppConstant.selectedFooterIndex = 0;
      AppContentCache().clear();
      final userController =
          Provider.of<UserController>(context, listen: false);
      await userController.clearUserData();

      if (!context.mounted) return;

      setLoading(false);

      if (res != null && res['success'] == true) {
        SnackBarToastMessage.showSnackBar(context, res['message'][language]);
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen()),
        (route) => false,
      );
    }

    setLoading(false);
  }

  // ================= CREATE BOOKING API CUSTOMER ================= //
  Future<bool> createBookingCustomerApi(
    BuildContext context, {
    required String vehicleTypeId,
    required String subVehicleTypeId,
    required String transactionId,
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String dropAddress,
    required double dropLat,
    required double dropLng,
    required String pickupDate,
    required String pickupShift,
    required String pickupSlot,
    required String itemCategoryId,
    required String paymentMode,
    required String bookingType,
    String helperDescription = "",
    String note = "",
    String receiverName = "",
    String receiverContact = "",
    bool needHelper = false,
    int totalHelpers = 0,
    List<XFile>? itemImages,
    String requestedVehicleName = '',
    String vehicleCategory = '',
    String pricingModifier = '1.0',
    String vehicleKey = '',
    String requiredTag = '',
    String displayVehicleName = '',
    String bookingFlow = '',
    double rawDistanceKm = 0,
    String senderName = '',
    String senderPhone = '',
    int coinsToApply = 0,
  }) async {
    setLoading(true);
    _lastErrorMessage = null;

    /// 🔹 Fields
    final Map<String, String> fields = {
      'booking_type': bookingType,
      'vehicleType_id': vehicleTypeId,
      'subVehicleType_id': subVehicleTypeId,
      'transaction_id': transactionId,
      'pickup_address': pickupAddress,
      'pickup_lat': pickupLat.toString(),
      'pickup_lng': pickupLng.toString(),
      'drop_address': dropAddress,
      'drop_lat': dropLat.toString(),
      'drop_lng': dropLng.toString(),
      'pickup_date': pickupDate,
      'pickup_shift': pickupShift,
      'pickup_slot': pickupSlot,
      'item_category_id': itemCategoryId,
      'note': note,
      'sender_name': senderName,
      'sender_phone': senderPhone,
      'receiver_name': receiverName,
      'receiver_phone': receiverContact,
      'need_helper': needHelper.toString(),
      'payment_mode': paymentMode,
      'helper_description': helperDescription,
      if (requestedVehicleName.isNotEmpty) 'requested_vehicle_name': requestedVehicleName,
      if (vehicleCategory.isNotEmpty) 'vehicle_category': vehicleCategory,
      if (pricingModifier.isNotEmpty) 'pricing_modifier': pricingModifier,
      if (vehicleKey.isNotEmpty) 'vehicle_key': vehicleKey,
      if (requiredTag.isNotEmpty) 'required_tag': requiredTag,
      if (displayVehicleName.isNotEmpty) 'display_vehicle_name': displayVehicleName,
      if (bookingFlow.isNotEmpty) 'booking_flow': bookingFlow,
      if (rawDistanceKm > 0) 'raw_distance_km': rawDistanceKm.toStringAsFixed(3),
      if (coinsToApply > 0) 'coins_to_apply': coinsToApply.toString(),
    };

    if (needHelper == true && totalHelpers > 0) {
      fields['total_helpers'] = totalHelpers.toString();
    }

    /// 🔹 Multiple Images
    // Map<String, XFile>? files;
    // if (itemImages != null && itemImages.isNotEmpty) {
    //   files = {};
    //   for (int i = 0; i < itemImages.length; i++) {
    //     files['item_images'] = itemImages[i];
    //   }
    // }

    log("CREATE BOOKING FIELDS => $fields");
    // log("CREATE BOOKING FILES => ${files?.keys}");

    final res = await postImageMultipartData(
      'booking/create',
      context,
      headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
        'Accept': 'application/json',
      },
      fields: fields,
      filesList: itemImages != null && itemImages.isNotEmpty
          ? {'item_images': itemImages}
          : null,
    );

    setLoading(false);

    if (res == null) return false;

    if (res['success'] == true) {
      _lastErrorMessage = null;

      /// ✅ Save booking id (guard against malformed/non-string _id so a
      /// bad response can't throw here and instead surfaces as a null
      /// bookingId that callers can detect and handle gracefully)
      bookingId = res['data']?['_id']?.toString();

      log("BOOKING ID SAVED => $bookingId");
      log("BOOKING DATA => ${res['data']}");

      /// ✅ Success Message
      if (res['message'] is List && res['message'].isNotEmpty) {
        SnackBarToastMessage.showSnackBar(
          context,
          res['message'][0].toString(),
        );
      }

      notifyListeners(); // optional but good

      return true;
    }

    _lastErrorMessage = _extractMessage(res['message']);
    final msg = (_lastErrorMessage ?? "").toLowerCase();
    return false;
  }

  // ================= CREATE BOOKING API Retailer ================= //
  Future<bool> createBookingRetailerApi(
    BuildContext context, {
    required String vehicleTypeId,
    required String subVehicleTypeId,
    required String transactionId,
    required String customerName,
    required String customerPhone,
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String dropAddress,
    required double dropLat,
    required double dropLng,
    required String pickupDate, // yyyy-MM-dd
    required String pickupShift,
    required String pickupSlot,
    required String itemCategoryId,
    required String paymentMode,
    required String bookingType,
    String note = "",
    String helperDescription = "",
    bool needHelper = false,
    int totalHelpers = 0,
    List<XFile>? itemImages,
    String requestedVehicleName = '',
    String vehicleCategory = '',
    String pricingModifier = '1.0',
    String vehicleKey = '',
    String requiredTag = '',
    String displayVehicleName = '',
    String bookingFlow = '',
    double rawDistanceKm = 0,
    String senderName = '',
    String senderPhone = '',
    String receiverName = '',
    String receiverPhone = '',
    bool isPriorityPickup = false,
  }) async {
    setLoading(true);
    _lastErrorMessage = null;

    /// 🔹 Fields
    final Map<String, String> fields = {
      'booking_type': bookingType,
      'vehicleType_id': vehicleTypeId,
      'subVehicleType_id': subVehicleTypeId,
      'transaction_id': transactionId,

      // ✅ Retailer / Sender
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'sender_name': senderName,
      'sender_phone': senderPhone,

      'pickup_address': pickupAddress,
      'pickup_lat': pickupLat.toString(),
      'pickup_lng': pickupLng.toString(),
      'drop_address': dropAddress,
      'drop_lat': dropLat.toString(),
      'drop_lng': dropLng.toString(),
      'pickup_date': pickupDate,
      'pickup_shift': pickupShift,
      'pickup_slot': pickupSlot,
      'item_category_id': itemCategoryId,
      'note': note,
      'need_helper': needHelper.toString(),
      'payment_mode': paymentMode, // "Online" | "Cash"
      'helper_description': helperDescription,
      if (requestedVehicleName.isNotEmpty) 'requested_vehicle_name': requestedVehicleName,
      if (vehicleCategory.isNotEmpty) 'vehicle_category': vehicleCategory,
      if (pricingModifier.isNotEmpty) 'pricing_modifier': pricingModifier,
      if (vehicleKey.isNotEmpty) 'vehicle_key': vehicleKey,
      if (requiredTag.isNotEmpty) 'required_tag': requiredTag,
      if (displayVehicleName.isNotEmpty) 'display_vehicle_name': displayVehicleName,
      if (bookingFlow.isNotEmpty) 'booking_flow': bookingFlow,
      if (rawDistanceKm > 0) 'raw_distance_km': rawDistanceKm.toStringAsFixed(3),
      // Receiver contact
      if (receiverName.isNotEmpty) 'receiver_name': receiverName,
      if (receiverPhone.isNotEmpty) 'receiver_phone': receiverPhone,
      if (isPriorityPickup) 'is_priority_pickup': 'true',
    };

    // 🔹 Condition: Helper
    if (needHelper == true && totalHelpers > 0) {
      fields['total_helpers'] = totalHelpers.toString();
    }

    log("CREATE RETAILER BOOKING FIELDS => $fields");

    final res = await postImageMultipartData(
      'booking/create',
      context,
      headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
        'Accept': 'application/json',
      },
      fields: fields,
      filesList: itemImages != null && itemImages.isNotEmpty
          ? {'item_images': itemImages}
          : null,
    );

    setLoading(false);

    if (res == null) return false;

    if (res['success'] == true) {
      _lastErrorMessage = null;

      /// ✅ Save booking id (guard against malformed/non-string _id so a
      /// bad response can't throw here and instead surfaces as a null
      /// bookingId that callers can detect and handle gracefully)
      bookingId = res['data']?['_id']?.toString();

      log("BOOKING ID SAVED => $bookingId");
      log("BOOKING DATA => ${res['data']}");

      /// ✅ Success Message
      if (res['message'] is List && res['message'].isNotEmpty) {
        SnackBarToastMessage.showSnackBar(
          context,
          res['message'][0].toString(),
        );
      }

      notifyListeners();
      return true;
    }

    _lastErrorMessage = _extractMessage(res['message']);
    final msg = (_lastErrorMessage ?? "").toLowerCase();
    return false;
  }

  // ================= PRICE ESTIMATE API ================= //
  Future<Map<String, dynamic>?> priceEstimateApi(
    BuildContext context, {
    required String vehicleTypeId,
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
    String requestedVehicleName = '',
    String vehicleKey = '',
    String requiredTag = '',
    double rawDistanceKm = 0,
  }) async {
    setLoading(true);

    final body = {
      "vehicleType_id": vehicleTypeId,
      "pickup_lat": pickupLat.toString(),
      "pickup_lng": pickupLng.toString(),
      "drop_lat": dropLat.toString(),
      "drop_lng": dropLng.toString(),
      if (requestedVehicleName.isNotEmpty) "requested_vehicle_name": requestedVehicleName,
      if (vehicleKey.isNotEmpty) "vehicle_key": vehicleKey,
      if (requiredTag.isNotEmpty) "required_tag": requiredTag,
      if (rawDistanceKm > 0) "raw_distance_km": rawDistanceKm.toStringAsFixed(3),
    };

    log("PRICE ESTIMATE BODY => $body");

    final res = await postJsonData(
      'booking/price_estimate',
      body,
      context,
      headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
      },
    );

    setLoading(false);

    if (res != null && res['success'] == true) {
      return res['data'];
    }

    return null;
  }

  // ================= ADD WALLET AMOUNT API ================= //
  Future<bool> addWalletAmountApi(
    BuildContext context, {
    required String amount,
  }) async {
    setLoading(true);

    /// 🔹 Body (JSON)
    final Map<String, dynamic> body = {
      "amount": amount,
    };

    log("ADD WALLET BODY => $body");

    final res = await postJsonData(
      'wallet/driver_add_money',
      body,
      context,
      headers: {
        'authorization': 'Bearer ${AppConstant.token}',
      },
    );

    setLoading(false);

    if (res == null) return false;

    if (res['success'] == true) {
      if (res['message'] is List && res['message'].isNotEmpty) {
        SnackBarToastMessage.showSnackBar(
          context,
          res['message'][language].toString(),
        );
      }

      final walletBalance = res['data']?['wallet_balance'];
      log("UPDATED WALLET BALANCE => $walletBalance");

      return true;
    }

    return false;
  }




  // ================= RAZORPAY WALLET: CREATE ORDER ================= //
  Future<Map<String, dynamic>?> createDepositOrder(
    BuildContext context, {
    required String amount,
  }) async {
    setLoading(true);
    final res = await postJsonData(
      'wallet/create_deposit_order',
      {'amount': amount},
      context,
      headers: {
        'authorization': 'Bearer ${AppConstant.token}',
        'Content-Type': 'application/json',
      },
    );
    setLoading(false);
    if (res != null && res['success'] == true) return res['data'] as Map<String, dynamic>?;
    return null;
  }

  // ================= RAZORPAY WALLET: VERIFY PAYMENT ================= //
  Future<bool> verifyDeposit(
    BuildContext context, {
    required String orderId,
    required String paymentId,
    required String signature,
    required String amount,
  }) async {
    setLoading(true);
    final res = await postJsonData(
      'wallet/verify_deposit',
      {
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
        'amount': amount,
      },
      context,
      headers: {
        'authorization': 'Bearer ${AppConstant.token}',
        'Content-Type': 'application/json',
      },
    );
    setLoading(false);
    if (res != null && res['success'] == true) {
      if (res['message'] is List && res['message'].isNotEmpty) {
        SnackBarToastMessage.showSnackBar(context, res['message'][0].toString());
      }
      return true;
    }
    return false;
  }

  // ================= ACTIVE DRIVER RIDE GUARD ================= //
  // Retailer may cancel any time up to the driver physically reaching the
  // pickup point — matches the backend's cancelByCustomer rule exactly
  // (blocks Arrived/Pickup/Ongoing/Delivered/Cancelled; allows Pending/Accepted).
  // Kept as a client-side pre-check purely for a nicer error message before
  // hitting the API — the backend is still the source of truth either way.
  bool _isNonCancellableBookingStatus(dynamic rawStatus) {
    final status = (rawStatus ?? '').toString().trim().toLowerCase();
    return status == 'arrived' ||
        status == 'pickup' ||
        status == 'ongoing' ||
        status == 'delivered' ||
        status == 'completed' ||
        status == 'complete' ||
        status == 'cancelled' ||
        status == 'canceled' ||
        status == 'rejected';
  }

  Future<bool> _canCustomerCancelBooking(
    BuildContext context, {
    required String bookingId,
  }) async {
    final response = await getData(
      'booking/$bookingId',
      context,
      headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
        'Accept': 'application/json',
      },
    );

    final data = response?['data'];
    if (response?['success'] != true || data is! Map) {
      // Do not hard-block if detail API is temporarily unavailable. Backend still validates.
      return true;
    }

    final bookingData = Map<String, dynamic>.from(data);
    final status = bookingData['booking_status'] ?? bookingData['status'];

    if (_isNonCancellableBookingStatus(status)) {
      SnackBarToastMessage.showSnackBar(
        context,
        'Your driver has already reached the pickup point (or the ride has ended). Cancellation is no longer allowed.',
      );
      return false;
    }

    return true;
  }

  // ================= CANCEL BOOKING API ================= //
  Future<bool> cancelBookingApi(
    BuildContext context, {
    required String bookingId,
    required String cancellationReason,
    String? cancelledBy,
  }) async {
    setLoading(true);

    final canCancel = await _canCustomerCancelBooking(
      context,
      bookingId: bookingId,
    );

    if (!canCancel) {
      setLoading(false);
      return false;
    }

    final Map<String, dynamic> body = {
      "cancellation_reason": cancellationReason,
      if (cancelledBy != null) "cancelled_by": cancelledBy, //
    };

    log("CANCEL BOOKING ID => $bookingId");
    log("CANCEL BOOKING BODY => $body");

    final res = await postJsonData(
      'booking/cancel_by_customer/$bookingId',
      body,
      context,
      headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
        'Accept': 'application/json',
      },
    );

    setLoading(false);

    if (res == null) return false;

    if (res['success'] == true) {
      /// ✅ Show success message
      if (res['message'] is List && res['message'].isNotEmpty) {
        SnackBarToastMessage.showSnackBar(
          context,
          res['message'][0].toString(),
        );
      }
      notifyListeners();
      return true;
    } else {
      // ✅ Show server error message (e.g. "Driver has arrived, cannot cancel")
      final errMsg = (res['message'] is List && (res['message'] as List).isNotEmpty)
          ? res['message'][0].toString()
          : 'Unable to cancel booking at this time.';
      SnackBarToastMessage.showSnackBar(context, errMsg);
      return false;
    }
  }

  // ==================== EDIT BOOKING LOCATION API ==================== //
  // Backend recomputes price fresh from the new coordinates — never trust a
  // client-computed fare here. Returns the full response (success/message
  // plus the updated booking data with the new price) so the caller can show
  // the new fare / surface a specific error (e.g. "driver already arrived").
  Future<Map<String, dynamic>?> editBookingLocationApi(
    BuildContext context, {
    required String bookingId,
    String? pickupAddress,
    double? pickupLat,
    double? pickupLng,
    String? dropAddress,
    double? dropLat,
    double? dropLng,
    // Full replacement list of intermediate stops (excludes the final drop) —
    // pass [] to clear all stops, or omit entirely to leave stops unchanged.
    List<Map<String, dynamic>>? stops,
  }) async {
    setLoading(true);
    final Map<String, dynamic> body = {
      if (pickupAddress != null) 'pickup_address': pickupAddress,
      if (pickupLat != null) 'pickup_lat': pickupLat,
      if (pickupLng != null) 'pickup_lng': pickupLng,
      if (dropAddress != null) 'drop_address': dropAddress,
      if (dropLat != null) 'drop_lat': dropLat,
      if (dropLng != null) 'drop_lng': dropLng,
      if (stops != null) 'stops': stops,
    };

    final res = await postJsonData(
      'booking/edit_location/$bookingId',
      body,
      context,
      headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
        'Accept': 'application/json',
      },
    );
    setLoading(false);

    if (res != null && res['success'] == true) {
      notifyListeners();
    }
    return res;
  }

  // ==================== LOGOUT API ==================== //
  Future<String?> logOutApiCalling(BuildContext context) async {
    setSecondaryLoading(true);

    String? successMessage;
    bool logoutSuccess = false;

    try {
      final res = await postJsonData(
        'user/logout',
        {},
        context,
        headers: {
          'authorization': 'Bearer ${AppConstant.token}',
        },
      );

      if (res != null && res['success'] == true) {
        logoutSuccess = true;
        successMessage = res['message'][0].toString();

        // Clear local data immediately
        await CacheHelper.clearAll();
        AppConstant.token = '';
      }
    } catch (e) {
      if (kDebugMode) print('Logout error: $e');
    }

    setSecondaryLoading(false);

    // Return the result
    return logoutSuccess ? successMessage : null;
  }

  //

  // ==================== COINS API ==================== //

  Future<Map<String, dynamic>?> getCoinsBalanceApi(BuildContext context) async {
    final res = await getData(
      'coins/balance',
      context,
      headers: {'Authorization': 'Bearer ${AppConstant.token}'},
    );
    return res;
  }

  Future<Map<String, dynamic>?> applyCoinsApi(
    BuildContext context, {
    required int coinsToApply,
    String? bookingId,
  }) async {
    final Map<String, dynamic> body = {'coins_to_apply': coinsToApply};
    if (bookingId != null && bookingId.isNotEmpty) body['booking_id'] = bookingId;
    final res = await postJsonData(
      'coins/apply',
      body,
      context,
      headers: {'Authorization': 'Bearer ${AppConstant.token}'},
    );
    return res;
  }

  Future<Map<String, dynamic>?> scratchSeenApi(
    BuildContext context, {
    required String bookingId,
  }) async {
    final res = await postJsonData(
      'coins/scratch-seen',
      {'booking_id': bookingId},
      context,
      headers: {'Authorization': 'Bearer ${AppConstant.token}'},
    );
    return res;
  }

  Future<Map<String, dynamic>?> getCoinsHistoryApi(BuildContext context) async {
    final res = await getData(
      'coins/history',
      context,
      headers: {'Authorization': 'Bearer ${AppConstant.token}'},
    );
    return res;
  }

  Future<Map<String, dynamic>?> createCoinRedeemRequestApi(
    BuildContext context, {
    required int coins,
    required String payoutMethod, // 'bank' or 'upi'
    String? bankAccountNumber,
    String? bankIfsc,
    String? bankAccountHolder,
    String? upiId,
  }) async {
    final Map<String, dynamic> body = {
      'coins': coins,
      'payout_method': payoutMethod,
    };
    if (payoutMethod == 'bank') {
      body['bank_account_number'] = bankAccountNumber ?? '';
      body['bank_ifsc'] = bankIfsc ?? '';
      body['bank_account_holder'] = bankAccountHolder ?? '';
    } else {
      body['upi_id'] = upiId ?? '';
    }
    final res = await postJsonData(
      'coins/redeem-request',
      body,
      context,
      headers: {'Authorization': 'Bearer ${AppConstant.token}'},
    );
    return res;
  }

  Future<Map<String, dynamic>?> getCoinRedeemRequestsApi(BuildContext context) async {
    final res = await getData(
      'coins/redeem-requests',
      context,
      headers: {'Authorization': 'Bearer ${AppConstant.token}'},
    );
    return res;
  }

  // Missions — "complete N delivered orders in the window, then claim X coins".
  Future<Map<String, dynamic>?> getCoinMissionsApi(BuildContext context) async {
    final res = await getData(
      'coins/missions',
      context,
      headers: {'Authorization': 'Bearer ${AppConstant.token}'},
    );
    return res;
  }

  Future<Map<String, dynamic>?> claimCoinMissionApi(
    BuildContext context, {
    required String missionId,
  }) async {
    final res = await postJsonData(
      'coins/missions/$missionId/claim',
      {},
      context,
      headers: {'Authorization': 'Bearer ${AppConstant.token}'},
    );
    return res;
  }

  //

  // ==================== BUSINESS MODE API ==================== //

  // Enterprise Mode interest form (Retailer app → BusinessLead in admin panel).
  Future<Map<String, dynamic>?> submitBusinessLeadApi(
    BuildContext context, {
    required String businessName,
    required String contactName,
    required String phoneNumber,
    required String email,
    String message = '',
  }) async {
    return postJsonData(
      'business/lead',
      {
        'businessName': businessName,
        'contactName': contactName,
        'phoneNumber': phoneNumber,
        'email': email,
        'message': message,
      },
      context,
      headers: {'Authorization': 'Bearer ${AppConstant.token}'},
    );
  }

  Future<Map<String, dynamic>?> getBusinessStatusApi(BuildContext context) async {
    final res = await getData(
      'business/status',
      context,
      headers: {'Authorization': 'Bearer ${AppConstant.token}'},
    );
    return res;
  }

  Future<Map<String, dynamic>?> redeemBusinessLinkCodeApi(
    BuildContext context, {
    required String code,
  }) async {
    final res = await postJsonData(
      'business/link-codes/redeem',
      {'code': code},
      context,
      headers: {'Authorization': 'Bearer ${AppConstant.token}'},
    );
    return res;
  }

  Future<Map<String, dynamic>?> leaveBusinessApi(BuildContext context) async {
    final res = await postData(
      'business/leave',
      context,
      headers: {'Authorization': 'Bearer ${AppConstant.token}'},
    );
    return res;
  }

  Future<Map<String, dynamic>?> registerBusinessAccountApi(
    BuildContext context, {
    required String businessName,
    required String gstNumber,
  }) async {
    final res = await postJsonData(
      'business/register',
      {'businessName': businessName, 'gstNumber': gstNumber},
      context,
      headers: {'Authorization': 'Bearer ${AppConstant.token}'},
    );
    return res;
  }

  //

  // ==================== NOTICEBOARD API ==================== //

  Future<Map<String, dynamic>?> getNoticesApi(BuildContext context) async {
    final res = await getData(
      'notices?audience=retailer',
      context,
      headers: {'Authorization': 'Bearer ${AppConstant.token}'},
    );
    return res;
  }

  //

  // ==================== PROMO BANNER API ==================== //

  // Home screen promo carousel — backend-driven so admin can add/edit/retire
  // banners from the admin panel with no app update. See Backend
  // GET /promo-banners?audience=retailer (returns 'retailer' + 'both').
  Future<Map<String, dynamic>?> getPromoBannersApi(BuildContext context) async {
    final res = await getData(
      'promo-banners?audience=retailer',
      context,
      headers: {'Authorization': 'Bearer ${AppConstant.token}'},
    );
    return res;
  }

  //
}

// ==================== Content Screen Cache ==================== //

class AppContentCache {
  static final AppContentCache _instance = AppContentCache._internal();
  factory AppContentCache() => _instance;
  AppContentCache._internal();

  List<dynamic>? contentArr;

  void clear() {
    contentArr = null;
  }

  bool get hasData => contentArr != null && contentArr!.isNotEmpty;
}
