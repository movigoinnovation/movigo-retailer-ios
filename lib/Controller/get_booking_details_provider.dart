import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';

class BookingDetailController with ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Map<String, dynamic>? _bookingDetail;
  Map<String, dynamic>? get bookingDetail => _bookingDetail;

  Future<void> getBookingDetail(
    BuildContext context, {
    required String bookingId,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final headers = {
        'Authorization': 'Bearer ${AppConstant.token}',
        'Accept': 'application/json',
      };

      final response = await getData(
        'booking/$bookingId',
        context,
        headers: headers,
      );

      if (response != null && response['success'] == true) {
        // ✅ DATA IS MAP, NOT LIST
        _bookingDetail = response['data'] as Map<String, dynamic>;
      } else {
        _bookingDetail = null;
      }
    } catch (e) {
      debugPrint('❌ Booking Detail Error: $e');
      _bookingDetail = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void reset() {
    _bookingDetail = null;
    _isLoading = false;
    notifyListeners();
  }
}
