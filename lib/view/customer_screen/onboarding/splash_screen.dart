import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:geolocator/geolocator.dart';
import 'package:movigo/Provider/common_api_helper/common_shared_prefrences.dart';
import 'package:movigo/Provider/socket_connection/socket_provider.dart';
import 'package:movigo/utilities/fcm_token_service.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/local_notification_service.dart';
import 'package:movigo/utilities/location_service_helper.dart';
import 'package:movigo/utilities/app_config_provider.dart';
import 'package:movigo/services/in_app_update_service.dart';
import 'package:movigo/main.dart' show MyApp;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:movigo/view/customer_screen/create_booking_screen/finding_driver_screen.dart';
import 'language_selection_screen.dart';
import 'onboardingone_screen.dart';
import 'force_update_screen.dart';
import 'SoftUpdatePopup.dart';

import 'signup_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isInitializationDone = false;
  VoidCallback? _navigationAction;
  final DateTime _splashStartTime = DateTime.now();
  static const Duration _minSplashTime = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirebaseAndInitialize();
    });
  }

  void _tryNavigation() {
    if (!_isInitializationDone || _navigationAction == null) return;

    final elapsed = DateTime.now().difference(_splashStartTime);
    final remaining = _minSplashTime - elapsed;
    if (remaining <= Duration.zero) {
      _navigationAction!();
    } else {
      Future.delayed(remaining, () {
        if (!mounted) return;
        _navigationAction?.call();
      });
    }
  }

  Future<void> _checkFirebaseAndInitialize() async {
    // Start login check immediately — cache read doesn't need Firebase
    _checkLoginStatus();

    // Wait for Firebase in background (needed for FCM/notifications)
    if (Firebase.apps.isEmpty) {
      log('⚠️ Firebase not initialized yet, waiting in background');
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (Firebase.apps.isNotEmpty) break;
      }
    }

    if (Firebase.apps.isNotEmpty) {
      log('✅ Firebase initialized');
      unawaited(_initFcmAndPermissions());
    } else {
      log('❌ Firebase not initialized after 3s');
    }
  }

  Future<void> _initializeApp() async {
    // FCM token, notification permission, and location permission don't
    // affect routing — run them in the background so they never delay the
    // login/navigation decision.
    unawaited(_initFcmAndPermissions());
    _checkLoginStatus();
  }

  Future<void> _initFcmAndPermissions() async {
    try {
      await getFCMToken();
      await _requestNotificationPermissions();
      // Request location permission on startup (like Porter)
      // Fetch GPS in background if granted so it's ready when user books
      await _requestLocationPermission();
    } catch (e) {
      log('❌ Error in _initializeApp: $e');
    }
  }

  Future<void> _requestLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Ask once at startup; if the retailer ignores it, the home screen's
        // search bar asks again before falling back to an empty pickup.
        serviceEnabled = await LocationServiceHelper.ensureEnabled();
        if (!serviceEnabled) return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        // Fetch GPS in background — saves it to AppConstant for use in booking
        Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium)
            .then((pos) {
          AppConstant.currentLat = pos.latitude;
          AppConstant.currentLng = pos.longitude;
          log('✅ GPS pre-fetched: ${pos.latitude}, ${pos.longitude}');
        }).catchError((e) {
          log('⚠️ GPS pre-fetch error: $e');
        });
      }
    } catch (e) {
      log('⚠️ Location permission error: $e');
    }
  }


  // // 🔴 NEW FUNCTION - Test notification bhejne ke liye
  // Future<void> _sendTestNotification() async {
  //   log('🧪 Sending test notification...');
  //   try {
  //     // Create a test RemoteMessage
  //     final testMessage = RemoteMessage(
  //       messageId: 'test_${DateTime.now().millisecondsSinceEpoch}',
  //       data: {
  //         'title': '🧪 Test Notification',
  //         'body': 'Yeh test notification hai iOS ke liye!',
  //         'type': 'test',
  //         'click_action': 'FLUTTER_NOTIFICATION_CLICK',
  //       },
  //       notification: RemoteNotification(
  //         title: '🧪 Test Notification',
  //         body: 'Yeh test notification hai iOS ke liye!',
  //       ),
  //       sentTime: DateTime.now(),
  //     );
  //     // LocalNotificationService ke through dikhao
  //     await LocalNotificationService.showFromRemoteMessage(testMessage);
  //     log('✅ Test notification sent successfully!');
  //   } catch (e) {
  //     log('❌ Test notification failed: $e');
  //   }
  // }

  Future<void> _requestNotificationPermissions() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      log('📱 Notification permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        String? apnsToken = await messaging.getAPNSToken();
        log('📱 APNS Token: $apnsToken');
      }
    } catch (e) {
      log('❌ Error requesting permissions: $e');
    }
  }

  Future<void> getFCMToken() async {
    try {
      if (Firebase.apps.isEmpty) {
        log('⚠️ Firebase not initialized, cannot get token');
        return;
      }

      String? token = await FirebaseMessaging.instance.getToken();

      if (token != null) {
        log('✅ FCM Token: $token');
      } else {
        log('❌ FCM Token is null');
      }
    } catch (e) {
      log('❌ Error getting FCM token: $e');
    }
  }

  Future<void> _checkLoginStatus() async {
    if (!mounted) return;

    // Force update check runs in parallel — login/navigation must never wait
    // on this network round-trip. If it comes back true, it redirects via
    // Navigator.pushReplacement whenever it resolves, even if we've already
    // navigated.
    unawaited(_checkForceUpdate());

    try {
      final userDetails = await CacheHelper.get('user_details');
      log("📱 userDetails from cache: $userDetails");

      if (userDetails == null || userDetails.isEmpty) {
        _navigationAction = () => _navigateToWelcome();
        _isInitializationDone = true;
        _tryNavigation();
        return;
      }

      final Map<String, dynamic> data = json.decode(userDetails);

      // 'token' is set by otp_verify and signup. 'current_token' is the
      // fallback for older cached data from profile update responses.
      final String token = (data['token'] ?? data['current_token'] ?? '').toString();
      final bool isProfileCompleted = data['is_profile_completed'] == true;
      final String userType = 'Retailer';

      AppConstant.token = token;
      log("✅ Restored token: $token");

      // Sync FCM token to backend every time the app launches with a valid session
      // This ensures the retailer's player_id in DB stays fresh
      FcmTokenService.updateTokenAfterLogin();

      if (token.isNotEmpty) {
        // Navigate immediately from cache — don't wait for network
        if (isProfileCompleted) {
          _navigationAction = () => _navigateToHome(userType);
        } else {
          final phone = (data['phone_number'] ?? '').toString();
          _navigationAction = () => Get.offAll(() => SignupScreen(mobile: phone));
        }
        _isInitializationDone = true;
        _tryNavigation();

        // Refresh profile in background — updates cache for next launch
        unawaited(_refreshProfileInBackground(token));
      } else {
        _navigationAction = () => _navigateToWelcome();
        _isInitializationDone = true;
        _tryNavigation();
      }
    } catch (e) {
      log("❌ Splash error: $e — trying cached data");
      // On any unexpected error, try cached data before giving up
      final fallback = await CacheHelper.get('user_details');
      if (fallback != null) {
        try {
          final fd = jsonDecode(fallback);
          final ft = (fd['token'] ?? '').toString();
          final fp = fd['is_profile_completed'] == true;
          final fu = 'Retailer';
          if (ft.isNotEmpty && fp) {
            AppConstant.token = ft;
            _navigationAction = () => _navigateToHome(fu);
            _isInitializationDone = true;
            _tryNavigation();
            return;
          }
        } catch (_) {}
      }
      _navigationAction = () => _navigateToWelcome();
      _isInitializationDone = true;
      _tryNavigation();
    }
  }

  Future<void> _refreshProfileInBackground(String token) async {
    try {
      final url = Uri.parse('${AppConstant.apiBaseUrl}user/get_profile');
      final resp = await http.get(url, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'User-Agent': 'movigo-retailer-app',
      }).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body['success'] == true && body['data'] != null) {
          final freshData = {...body['data'], 'token': token};
          await CacheHelper.save('user_details', jsonEncode(freshData));
          log('✅ Profile refreshed in background');
        }
      }
    } catch (e) {
      log('⚠️ Background profile refresh failed: $e');
    }
  }

  Future<bool> _checkForceUpdate() async {
    try {
      // Cross-platform build number via package_info_plus (reads the actual
      // installed CFBundleVersion/versionCode) instead of a Dart-side
      // hardcoded fallback. The previous implementation read this through an
      // Android-only MethodChannel ('com.movigo.retailer/permissions') that
      // has no iOS-side handler — on iOS it always threw and silently fell
      // back to a hardcoded stale number, so the backend never learned the
      // real installed build and could never force/soft-update iOS at all.
      int buildNumber = 1;
      try {
        final info = await PackageInfo.fromPlatform();
        buildNumber = int.tryParse(info.buildNumber) ?? 1;
      } catch (e) {
        log('Error fetching app version via PackageInfo: $e');
      }

      const String appType  = 'retailer';
      final String platform = Platform.isIOS ? 'ios' : 'android';
      final url = Uri.parse(
        '${AppConfigProvider.apiUrl}app_version_check'
        '?app_type=$appType&version_code=$buildNumber&platform=$platform',
      );
      final resp = await http
          .get(url, headers: {
            'Content-Type': 'application/json',
            // Best-effort: if a session token is already cached (returning
            // user, not a fresh install), the backend uses it to also drop
            // an "Update Available" entry into the retailer's notification
            // inbox.
            if (AppConstant.token.isNotEmpty) 'Authorization': 'Bearer ${AppConstant.token}',
          })
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        if (body['success'] == true && body['data'] != null) {
          final data = body['data'];
          final bool forceUpdate = data['force_update'] == true;

          if (forceUpdate) {
            // Backend's own version gate decides immediate vs flexible, not
            // Play Console's staged-rollout priority. Try Play's native
            // full-screen blocking flow first; only fall back to our own
            // ForceUpdateScreen if that isn't available (e.g. sideloaded
            // build, no Play Store on device).
            final started = await InAppUpdateService.instance.check(
              MyApp.navigatorKey.currentContext,
              forceUpdate: true,
            );
            if (started) return true;

            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => ForceUpdateScreen(
                    latestVersion: (data['latest_version'] ?? '').toString(),
                    playStoreUrl:  (data['play_store_url']  ?? '').toString(),
                    appStoreUrl:   (data['app_store_url']   ?? '').toString(),
                  ),
                ),
              );
            }
            return true;
          } else {
            // Not force-required — offer a flexible (backgrounded) update.
            unawaited(InAppUpdateService.instance.check(
              MyApp.navigatorKey.currentContext,
              forceUpdate: false,
            ));

            // A newer build has been published but isn't mandatory yet —
            // show a dismissible popup so the retailer can update on their
            // own terms instead of only relying on Play's silent flow.
            if (data['update_available'] == true) {
              final ctx = MyApp.navigatorKey.currentContext;
              if (ctx != null) {
                unawaited(SoftUpdatePopup.showIfNeeded(
                  ctx,
                  latestVersion: (data['latest_version'] ?? '').toString(),
                  latestVersionCode:
                      int.tryParse(data['latest_version_code']?.toString() ?? '') ?? 0,
                  playStoreUrl: (data['play_store_url'] ?? '').toString(),
                  appStoreUrl: (data['app_store_url'] ?? '').toString(),
                ));
              }
            }
          }
        }
      }
    } catch (e) {
      log('Version check failed (offline?): $e');
    }
    return false;
  }

  void _navigateToHome(String userType) async {
    if (!mounted) return;
    final socketProvider = Provider.of<SocketProvider>(context, listen: false);
    socketProvider.initSocket(AppConstant.token);
    AppConstant.selectedFooterIndex = 0;

    if (userType == "Retailer") {
      // R2: Restore active booking screen if the app was killed mid-booking
      final prefs = await SharedPreferences.getInstance();
      final activeBookingId = prefs.getString('retailer_active_booking_id') ?? '';
      if (activeBookingId.isNotEmpty) {
        Get.offAll(() => FindingDriverScreen(bookingId: activeBookingId));
      } else {
        Get.offAll(() => const CustomBottomNav(
              userType: UserType.retailer,
              initialIndex: 0,
            ));
      }
    } else {
      _navigateToWelcome();
    }
  }

  void _navigateToWelcome() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    // Default to English (0) silently — no language selection screen on startup
    if (!prefs.containsKey('app_language')) {
      await prefs.setInt('app_language', 0);
    }
    language = prefs.getInt('app_language') ?? 0;
    Get.off(() => OnboardingScreen());
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.white, // clean premium white background as requested
      body: SizedBox.expand(
        child: Center(
          child: Image.asset(
            'assets/icons/movigo_app_logo2.png',
            width: size.width * 0.6,
            fit: BoxFit.contain,
            cacheWidth: (size.width * 0.6 * MediaQuery.of(context).devicePixelRatio).round(),
          ),
        ),
      ),
    );
  }
}
