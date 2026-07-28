import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';

class NotificationUnreadCountController with ChangeNotifier {

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  int _totalUnreadCount = 0;
  int get totalUnreadCount => _totalUnreadCount;

  bool _hasUnread = false;
  bool get hasUnread => _hasUnread;

  int _readStatus = 0;
  int get readStatus => _readStatus;

  // ================= GET UNREAD COUNT =================

  Future<void> getUnreadNotificationCount(BuildContext context) async {

    _isLoading = true;
    notifyListeners();

    try {

      final response = await getData(
        'notification/unread-count',
        context,
        headers: {
          'Authorization': 'Bearer ${AppConstant.token}',
          'Accept': 'application/json',
        },
      );

      if (response != null && response['success'] == true) {

        final data = response['data'];

        _totalUnreadCount = data['total_unread_count'] ?? 0;
        _hasUnread = data['has_unread'] ?? false;
        _readStatus = data['read_status'] ?? 0;

      }

    } catch (e) {
      debugPrint('❌ Notification Count Error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // ================= RESET =================

  void reset() {
    _totalUnreadCount = 0;
    _hasUnread = false;
    _readStatus = 0;
    _isLoading = false;

    notifyListeners();
  }
}