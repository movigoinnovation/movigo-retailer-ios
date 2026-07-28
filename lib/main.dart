import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get_navigation/src/root/get_material_app.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'Provider/app_provider/app_provider.dart';
import 'Provider/app_provider/theme_provider.dart';
import 'utilities/app_constant.dart';
import 'utilities/fcm_token_service.dart';
import 'utilities/local_notification_service.dart';
import 'utilities/no_internet.dart';
import 'utilities/notification_redirect_helper.dart';
import 'view/customer_screen/notification_screen/notification_screen.dart';
import 'view/customer_screen/onboarding/splash_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("📱 [BACKGROUND] Message received: ${message.messageId}");

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }

  await LocalNotificationService.initialize();
  // FIX: always show — backend sends notification+data together, handle both
  {
    await LocalNotificationService.showFromRemoteMessage(message);
  }
}

Future<void> main() async {
  HttpOverrides.global = MyHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();

  // Catches ALL unhandled Flutter framework errors (widget build, layout, etc.)
  // Without this, any uncaught error in a build/paint phase crashes the app
  // and gets counted toward Play Store's crash rate threshold.
  FlutterError.onError = (FlutterErrorDetails details) {
    // Firebase may not be initialized yet (it's set up in the background
    // below) — only forward to Crashlytics once an app instance exists.
    if (Firebase.apps.isNotEmpty) {
      FirebaseCrashlytics.instance.recordFlutterError(details);
    }
    FlutterError.presentError(details);
  };

  // Catches ALL errors thrown in async callbacks, timers, isolates, etc.
  // that Flutter's framework doesn't catch natively.
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    if (Firebase.apps.isNotEmpty) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
    }
    return true; // returning true = handled, app continues
  };

  // Boot the app immediately so the splash screen and first frames draw.
  // This satisfies the Android Vitals cold start requirement.
  runApp(const MyApp());

  // Run slow/network initializations in the background
  _initializeDependenciesInBackground();
}

Future<void> _initializeDependenciesInBackground() async {
  // Edge-to-edge: let content draw behind both status bar and nav bar.
  // Each screen controls its own overlay colours via SystemUiOverlayStyle.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.dark,
  ));

  // Lock app in Portrait mode only on phone-sized screens; leave
  // tablets/foldables unrestricted so the app isn't flagged for
  // large-screen support.
  final view = PlatformDispatcher.instance.views.first;
  final shortestSideDp = (view.physicalSize.shortestSide / view.devicePixelRatio);
  if (shortestSideDp < 600) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]).catchError((_) {});
  }

  try {
    // Initialize Firebase first
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    print('✅ Firebase initialized in background');

    // Platform-specific notification setup
    await _setupNotifications();
  } catch (e) {
    print('❌ Error in background init: $e');
  }
}

// Platform-specific notification setup
Future<void> _setupNotifications() async {
  try {
    // Request permissions based on platform
    if (Platform.isIOS) {
      // iOS specific settings - simplified
      NotificationSettings settings =
          await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      print('✅ iOS Permission: ${settings.authorizationStatus}');

      // Get APNS Token for iOS
      String? apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      if (kDebugMode) {
        print('✅ APNS Token: $apnsToken');
      }
    } else if (Platform.isAndroid) {
      final notificationPermission = await Permission.notification.status;
      if (!notificationPermission.isGranted) {
        await Permission.notification.request();
      }

      NotificationSettings settings =
          await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      print('✅ Android Permission: ${settings.authorizationStatus}');
    }

    // Get FCM Token (common for both platforms)
    String? fcmToken = await FirebaseMessaging.instance.getToken();
    if (kDebugMode) {
      print('✅ FCM Token: $fcmToken');
    }

    if (fcmToken != null) {
      AppConstant.playerID = fcmToken;
    }

    // Initialize local notifications
    await LocalNotificationService.initialize();
    print('✅ Local notifications initialized');

    // Set up message handlers
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // NOTE: foreground onMessage is handled by FcmTokenService._setupForegroundMessageHandler()

    // App opened from background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('📱 [OPENED] App opened from notification');
      _handleNotificationNavigation(message);
    });

    // Check initial message
    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      print('📱 [TERMINATED] App opened from terminated state');
      _handleNotificationNavigation(initialMessage);
    }

    print('✅ Notification setup complete');
  } catch (e) {
    print('❌ Error in notification setup: $e');
    print('Stack trace: ${StackTrace.current}');
  }
}

