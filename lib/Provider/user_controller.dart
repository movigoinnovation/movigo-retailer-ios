import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'common_api_helper/common_shared_prefrences.dart';

class UserController with ChangeNotifier {
  String _userId = "";
  String get getUserId => _userId;

  String _token = "";
  String get getToken => _token;

  String _userImage = "";
  String get getUserImage => _userImage;

  String _userName = "";
  String get getUserName => _userName;

  String _userMobile = "";
  String get getUserMobile => _userMobile;

  String _userGender = "";
  String get getUserGender => _userGender;

  String _userEmail = "";
  String get getUserEmail => _userEmail;

  List<String> _workPhotos = [];
  List<String> get getWorkPhotos => _workPhotos;

  String _address = "";
  String get getAddress => _address;

  double _latitude = 0.0;
  double get getlatitude => _latitude;

  double _longitude = 0.0;
  double get getlongitude => _longitude;

  String _serviceId = ""; // vehicleType_id
  String get getServiceId => _serviceId;

  String _serviceName = ""; // not provided in API
  String get getServiceName => _serviceName;

  String _technicianExperience = ""; // not applicable for driver
  String get getTechnicianExperience => _technicianExperience;

  String _approvalStatus = "";
  String get getApprovalStatus => _approvalStatus;

  String _birthdate = "";
  String get getBirthdate => _birthdate;

  bool _isVerified = false;
  bool get getIsVerified => _isVerified;

  String _aadhaarFront = "";
  String get getAadhaarFront => _aadhaarFront;

  String _aadhaarBack = "";
  String get getAadhaarBack => _aadhaarBack;

  String _pancard = "";
  String get getPancard => _pancard;

  String _dlFront = "";
  String get getDlFront => _dlFront;

  String _dlBack = "";
  String get getDlBack => _dlBack;

  bool _isAvailable = false;
  bool get getIsAvailable => _isAvailable;

  String _vehicleName = "";
  String get getVehicleName => _vehicleName;

  String _registrationNumber = "";
  String get getRegistrationNumber => _registrationNumber;

  String _userType = ""; // Customer / Retailer
  String get getUserType => _userType;

  String _businessName = "";
  String get getBusinessName => _businessName;
  bool _isBusinessProfileCompleted = false;
  bool get isBusinessProfileCompleted => _isBusinessProfileCompleted;
  double _businessLat = 0.0;
  double _businessLng = 0.0;
  double get businessLat => _businessLat;
  double get businessLng => _businessLng;

  // ── Ride PINs ─────────────────────────────────────────────────────────────
  String _startPin = '';
  String _endPin   = '';
  String get startPin => _startPin;
  String get endPin   => _endPin;

  // Returns full data map for screens that need multiple fields at once
  Map<String, dynamic> get getAllData => {
    'business_name':    _businessName,
    'business_type':    '',  // loaded from cache on demand
    'gst_number':       '',
    'pan_number':       _pancard,
    'address':          _address,
    'landmark':         _landmark,
    'city':             '',
    'pincode':          '',
    'num_employees':    '',
    'website':          '',
    'bank_account_number': '',
    'bank_ifsc':        '',
    'bank_name':        '',
    'bank_account_holder': '',
    'description':      _description,
  };

  String _description = "";
  String get getDescription => _description;

  String _landmark = "";
  String get getLandmark => _landmark;

  bool _disposed = false;

