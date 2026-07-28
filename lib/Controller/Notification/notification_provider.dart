import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';

class NotificationController with ChangeNotifier {
  List<NotificationItem> _notifications = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;

  int _currentPage = 1;
  int _totalPages = 1;
  int _totalItems = 0;
  final int _limit = 10;

  List<NotificationItem> get notifications => _notifications;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _currentPage < _totalPages;

  /// ================= GET ALL NOTIFICATIONS =================
  Future<void> getAllNotifications(
    BuildContext context, {
    bool isRefresh = false,
  }) async {
    if (isRefresh) {
      _currentPage = 1;
      _notifications.clear();
      _isLoading = true;
    } else {
      _isLoadingMore = true;
    }
    notifyListeners();

    try {
      final response = await getData(
        'notification/get_all_notification?limit=$_limit&page=$_currentPage',
        context,
        headers: {
          'Authorization': 'Bearer ${AppConstant.token}',
        },
      );

      if (response != null && response['success'] == true) {
        final data = response['data'];

        _totalItems = data['totalItems'] ?? 0;
        _totalPages = data['totalPages'] ?? 1;
        _currentPage = data['currentPage'] ?? 1;

        final List list = data['item'] ?? [];
        final newList = list.map((e) => NotificationItem.fromJson(e)).toList();

        _notifications.addAll(newList);
      }
    } catch (e) {
      debugPrint("Notification Error: $e");
    } finally {
      _isLoading = false;
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// ================= LOAD MORE =================
  Future<void> loadMore(BuildContext context) async {
    if (hasMore && !_isLoadingMore) {
      _currentPage++;
      await getAllNotifications(context);
    }
  }

  /// ================= DELETE SINGLE =================
  Future<bool> deleteSingleNotification(
    BuildContext context,
    String notificationId,
  ) async {
    final response = await postJsonData(
      'notification/delete_single_notification',
      {
        'notification_id': notificationId,
      },
      context,
      headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
      },
    );

    if (response != null && response['success'] == true) {
      _notifications.removeWhere((e) => e.notificationId == notificationId);

      _totalItems = _notifications.length;
      notifyListeners();

      final msg = response['message'];
      final msgText = msg is List && language < msg.length
          ? msg[language].toString()
          : msg?.toString() ?? 'Notification deleted';
      SnackBarToastMessage.showSnackBar(context, msgText);
      return true;
    }
    return false;
  }

  /// ================= CLEAR ALL =================
  Future<bool> clearAllNotifications(BuildContext context) async {
    final response = await postData(
      'notification/clear_all_notification',
      context,
      headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
      },
    );

    if (response != null && response['success'] == true) {
      _notifications.clear();
      _currentPage = 1;
      _totalItems = 0;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// ================= RESET =================
  void reset() {
    _notifications.clear();
    _currentPage = 1;
    _totalPages = 1;
    _totalItems = 0;
    _isLoading = false;
    _isLoadingMore = false;
    notifyListeners();
  }
}

class NotificationItem {
  final String notificationId;
  final String action;
  final String title;
  final String message;
  final Map<String, dynamic>? actionJson;
  final String? bookingId;
  final int readStatus;
  final String createTime;

  NotificationItem({
    required this.notificationId,
    required this.action,
    required this.title,
    required this.message,
    this.actionJson,
    this.bookingId,
    required this.readStatus,
    required this.createTime,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? parsedActionJson;
    final dynamic rawActionJson = json['action_json'];
    if (rawActionJson is Map<String, dynamic>) {
      parsedActionJson = rawActionJson;
    } else if (rawActionJson is Map) {
      parsedActionJson =
          rawActionJson.map((key, value) => MapEntry(key.toString(), value));
    } else if (rawActionJson is String && rawActionJson.trim().isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(rawActionJson);
        if (decoded is Map) {
          parsedActionJson =
              decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {}
    }

    return NotificationItem(
      notificationId: json['notification_id'] ?? '',
      action: json['action'] ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      actionJson: parsedActionJson,
      bookingId: json['booking_id'],
      readStatus: json['read_status'] ?? 0,
      createTime: json['createtime'] ?? '',
    );
  }
}
