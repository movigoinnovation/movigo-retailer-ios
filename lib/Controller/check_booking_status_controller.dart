import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';

class CheckBookingStatusController with ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool? _isDriverAccepted;
  bool? get isDriverAccepted => _isDriverAccepted;

  String? _bookingStatus;
  String? get bookingStatus => _bookingStatus;

  String? _assignedDriverId;
  String? get assignedDriverId => _assignedDriverId;

  Map<String, dynamic>? _pickupLocation;
  Map<String, dynamic>? get pickupLocation => _pickupLocation;

  bool get isTerminalStatus {
    final status = (_bookingStatus ?? '').trim().toLowerCase();
    return status == 'delivered' ||
        status == 'completed' ||
        status == 'complete' ||
        status == 'cancelled' ||
        status == 'canceled' ||
        status == 'rejected';
  }

  // ================= CHECK BOOKING STATUS =================
  Future<void> checkBookingStatus(
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
        'user/check_booking_status/$bookingId',
        context,
        headers: headers,
      );

      if (response != null && response['success'] == true) {
        final data = response['data'];
        if (data is Map) {
          _isDriverAccepted = data['is_driver_accepted'] == true;
          _bookingStatus = (data['booking_status'] ?? data['status'])?.toString();
          final driver = data['driver_id'] ?? data['driverId'] ?? data['driver'];
          if (driver is Map) {
            _assignedDriverId = (driver['_id'] ?? driver['id'])?.toString();
          } else {
            _assignedDriverId = driver?.toString();
          }
          _pickupLocation = data['pickup_location'] is Map
              ? Map<String, dynamic>.from(data['pickup_location'] as Map)
              : null;
        } else {
          _isDriverAccepted = false;
          _bookingStatus = null;
          _assignedDriverId = null;
          _pickupLocation = null;
        }
      } else {
        _isDriverAccepted = null;
        _bookingStatus = null;
        _assignedDriverId = null;
        _pickupLocation = null;
      }
    } catch (e) {
      debugPrint('❌ Check Booking Status Error: $e');
      _isDriverAccepted = null;
      _bookingStatus = null;
      _assignedDriverId = null;
      _pickupLocation = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ================= RESET =================
  void reset() {
    _isDriverAccepted = null;
    _bookingStatus = null;
    _assignedDriverId = null;
    _pickupLocation = null;
    _isLoading = false;
    notifyListeners();
  }
}
