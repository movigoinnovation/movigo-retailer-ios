import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';

class RetailerHomeController with ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Map<String, dynamic>? _homeData;
  Map<String, dynamic>? get homeData => _homeData;

  Map<String, dynamic>? _counts;
  Map<String, dynamic>? get counts => _counts;

  List<dynamic> _ongoingBookings = [];
  List<dynamic> get ongoingBookings => _ongoingBookings;

  Map<String, dynamic>? _pagination;
  Map<String, dynamic>? get pagination => _pagination;

  Future<void> getRetailerHome(
    BuildContext context, {
    int page = 1,
    int limit = 10,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final headers = {
        'Authorization': 'Bearer ${AppConstant.token}',
        'Accept': 'application/json',
      };

      final response = await getData(
        'user/retailer_home?page=$page&limit=$limit',
        context,
        headers: headers,
      );

      if (response != null && response['success'] == true) {
        _homeData = response['data'];

        _counts = _homeData?['counts'];
        _ongoingBookings = _homeData?['ongoing_bookings'] ?? [];
        _pagination = _homeData?['pagination'];
      } else {
        _homeData = null;
        _counts = null;
        _ongoingBookings = [];
        _pagination = null;
      }
    } catch (e) {
      debugPrint('❌ Retailer Home Error: $e');
      _homeData = null;
      _counts = null;
      _ongoingBookings = [];
      _pagination = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void reset() {
    _homeData = null;
    _counts = null;
    _ongoingBookings = [];
    _pagination = null;
    _isLoading = false;
    notifyListeners();
  }
}