void _showForegroundNotification(RemoteMessage message) {
  // Show notification in foreground
  LocalNotificationService.showFromRemoteMessage(message);
}

void _handleNotificationNavigation(RemoteMessage message) {
  print('Navigating from notification: ${message.data}');
  // Add your navigation logic here
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ConnectionStatus status = ConnectionStatus.WiFi;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  static final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _subscription =
        _connectivity.onConnectivityChanged.listen(_onConnectivityChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initNotificationRedirections();
    });
  }

  void _onConnectivityChange(List<ConnectivityResult> results) {
    if (results.isEmpty) {
      _updateConnectionStatus(ConnectivityResult.none);
    } else {
      _updateConnectionStatus(results.first);
    }
  }

  Future<void> _initConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.isEmpty) {
        _updateConnectionStatus(ConnectivityResult.none);
      } else {
        _updateConnectionStatus(results.first);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => status = ConnectionStatus.None);
    }
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    if (!mounted) return;
    setState(() {
      switch (result) {
        case ConnectivityResult.wifi:
          status = ConnectionStatus.WiFi;
          break;
        case ConnectivityResult.mobile:
          status = ConnectionStatus.Mobile;
          break;
        case ConnectivityResult.none:
        default:
          status = ConnectionStatus.None;
      }
    });
  }

  Future<void> _handleRetry() async {
    await _initConnectivity();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _initNotificationRedirections() async {
    if (Firebase.apps.isEmpty) {
      print('⚠️ Firebase not ready');
      return;
    }

    try {
      LocalNotificationService.setOnNotificationTapHandler(
        _handleLocalNotificationTapPayload,
      );

      final String? pendingLocalPayload =
          LocalNotificationService.consumePendingLaunchPayload();
      if (pendingLocalPayload != null &&
          pendingLocalPayload.trim().isNotEmpty) {
        _handleLocalNotificationTapPayload(pendingLocalPayload);
      }

      FcmTokenService.setupNotificationTapRedirection(_handlePushRedirect);

      final RemoteMessage? initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _handlePushRedirect(initialMessage);
      }

      print('✅ Notification redirections initialized');
    } catch (e) {
      print('❌ Error in notification redirections: $e');
    }
  }

  void _handleLocalNotificationTapPayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) {
      _openNotificationScreen();
      return;
    }

    try {
      final dynamic decoded = jsonDecode(payload);
      if (decoded is Map) {
        final map =
            decoded.map((key, value) => MapEntry(key.toString(), value));
        _routeFromNotificationData(map);
        return;
      }
    } catch (_) {}

    _openNotificationScreen();
  }

  void _handlePushRedirect(RemoteMessage message) {
    _routeFromNotificationData(message.data);
  }

  void _routeFromNotificationData(Map<String, dynamic> data) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _routeFromNotificationData(data);
      });
      return;
    }

    final context = _navigatorKey.currentContext;
    if (context == null) return;

    NotificationRedirectHelper.routeFromNotificationData(
      context: context,
      navigator: navigator,
      data: data,
      onUnknownAction: _openNotificationScreen,
    );
  }

  void _openNotificationScreen() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute(
        builder: (_) => const NotificationScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return MultiProvider(
      providers: AppProviders.providers,
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => GetMaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Movigo',
        debugShowCheckedModeBanner: false,
        themeMode: themeProvider.themeMode,
        theme: ThemeProvider.lightTheme,
        darkTheme: ThemeProvider.darkTheme,
        builder: (context, child) {
          return Stack(
            children: [
              child!,
              NoInternetBanner(
                status: status,
                onRetry: _handleRetry,
              ),
            ],
          );
        },
        home: const SplashScreen(),
      ),
      ),
    );
  }
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..userAgent = 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 movigo';
  }
}
