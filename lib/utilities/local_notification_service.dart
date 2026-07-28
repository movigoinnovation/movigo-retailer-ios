import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Used for important notifications.',
    importance: Importance.max,
  );

  static bool _initialized = false;
  static void Function(String? payload)? _onNotificationTap;
  static String? _pendingLaunchPayload;

  static final Map<String, DateTime> _recentNotificationKeys = {};
  static const Duration _dedupeWindow = Duration(seconds: 6);

  static void setOnNotificationTapHandler(
      void Function(String? payload) onTap) {
    _onNotificationTap = onTap;
  }

  static Future<void> initialize() async {
    if (_initialized) return;

    /// ANDROID SETTINGS
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@drawable/ic_stat_notification');

    /// IOS SETTINGS (IMPORTANT FIX)
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    /// COMBINED SETTINGS
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse:
          (NotificationResponse notificationResponse) {
        _onNotificationTap?.call(notificationResponse.payload);
      },
    );

    /// APP LAUNCH FROM NOTIFICATION
    final NotificationAppLaunchDetails? launchDetails =
        await _notifications.getNotificationAppLaunchDetails();

    if (launchDetails?.didNotificationLaunchApp == true) {
      _pendingLaunchPayload = launchDetails?.notificationResponse?.payload;
    }

    /// ANDROID CHANNEL
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    _initialized = true;
  }

  static String? consumePendingLaunchPayload() {
    final payload = _pendingLaunchPayload;
    _pendingLaunchPayload = null;
    return payload;
  }

  static Future<void> showFromRemoteMessage(RemoteMessage message) async {
    final RemoteNotification? notification = message.notification;

    if (!_shouldShowNotification(message)) return;

    final String? title = _pickFirstString([
      notification?.title,
      message.data['title'],
      message.data['notification_title'],
    ]);

    final String? body = _pickFirstString([
      notification?.body,
      message.data['body'],
      message.data['message'],
      message.data['description'],
      message.data['content'],
    ]);

    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    final int notificationId = _stableNotificationId(message);

    await _notifications.show(
      notificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_stat_notification',
        ),
        iOS: const DarwinNotificationDetails(), // iOS fix
      ),
      payload: jsonEncode(message.data),
    );
  }

  static String? _pickFirstString(List<dynamic> values) {
    for (final dynamic value in values) {
      if (value == null) continue;
      final String text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static bool _shouldShowNotification(RemoteMessage message) {
    final String key = _notificationKey(message);
    if (key.isEmpty) return true;

    final DateTime now = DateTime.now();

    _recentNotificationKeys.removeWhere(
      (_, timestamp) => now.difference(timestamp) > _dedupeWindow,
    );

    final DateTime? lastSeen = _recentNotificationKeys[key];

    if (lastSeen != null && now.difference(lastSeen) <= _dedupeWindow) {
      return false;
    }

    _recentNotificationKeys[key] = now;
    return true;
  }

  static String _notificationKey(RemoteMessage message) {
    final Map<String, dynamic> data = message.data;

    final String id = _pickFirstString([
          message.messageId,
          data['notification_id'],
          data['booking_id'],
          data['venue_booking_id'],
          data['event_booking_id'],
          data['senderId'],
        ]) ??
        '';

    if (id.isNotEmpty) return id;

    final String? action = _pickFirstString([data['action']]);

    final String? title = _pickFirstString([
      message.notification?.title,
      data['title'],
      data['notification_title'],
    ]);

    final String? body = _pickFirstString([
      message.notification?.body,
      data['body'],
      data['message'],
      data['description'],
      data['content'],
    ]);

    return '${action ?? ''}|${title ?? ''}|${body ?? ''}'.trim();
  }

  static int _stableNotificationId(RemoteMessage message) {
    final String key = _notificationKey(message);
    if (key.isEmpty) return message.hashCode;

    return key.hashCode & 0x7fffffff;
  }
}
