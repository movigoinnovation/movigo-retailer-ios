import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:movigo/view/customer_screen/create_booking_screen/booking_detail_screen.dart';
import 'package:movigo/view/customer_screen/wallet_screen/add_money_screen.dart';
import 'app_constant.dart';
import 'app_footer.dart';

class NotificationRedirectHelper {
  static String _str(dynamic value) => (value ?? '').toString().trim();

  static String _firstNonEmpty(Map<String, dynamic> map, List<String> keys) {
    for (final String key in keys) {
      final String value = _str(map[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static Map<String, dynamic> extractActionJson(Map<String, dynamic> data) {
    final dynamic raw = data['action_json'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  static Map<String, dynamic> payloadFromNotificationItem({
    required String action,
    String? bookingId,
    Map<String, dynamic>? actionJson,
  }) {
    final Map<String, dynamic> data = <String, dynamic>{};
    if (action.trim().isNotEmpty) {
      data['action'] = action;
    }
    if (bookingId != null && bookingId.trim().isNotEmpty) {
      data['booking_id'] = bookingId;
    }
    if (actionJson != null && actionJson.isNotEmpty) {
      data['action_json'] = actionJson;
    }
    return data;
  }

  static void routeFromNotificationData({
    required BuildContext context,
    required NavigatorState navigator,
    required Map<String, dynamic> data,
    VoidCallback? onUnknownAction,
  }) {
    final String action = _str(data['action']).toLowerCase();
    final Map<String, dynamic> actionJson = extractActionJson(data);
    final String bookingId = _firstNonEmpty(
      actionJson.isNotEmpty ? actionJson : data,
      <String>['booking_id'],
    );

    if (action == 'low_wallet_balance' || action == 'low_wallet_credit') {
      navigator.push(MaterialPageRoute(builder: (_) => AddMoneyScreen()));
      return;
    }

    if (action == 'booking_accepted' ||
        action == 'driver_arrived' ||
        action == 'booking_started' ||
        action == 'on_the_way' ||
        action == 'booking_completed') {
      if (bookingId.isEmpty) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => BookingDetailScreen(bookingId: bookingId),
        ),
      );
      return;
    }

    if (action == 'deposit_refunded' || action == 'wallet_deposit_deducted') {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => const CustomBottomNav(
            userType: UserType.retailer,
            initialIndex: 2,
          ),
        ),
      );
      return;
    }

    onUnknownAction?.call();
  }
}
