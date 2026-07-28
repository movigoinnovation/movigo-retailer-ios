import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'app_config_provider.dart';
import 'app_constant.dart';
import 'local_notification_service.dart';

class FcmTokenService {
  static Future<void> generateAndStoreToken() async {
    final FirebaseMessaging messaging = FirebaseMessaging.instance;

    try {
      await messaging.requestPermission(
        alert: true, badge: true, sound: true, provisional: false,
      );
    } catch (e) {
      debugPrint('FCM permission request failed: $e');
    }

    final String? token = await _getTokenWithRetry(messaging: messaging);

    if (token != null && token.isNotEmpty) {
      AppConstant.playerID = token;
      debugPrint('FCM token: ${AppConstant.playerID}');
    }

    _setupForegroundMessageHandler();

    // FIX: send refreshed token to backend immediately
    messaging.onTokenRefresh.listen(
      (String refreshedToken) async {
        AppConstant.playerID = refreshedToken;
        debugPrint('FCM token refreshed: ${AppConstant.playerID}');
        await _updateTokenOnBackend(refreshedToken);
      },
      onError: (Object error) => debugPrint('FCM refresh error: $error'),
    );
  }

  static Future<void> updateTokenAfterLogin() async {
    if (AppConstant.playerID.isEmpty || AppConstant.playerID == '123456') return;
    await _updateTokenOnBackend(AppConstant.playerID);
  }

  static Future<void> _updateTokenOnBackend(String token) async {
    if (AppConstant.token.isEmpty || token.isEmpty || token == '123456') return;
    try {
      await http.post(
        Uri.parse('${AppConfigProvider.apiUrl}user/update_fcm_token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AppConstant.token}',
        },
        body: jsonEncode({'fcm_token': token}),
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('FCM backend update failed: $e');
    }
  }

  static Future<String?> _getTokenWithRetry({
    required FirebaseMessaging messaging,
    int maxAttempts = 3,
  }) async {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await messaging.getToken();
      } on PlatformException catch (e) {
        debugPrint('FCM getToken PlatformException attempt $attempt: ${e.code}');
      } catch (e) {
        debugPrint('FCM getToken failed attempt $attempt: $e');
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
    return null;
  }

  static void _setupForegroundMessageHandler() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      await LocalNotificationService.showFromRemoteMessage(message);
    });
  }

  static void setupNotificationTapRedirection(
    void Function(RemoteMessage message) onRedirect,
  ) {
    FirebaseMessaging.onMessageOpenedApp.listen(onRedirect);
  }
}