  // ================= GET USER DETAILS =================
  Future<void> getUserDetails() async {
    final userDetails = await CacheHelper.get('user_details');
    if (kDebugMode) print("userdetails: $userDetails");

    if (userDetails == null) {
      _clearLocalVariables();
      return;
    }

    try {
      final Map<String, dynamic> data = json.decode(userDetails);

      _token = data['token'] ?? "";
      _userId = (data['user_id'] ?? data['_id'] ?? '').toString();
      _userType = data['user_type'] ?? "";
      _userImage = data['profile_image'] ?? "";
      _userName = data['full_name'] ?? "";
      _userMobile = data['phone_number'] ?? "";
      _userGender = data['gender'] ?? "";
      _userEmail = data['email'] ?? "";
      _birthdate = data['birthdate'] ?? "";
      _registrationNumber = data['registration_number'] ?? "";
      _approvalStatus = data['approval_status'] ?? "";
      _isVerified = data['is_verified'] ?? false;
      _isAvailable = data['is_available'] ?? false;

      _address = data['address'] ?? "";
      _latitude = double.tryParse(data['latitude']?.toString() ?? '') ?? 0.0;
      _longitude = double.tryParse(data['longitude']?.toString() ?? '') ?? 0.0;

      _businessName = data['business_name'] ?? "";
      _landmark = data['landmark'] ?? "";
      _description = data['description'] ?? "";
      _isBusinessProfileCompleted = data['is_business_profile_completed'] ?? false;
      _businessLat = double.tryParse(data['business_lat']?.toString() ?? '') ?? 0.0;
      _businessLng = double.tryParse(data['business_lng']?.toString() ?? '') ?? 0.0;
      _startPin = data['start_pin'] ?? '';
      _endPin   = data['end_pin']   ?? '';

      // Vehicle
      _serviceId = data['vehicleType_id'] ?? "";
      _vehicleName = data['vehicleType_name'] ?? "";

      // Driver does not have work photos
      _workPhotos = [];
      _technicianExperience = "";

      // ID Proofs
      _aadhaarFront = "";
      _aadhaarBack = "";
      _pancard = "";

      if (data['id_proofs'] is List) {
        for (final doc in data['id_proofs']) {
          if (doc['document_type'] == 'Aadhaar') {
            _aadhaarFront = doc['front'] ?? "";
            _aadhaarBack = doc['back'] ?? "";
          }
          if (doc['document_type'] == 'DrivingLicense') {
            _dlFront = doc['front'] ?? "";
            _dlBack = doc['back'] ?? "";
          }
        }
      }

      if (kDebugMode) print("PROFILE IMAGE FROM CACHE => ${data['profile_image']}");

      if (hasListeners && !_disposed) {
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) print("❌ Error decoding userDetails: $e");
      _clearLocalVariables();
    }
  }

  // ================= CLEAR LOCAL =================
  void _clearLocalVariables() {
    _registrationNumber = "";
    _token = "";
    _userType = "";
    _dlBack = "";
    _userId = "";
    _userImage = "";
    _userName = "";
    _userMobile = "";
    _userGender = "";
    _userEmail = "";
    _businessName = "";
    _landmark = "";
    _description = "";
    _workPhotos = [];
    _address = "";
    _serviceId = "";
    _vehicleName = "";
    _serviceName = "";
    _technicianExperience = "";
    _approvalStatus = "";
    _birthdate = "";
    _isVerified = false;
    _isAvailable = false;
    _aadhaarFront = "";
    _aadhaarBack = "";
    _pancard = "";
    _latitude = 0.0;
    _longitude = 0.0;
  }

  // ================= CLEAR USER DATA =================
  Future<void> clearUserData() async {
    try {
      await CacheHelper.remove('user_details');
      _clearLocalVariables();

      if (hasListeners && !_disposed) {
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) print('Error in clearUserData: $e');
    }
  }

  // ================= UPDATE AVAILABILITY =================
  Future<void> updateAvailabilityStatus(bool isAvailable) async {
    _isAvailable = isAvailable;

    final userDetails = await CacheHelper.get('user_details');
    if (userDetails != null) {
      try {
        final data = json.decode(userDetails);
        if (data is Map<String, dynamic>) {
          data['is_available'] = isAvailable;
          await CacheHelper.save('user_details', json.encode(data));
        }
      } catch (e) {
        if (kDebugMode) print("Error updating availability status: $e");
      }
    }

    if (hasListeners && !_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }
}
