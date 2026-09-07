import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';

class BookingDetailController with ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Map<String, dynamic>? _bookingDetail;
  Map<String, dynamic>? get bookingDetail => _bookingDetail;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // True when the backend says this booking is no longer assigned to this
  // retailer (reassigned/cancelled) — retrying won't help, so the UI should
  // offer "Go back" instead of "Retry".
  bool _isReassigned = false;
  bool get isReassigned => _isReassigned;

  // Retries a transient failure (timeout/network blip/5xx) a few times with
  // backoff before giving up, since the booking is already committed on the
  // backend by the time this screen loads — a blip here should not be shown
  // to the retailer as "booking not found".
  static const int _maxAttempts = 3;
  static const List<Duration> _retryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  // [silent] is used for background/manual refreshes (e.g. the map's
  // refresh button, the 1-min live-location poll) where the previous
  // booking data should stay on screen instead of being replaced by the
  // full-screen shimmer while the new data loads.
  Future<void> getBookingDetail(
    BuildContext context, {
    required String bookingId,
    bool silent = false,
  }) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }
    _errorMessage = null;
    _isReassigned = false;

    final headers = {
      'Authorization': 'Bearer ${AppConstant.token}',
      'Accept': 'application/json',
    };

    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        debugPrint(
            "🌐 [API] Fetching booking detail for ID => $bookingId (attempt $attempt)");

        final response = await getData(
          'booking/$bookingId',
          // Only let the shared helper show its own snackbars (401/500/etc.)
          // on the final attempt — earlier attempts retry silently.
          attempt == _maxAttempts ? context : null,
          headers: headers,
        );

        if (response != null && response['success'] == true) {
          final rawData = response['data'];

          if (rawData is Map<String, dynamic>) {
            _bookingDetail = rawData;
            _errorMessage = null;
          } else if (rawData is String) {
            try {
              _bookingDetail = jsonDecode(rawData);
              _errorMessage = null;
            } catch (e) {
              debugPrint("JSON Decode Failed: $e");
              _bookingDetail = null;
              _errorMessage = 'Could not read booking details. Please try again.';
            }
          } else {
            debugPrint("Unexpected type: ${rawData.runtimeType}");
            _bookingDetail = null;
            _errorMessage = 'Could not read booking details. Please try again.';
          }
          break;
        } else if (response != null && response['code'] == 'BOOKING_NOT_ASSIGNED') {
          // Not a transient failure — this booking was reassigned/cancelled
          // and will never load for this retailer. Stop retrying immediately.
          _bookingDetail = null;
          _isReassigned = true;
          _errorMessage = _extractServerMessage(response) ??
              'This booking is no longer available.';
          break;
        } else {
          _bookingDetail = null;
          _errorMessage = _extractServerMessage(response) ??
              'Could not load booking details. Check your connection and try again.';
        }
      } catch (e) {
        debugPrint('❌ Booking Detail Error: $e');
        _bookingDetail = null;
        _errorMessage = 'Could not load booking details. Check your connection and try again.';
      }

      if (_bookingDetail != null) break;
      if (attempt < _maxAttempts) {
        await Future.delayed(_retryDelays[attempt - 1]);
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  // Backend sends `message` as either a plain string or a per-language list
  // (e.g. ['Booking not found']) — unwrap it so the real reason reaches the UI
  // instead of falling back to the generic connectivity message.
  String? _extractServerMessage(Map<String, dynamic>? response) {
    final message = response?['message'];
    if (message is String && message.isNotEmpty) return message;
    if (message is List && message.isNotEmpty) {
      final idx = language >= 0 && language < message.length ? language : 0;
      return message[idx]?.toString();
    }
    return null;
  }

  void reset() {
    _bookingDetail = null;
    _isLoading = false;
    _errorMessage = null;
    _isReassigned = false;
    notifyListeners();
  }
}
