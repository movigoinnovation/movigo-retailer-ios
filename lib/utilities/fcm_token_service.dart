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
      // Push it to the backend right away instead of relying solely on
      // updateTokenAfterLogin() — that's called from the splash screen's
      // fast, synchronous cached-login path, which reliably finishes
      // *before* this async Firebase/permission-dialog/getToken() chain
      // does. That one-shot check was silently no-op'ing on every normal
      // launch, leaving player_id stuck at the "123456" placeholder forever.
      await _updateTokenOnBackend(token);
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
    if (token.isEmpty || token == '123456') return;
    // The auth token is normally already restored from cache by the time
    // this runs (that's fast/synchronous; FCM setup is not), but guard
    // against the reverse race by waiting briefly instead of a one-shot
    // check that silently drops the update.
    for (int i = 0; i < 10 && AppConstant.token.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (AppConstant.token.isEmpty) return;
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
        final t = await messaging.getToken().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            debugPrint('FCM getToken attempt $attempt timed out after 15s');
            return null;
          },
        );
        if (t != null) return t;
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
