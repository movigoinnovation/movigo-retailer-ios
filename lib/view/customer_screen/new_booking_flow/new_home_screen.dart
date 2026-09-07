import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:movigo/Controller/NotificationUnreadCountController.dart';
import 'package:movigo/Controller/retailer_home_cotroller.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/helper/date_time_format/date_time_format.dart';
import 'package:movigo/view/retailer_screen/retailer_booking_screen/track_driver_screen.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_config_provider.dart';
import 'package:movigo/helper/places_session_token.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/location_service_helper.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/utilities/phone_number_formatter.dart';
import 'package:movigo/view/customer_screen/account_screen/help_and_support_screen.dart';
import 'package:movigo/view/customer_screen/notification_screen/notification_screen.dart';
import 'package:movigo/view/customer_screen/noticeboard/noticeboard_screen.dart';
import 'package:movigo/Model/notice_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'route_vehicle_screen.dart';
import 'package:movigo/utilities/app_tour_spotlight.dart';
import 'package:movigo/view/customer_screen/coins/coin_wallet_screen.dart';
import 'package:movigo/view/customer_screen/coins/coin_missions_screen.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:movigo/helper/contacts_permission_helper.dart';
import 'package:movigo/helper/map_picker.dart';
import 'package:movigo/Controller/accepted_booking_provider.dart';
import 'package:movigo/view/customer_screen/new_booking_flow/retailer_confirm_screen.dart';

DateTime? _homeLastPressed;

class NewHomeScreen extends StatefulWidget {
  const NewHomeScreen({super.key});

  @override
  State<NewHomeScreen> createState() => _NewHomeScreenState();
}

class _NewHomeScreenState extends State<NewHomeScreen> {
  String _currentCity = "Fetching location...";
  LatLng? _currentLatLng;
  // True only once a real device GPS fix has been obtained — distinguishes
  // an actual current location from the retailer's saved business-address
  // fallback, which otherwise looks "resolved" and wins the race against GPS.
  bool _isRealGps = false;
  // Set when the retailer is asked (a second time, via the search bar) to
  // turn GPS on and still declines/doesn't — while true, pickup resolution
  // skips the business-address fallback and stays empty rather than guessing.
  bool _locationServiceDeclined = false;
  bool _geocodingInProgress = false;
  // Cache geocoding result — only re-call the API if user has moved >500 m
  LatLng? _lastGeocodedLatLng;
  String? _lastGeocodedCity;
  // When the last successful GPS fix completed — lets us skip re-fetching
  // (and blocking navigation) if it's still recent.
  DateTime? _lastLocationFetchAt;
  // Recent drop locations fetched from the server; merged with
  // _favoriteLocations (pinned first) and capped to 3 for display.
  List<Map<String, dynamic>> _recentDrops = [];
  // Hearted locations, persisted locally (not saved as an address on the
  // server) — always shown pinned at the top of the 3 recommendations.
  List<Map<String, dynamic>> _favoriteLocations = [];
  static const _favoriteLocationsPrefsKey = 'retailer_favorite_locations';

  static const _intentChannel = MethodChannel('com.movigo.retailer/location_intent');

  // Polls for the active-booking tracker banner so it disappears on its own
  // shortly after the driver marks the ride Delivered/Cancelled — the retailer
  // may already be sitting on Home when that happens, so a one-shot fetch on
  // initState alone would leave a stale banner up.
  Timer? _bookingTrackerTimer;

  int _coinBalance = 0;
  // Available coin missions (not yet claimed) — drives the "New mission for
  // you" banner shown above the destination search bar.
  int _availableMissions = 0;
  Map<String, dynamic>? _topMission;
  String _homeAddress = "";
  double? _homeLat;
  double? _homeLng;
  String _shopAddress = "";
  double? _shopLat;
  double? _shopLng;
  Map? _lastBooking;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _noticeboardIconKey = GlobalKey();
  final GlobalKey _bookRideSearchBarKey = GlobalKey();
  final GlobalKey _missionBannerKey = GlobalKey();

  // Server-saved addresses (Home/Work/Office/Godown/Other, via user/save_address).
  List<Map<String, dynamic>> _savedAddresses = [];

  // Bumped on pull-to-refresh so the promo carousel / noticeboard banner
  // subtrees are rebuilt from scratch and re-fetch their backend data.
  int _refreshTick = 0;

  @override
  static const _retailerVehicleOptions = [
    _VehicleOption(Icons.two_wheeler,       'Bike / 2W',  'R_2W',       AppImage.bike),
    _VehicleOption(Icons.electric_scooter,  'E-Scooter',  'R_SCOOTER',  AppImage.twowheel),
    _VehicleOption(Icons.electric_rickshaw, 'Mini 3W',    'R_MINI_3W',  AppImage.mini3w),
    _VehicleOption(Icons.electric_car,      'E-Loader',   'R_E_LOADER', AppImage.eloader),
    _VehicleOption(Icons.airport_shuttle,   '3 Wheeler',  'R_3W',       AppImage.threewheeler),
    _VehicleOption(Icons.local_shipping,    'Tata Ace',   'R_TATA_ACE', AppImage.minitruck),
  ];

  static const _customerVehicleOptions = [
    _VehicleOption(Icons.two_wheeler,       '2 Wheeler', 'C_2W', AppImage.twowheel),
    _VehicleOption(Icons.electric_rickshaw, '3 Wheeler', 'C_3W', AppImage.threewheeler),
    _VehicleOption(Icons.directions_car,    '4 Wheeler', 'C_4W', AppImage.minitruck),
  ];

  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
    _loadUserData();
    _initLocationIntentChannel();
    _loadFavoriteLocations();
    _fetchRecentDrops();
    _loadCoinBalance();
    _loadMissions();
    _loadHomeAndShopAddresses();
    _loadSavedAddresses();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getCurrentLocation();
      Provider.of<NotificationUnreadCountController>(context, listen: false)
          .getUnreadNotificationCount(context);
      // Once-only quick-tour: noticeboard icon, then the booking search bar —
      // give layout a beat to settle before measuring target positions.
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        AppTourSpotlight.maybeShow(
          context: context,
          targetKey: _noticeboardIconKey,
          prefKey: AppTourSpotlight.noticeboardKey,
          title: 'Noticeboard 📣',
          description:
              'Tap here anytime for announcements, updates and offers from Movigo.',
          onDismissed: () {
            if (!mounted) return;
            AppTourSpotlight.maybeShow(
              context: context,
              targetKey: _bookRideSearchBarKey,
              prefKey: AppTourSpotlight.bookRideKey,
              title: 'Book a Ride 🚚',
              description:
                  'Tap here to start a delivery — pick your pickup and drop points in seconds.',
              onDismissed: () {
                if (!mounted || _topMission == null) return;
                AppTourSpotlight.maybeShow(
                  context: context,
                  targetKey: _missionBannerKey,
                  prefKey: AppTourSpotlight.missionKey,
                  title: 'New mission for you 🎯',
                  description:
                      'Hit the order target here to earn bonus coins. Tap to see your missions and claim rewards.',
                );
              },
            );
          },
        );
      });

      // Fetch booking history
      Provider.of<AcceptedBookingController>(context, listen: false)
          .getBookings(context, bookingKey: 'all')
          .then((_) {
            if (mounted) {
              final list = Provider.of<AcceptedBookingController>(context, listen: false).bookingList;
              if (list.isNotEmpty) {
                setState(() {
                  _lastBooking = list.firstWhere(
                    (b) => b['booking_status']?.toString().toLowerCase() == 'delivered',
                    orElse: () => list.first,
                  );
                });
              }
            }
          });
    });
  }

  // Pull-to-refresh — reload everything the Home screen shows, mirroring the
  // Orders screen's swipe-down behaviour. Runs the fetches concurrently and
  // rebuilds the promo/noticeboard banner subtrees so they re-fetch too.
  Future<void> _onRefresh() async {
    if (mounted) setState(() => _refreshTick++);
    await Future.wait([
      _loadUserData(),
      _fetchRecentDrops(),
      _loadCoinBalance(),
      _loadMissions(),
      _loadHomeAndShopAddresses(),
      _loadSavedAddresses(),
      Provider.of<AcceptedBookingController>(context, listen: false)
          .getBookings(context, bookingKey: 'all'),
      Provider.of<NotificationUnreadCountController>(context, listen: false)
          .getUnreadNotificationCount(context),
    ]);
  }

  Future<void> _fetchRecentDrops() async {
    try {
      final data = await getData('user/recent_drops', context, headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
      });
      if (!mounted) return;
      if (data != null && data['success'] == true) {
        setState(() =>
            _recentDrops = List<Map<String, dynamic>>.from(data['data'] ?? []));
      }
    } catch (e) {
      debugPrint('fetchRecentDrops error: $e');
    }
  }

  // Locations don't carry a stable server id here, so identify them by
  // coordinates (falling back to the address text) for de-duping/matching.
  String _locationKey(Map<String, dynamic> loc) {
    final lat = loc['lat'];
    final lng = loc['lng'];
    if (lat != null && lng != null) {
      return '${(lat as num).toStringAsFixed(6)},${(lng as num).toStringAsFixed(6)}';
    }
    return (loc['address'] ?? '').toString();
  }

  // Favorited locations pinned first, then recent drops filling the rest,
  // deduped, capped to 5 — what actually gets rendered below the search bar.
  List<Map<String, dynamic>> get _displayedLocations {
    final seen = <String>{};
    final combined = <Map<String, dynamic>>[];
    for (final loc in [..._favoriteLocations, ..._recentDrops]) {
      if (seen.add(_locationKey(loc))) combined.add(loc);
    }
    return combined.take(5).toList();
  }

  Future<void> _loadFavoriteLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_favoriteLocationsPrefsKey);
      if (json == null || !mounted) return;
      setState(() => _favoriteLocations =
          List<Map<String, dynamic>>.from(jsonDecode(json)));
    } catch (e) {
      debugPrint('loadFavoriteLocations error: $e');
    }
  }

  Future<void> _persistFavoriteLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _favoriteLocationsPrefsKey, jsonEncode(_favoriteLocations));
    } catch (e) {
      debugPrint('persistFavoriteLocations error: $e');
    }
  }

  // Hearting never calls the server — it just pins the location locally so
  // it always shows up first. Hearting again unpins/removes it.
  void _toggleFavoriteLocation(Map<String, dynamic> loc) {
    final key = _locationKey(loc);
    setState(() {
      final existingIndex =
          _favoriteLocations.indexWhere((f) => _locationKey(f) == key);
      if (existingIndex != -1) {
        _favoriteLocations.removeAt(existingIndex);
      } else {
        _favoriteLocations.insert(0, {
          'address': loc['address'],
          'lat': loc['lat'],
          'lng': loc['lng'],
          'contact_name': loc['contact_name'],
          'contact_phone': loc['contact_phone'],
        });
      }
    });
    _persistFavoriteLocations();
  }

  @override
  void dispose() {
    _bookingTrackerTimer?.cancel();
    super.dispose();
  }

  void _initLocationIntentChannel() {
    _intentChannel.setMethodCallHandler((call) async {
      if (call.method == 'onLocationIntentReceived') {
        final String? uri = call.arguments as String?;
        if (uri != null && uri.isNotEmpty) {
          _handleLocationIntent(uri);
        }
      }
    });

    // Check for pending intents
    _checkPendingLocationIntent();
  }

  Future<void> _checkPendingLocationIntent() async {
    try {
      final String? uri = await _intentChannel.invokeMethod<String>('getPendingLocationIntent');
      if (uri != null && uri.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _handleLocationIntent(uri);
          }
        });
      }
    } catch (_) {}
  }

  Future<String> _resolveShortUrl(String url) async {
    int redirectCount = 0;
    String currentUrl = url;
    while (redirectCount < 5) {
      if (!currentUrl.contains('maps.app.goo.gl') && 
          !currentUrl.contains('goo.gl/maps') && 
          !currentUrl.contains('t.co') &&
          !currentUrl.contains('bit.ly')) {
        break;
      }
      try {
        final client = http.Client();
        final request = http.Request('GET', Uri.parse(currentUrl))..followRedirects = false;
        final response = await client.send(request);
        final redirectUrl = response.headers['location'];
        client.close();
        if (redirectUrl != null && redirectUrl.isNotEmpty) {
          currentUrl = redirectUrl;
          redirectCount++;
        } else {
          break;
        }
      } catch (_) {
        break;
      }
    }
    return currentUrl;
  }

  LatLng? _parseCoordinates(String url) {
    if (url.startsWith('geo:')) {
      final geoBody = url.substring(4);
      final parts = geoBody.split('?');
      final latLngPart = parts[0];
      final latLngSubparts = latLngPart.split(',');
      if (latLngSubparts.length >= 2) {
        final lat = double.tryParse(latLngSubparts[0]);
        final lng = double.tryParse(latLngSubparts[1]);
        if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
          return LatLng(lat, lng);
        }
      }
      if (parts.length > 1) {
        final query = Uri.splitQueryString(parts[1]);
        final q = query['q'];
        if (q != null) {
          final qParts = q.split('(')[0].split(',');
          if (qParts.length >= 2) {
            final lat = double.tryParse(qParts[0].trim());
            final lng = double.tryParse(qParts[1].trim());
            if (lat != null && lng != null) {
              return LatLng(lat, lng);
            }
          }
        }
      }
      return null;
    }

    final atMatch = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(url);
    if (atMatch != null) {
      final lat = double.tryParse(atMatch.group(1) ?? '');
      final lng = double.tryParse(atMatch.group(2) ?? '');
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }

    final qMatch = RegExp(r'[?&](?:q|query)=(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(url);
    if (qMatch != null) {
      final lat = double.tryParse(qMatch.group(1) ?? '');
      final lng = double.tryParse(qMatch.group(2) ?? '');
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }

    final placeMatch = RegExp(r'/place/(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(url);
    if (placeMatch != null) {
      final lat = double.tryParse(placeMatch.group(1) ?? '');
      final lng = double.tryParse(placeMatch.group(2) ?? '');
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }

    final dirMatch = RegExp(r'/(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(url);
    if (dirMatch != null) {
      final lat = double.tryParse(dirMatch.group(1) ?? '');
      final lng = double.tryParse(dirMatch.group(2) ?? '');
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }

    return null;
  }

  String? _parseQuerySearch(String url) {
    if (url.startsWith('geo:')) {
      final parts = url.substring(4).split('?');
      if (parts.length > 1) {
        final query = Uri.splitQueryString(parts[1]);
        return query['q'];
      }
    } else {
      try {
        final uri = Uri.parse(url);
        return uri.queryParameters['q'] ?? uri.queryParameters['query'];
      } catch (_) {}
    }
    return null;
  }

  Future<Map<String, dynamic>?> _geocodeAddress(String query) async {
    try {
      final _gUri = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(query)}&key=${AppConstant.googleApiKey}&language=en');
      final _gResp = await http.get(_gUri).timeout(const Duration(seconds: 6));
      if (_gResp.statusCode == 200) {
        final decoded = jsonDecode(_gResp.body);
        final results = (decoded['results'] as List? ?? []);
        if (results.isNotEmpty) {
          final location = results.first['geometry']['location'];
          final lat = location['lat'] as double;
          final lng = location['lng'] as double;
          final formattedAddress = results.first['formatted_address'] as String? ?? '';
          return {
            'lat': lat,
            'lng': lng,
            'address': formattedAddress.isNotEmpty ? formattedAddress : query,
          };
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String> _geocodeLatLng(LatLng latLng) async {
    try {
      final _gUri = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?latlng=${latLng.latitude},${latLng.longitude}&key=${AppConstant.googleApiKey}&language=en');
      final _gResp = await http.get(_gUri).timeout(const Duration(seconds: 6));
      if (_gResp.statusCode == 200) {
        final decoded = jsonDecode(_gResp.body);
        final results = (decoded['results'] as List? ?? []);
        if (results.isNotEmpty) {
          final formattedAddress = results.first['formatted_address'] as String? ?? '';
          if (formattedAddress.isNotEmpty) {
            return formattedAddress;
          }
        }
      }
    } catch (_) {}
    return "${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}";
  }

  // Returns the retailer's saved shop coordinates, or null when none are on
  // file — callers must treat null as "no location known" and let the user
  // pick one manually rather than silently substituting an arbitrary point.
  LatLng? _getRetailerFallbackLatLng(UserController user) {
    if (user.getlatitude != 0.0 && user.getlongitude != 0.0) {
      return LatLng(user.getlatitude, user.getlongitude);
    }
    if (user.businessLat != 0.0 && user.businessLng != 0.0) {
      return LatLng(user.businessLat, user.businessLng);
    }
    return null;
  }

  String _getRetailerFallbackAddress(UserController user) => user.getAddress;

  Future<void> _handleLocationIntent(String intentUri) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(
          color: AppColor.themeColor,
        ),
      ),
    );

    try {
      final resolvedUrl = await _resolveShortUrl(intentUri);
      LatLng? targetLatLng = _parseCoordinates(resolvedUrl);
      String? targetAddress;

      if (targetLatLng == null) {
        final searchQuery = _parseQuerySearch(resolvedUrl);
        if (searchQuery != null && searchQuery.isNotEmpty) {
          final geocoded = await _geocodeAddress(searchQuery);
          if (geocoded != null) {
            targetLatLng = LatLng(geocoded['lat'] as double, geocoded['lng'] as double);
            targetAddress = geocoded['address'] as String;
          }
        }
      } else {
        targetAddress = await _geocodeLatLng(targetLatLng);
      }

      if (mounted) {
        Navigator.pop(context); // dismiss progress dialog
      }

      if (targetLatLng != null && targetAddress != null) {
        if (!mounted) return;

        // Ask the user whether the shared location is Pickup or Drop.
        final String? choice = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => _LocationRoleSheet(address: targetAddress!),
        );

        if (!mounted || choice == null) return;

        if (choice == 'drop') {
          // Shared location â†' Drop. Let user pick their own pickup location.
          await _ensureFreshLocation();
          if (!mounted) return;

          final user = Provider.of<UserController>(context, listen: false);
          final isRetailer = user.getUserType.toLowerCase() == 'retailer';

          LatLng? pickupLatLng = _currentLatLng;
          String pickupAddr = _currentCity;

          final bool hasGoodLocation = _isRealGps &&
              _currentLatLng != null &&
              _currentCity != "Fetching location..." &&
              _currentCity != "Location disabled" &&
              _currentCity != "Enable location" &&
              _currentCity != "Unable to fetch location";

          if (!hasGoodLocation) {
            if (isRetailer) {
              pickupLatLng = _getRetailerFallbackLatLng(user);
              pickupAddr = _getRetailerFallbackAddress(user);
            } else {
              pickupLatLng = null;
              pickupAddr = "";
            }
          }

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RouteVehicleScreen(
                pickupLatLng: pickupLatLng,
                pickupAddress: pickupAddr,
                dropLatLng: targetLatLng,
                dropAddress: targetAddress,
              ),
            ),
          );
        } else {
          // Shared location â†' Pickup. Opens with pickup pre-filled; the drop
          // field is focused by default so the user can type it immediately.
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RouteVehicleScreen(
                pickupLatLng: targetLatLng,
                pickupAddress: targetAddress!,
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          SnackBarToastMessage.showSnackBar(
            context,
            "Could not parse shared location coordinates.",
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        SnackBarToastMessage.showSnackBar(
          context,
          "Error processing location intent: ${e.toString()}",
        );
      }
    }
  }

  Future<void> _loadUserData() async {
    await Provider.of<UserController>(context, listen: false).getUserDetails();
    if (mounted) {
      final user = Provider.of<UserController>(context, listen: false);
      if (user.getUserType.toLowerCase() == 'retailer') {
        if (!_isRealGps &&
            (_currentLatLng == null || _currentCity == "Fetching location...") &&
            user.getAddress.isNotEmpty) {
          setState(() {
            _currentLatLng = _getRetailerFallbackLatLng(user);
            _currentCity = _getRetailerFallbackAddress(user);
          });
        }
        Provider.of<RetailerHomeController>(context, listen: false)
            .getRetailerHome(context);
        _bookingTrackerTimer?.cancel();
        _bookingTrackerTimer =
            Timer.periodic(const Duration(seconds: 20), (timer) async {
          if (!mounted) {
            timer.cancel();
            return;
          }
          final homeCtrl =
              Provider.of<RetailerHomeController>(context, listen: false);
          await homeCtrl.getRetailerHome(context);
          // No more active bookings — stop polling until the next Home load.
          if (homeCtrl.ongoingBookings.isEmpty) timer.cancel();
        });
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _currentCity = "Location disabled");
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _currentCity = "Enable location");
        return;
      }

      final last = await Geolocator.getLastKnownPosition();
      if (last != null) _updateLocation(last);

      final current = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 8));
      _updateLocation(current);
      _lastLocationFetchAt = DateTime.now();
    } catch (_) {
      if (mounted && !_isRealGps) setState(() => _currentCity = "Unable to fetch location");
    }
  }

  Future<void> _updateLocation(Position pos) async {
    if (!mounted) return;
    setState(() {
      _currentLatLng = LatLng(pos.latitude, pos.longitude);
      _isRealGps = true;
      _locationServiceDeclined = false;
    });

    // Only one geocoding call at a time â€” prevents double API calls when
    // getLastKnownPosition and getCurrentPosition both trigger this method
    if (_geocodingInProgress) return;

    // Skip geocoding if the cached address is still valid (user within 500 m)
    if (_lastGeocodedLatLng != null && _lastGeocodedCity != null) {
      final double moved = Geolocator.distanceBetween(
        _lastGeocodedLatLng!.latitude, _lastGeocodedLatLng!.longitude,
        pos.latitude, pos.longitude,
      );
      if (moved < 500) {
        if (mounted) setState(() => _currentCity = _lastGeocodedCity!);
        return;
      }
    }

    _geocodingInProgress = true;

    try {
      final _gUri = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?latlng=${pos.latitude},${pos.longitude}&key=${AppConstant.googleApiKey}&language=en');
      final _gResp = await http.get(_gUri).timeout(const Duration(seconds: 6));
      if (_gResp.statusCode == 200) {
        final decoded = jsonDecode(_gResp.body);
        final results = (decoded['results'] as List? ?? []);
        if (results.isNotEmpty) {
          final formattedAddress = results.first['formatted_address'] as String? ?? '';
          if (formattedAddress.isNotEmpty) {
            _lastGeocodedLatLng = LatLng(pos.latitude, pos.longitude);
            _lastGeocodedCity = formattedAddress;
            if (mounted) {
              setState(() => _currentCity = formattedAddress);
            }
            return;
          }
        }
      }
      if (mounted) {
        setState(() => _currentCity = "${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)}");
      }
    } catch (_) {
      if (mounted) {
        setState(() => _currentCity = "${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)}");
      }
    } finally {
      _geocodingInProgress = false;
    }
  }

  // Re-fetches GPS before opening booking rather than trusting a fix from
  // hours ago — this screen is the persistent home tab, so a stale one-time
  // fix could otherwise sit cached for the entire app session and set pickup
  // to wherever the retailer was hours ago instead of where they are now.
  // If the last fix is still recent, though, skip the blocking wait: refresh
  // it silently in the background instead (LocationSelectionScreen also
  // refreshes GPS itself once it opens, so nothing is lost by not blocking).
  Future<void> _ensureFreshLocation() async {
    if (!mounted) return;

    final bool hasRecentFix = _isRealGps &&
        _currentLatLng != null &&
        _lastLocationFetchAt != null &&
        DateTime.now().difference(_lastLocationFetchAt!) <
            const Duration(seconds: 30);

    if (hasRecentFix) {
      unawaited(_getCurrentLocation());
      return;
    }

    // GPS was off at startup and the retailer ignored that prompt — ask
    // again now that they're actively trying to search for a location. If
    // they still decline, _resolvePickupLatLngAndAddress leaves pickup empty
    // instead of guessing the business address.
    if (!await Geolocator.isLocationServiceEnabled()) {
      final enabled = await LocationServiceHelper.ensureEnabled();
      if (!mounted) return;
      setState(() => _locationServiceDeclined = !enabled);
      if (!enabled) return;
    }

    bool dialogShown = false;
    try {
      dialogShown = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColor.themeColor),
        ),
      );
      await _getCurrentLocation();
    } catch (_) {
    } finally {
      if (dialogShown && mounted) {
        Navigator.pop(context);
      }
    }
  }

  // Resolves what to use as the pickup point right now: the freshest GPS fix
  // if we have one, otherwise the retailer's saved business address — unless
  // the retailer was just asked to turn GPS on (again) and declined, in
  // which case we don't guess and leave pickup empty.
  (LatLng?, String) _resolvePickupLatLngAndAddress() {
    if (_locationServiceDeclined) return (null, "");

    final user = Provider.of<UserController>(context, listen: false);
    final isRetailer = user.getUserType.toLowerCase() == 'retailer';

    LatLng? pickupLatLng = _currentLatLng;
    String pickupAddress = _currentCity;

    if (!_isRealGps &&
        (_currentLatLng == null ||
            _currentCity == "Fetching location..." ||
            _currentCity == "Location disabled" ||
            _currentCity == "Enable location" ||
            _currentCity == "Unable to fetch location")) {
      if (isRetailer) {
        pickupLatLng = _getRetailerFallbackLatLng(user);
        pickupAddress = _getRetailerFallbackAddress(user);
      } else {
        pickupLatLng = null;
        pickupAddress = "";
      }
    }
    return (pickupLatLng, pickupAddress);
  }

  Future<void> _openLocationSelectionScreen({
    LatLng? initialPickupLatLng,
    required String initialPickupAddress,
    LatLng? initialDropLatLng,
    String? initialDropAddress,
    String? initialDropContactName,
    String? initialDropContactPhone,
    String? vehicleName,
  }) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RouteVehicleScreen(
          pickupLatLng: initialPickupLatLng,
          pickupAddress: initialPickupAddress,
          dropLatLng: initialDropLatLng,
          dropAddress: initialDropAddress,
          dropContactName: initialDropContactName ?? '',
          dropContactPhone: initialDropContactPhone ?? '',
          preSelectedVehicleName: vehicleName,
        ),
      ),
    );
  }

  Future<void> _openLocationSelection({String? vehicleName}) async {
    await _ensureFreshLocation();
    if (!mounted) return;
    final (pickupLatLng, pickupAddress) = _resolvePickupLatLngAndAddress();
    await _openLocationSelectionScreen(
      initialPickupLatLng: pickupLatLng,
      initialPickupAddress: pickupAddress,
      vehicleName: vehicleName,
    );
  }

  // Tapping a previous drop location: pickup = current location, drop = the
  // tapped location — skips the choose-location screen entirely and goes
  // straight to vehicle selection.
  Future<void> _selectPreviousLocation(Map<String, dynamic> drop) async {
    final lat = drop['lat'];
    final lng = drop['lng'];
    if (lat == null || lng == null) return;

    await _ensureFreshLocation();
    if (!mounted) return;
    final (pickupLatLng, pickupAddress) = _resolvePickupLatLngAndAddress();
    if (pickupLatLng == null || pickupAddress.isEmpty) {
      SnackBarToastMessage.showSnackBar(
          context, 'Unable to detect your current location');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RouteVehicleScreen(
          pickupLatLng:      pickupLatLng,
          pickupAddress:     pickupAddress,
          pickupContactName:  '',
          pickupContactPhone: '',
          dropLatLng:  LatLng((lat as num).toDouble(), (lng as num).toDouble()),
          dropAddress: (drop['address'] ?? '').toString(),
          dropContactName:  (drop['contact_name']  ?? '').toString(),
          dropContactPhone: (drop['contact_phone'] ?? '').toString(),
          skipLocationPhase: true,
        ),
      ),
    );
  }

  Future<void> _loadCoinBalance() async {
    try {
      final provider = Provider.of<PostApiProvider>(context, listen: false);
      final res = await provider.getCoinsBalanceApi(context);
      debugPrint('[CoinBalance] raw response: $res');
      if (res != null && res['success'] == true) {
        final data = res['data'] as Map<String, dynamic>?;
        final rawBalance = data?['coin_balance'];
        debugPrint('[CoinBalance] parsed coin_balance: $rawBalance (${rawBalance.runtimeType})');
        if (data != null && mounted) {
          setState(() {
            _coinBalance = (rawBalance as num?)?.toInt() ?? 0;
          });
        }
      } else {
        debugPrint('[CoinBalance] request did not succeed: success=${res?['success']}, message=${res?['message']}');
      }
    } catch (e) {
      debugPrint('[CoinBalance] loadCoinBalance error: $e');
    }
  }

  // Pulls the retailer's currently-visible coin missions and keeps the most
  // relevant unclaimed one for the "New mission for you" home banner —
  // prefers one that's ready to claim, else the closest to completion.
  Future<void> _loadMissions() async {
    try {
      final provider = Provider.of<PostApiProvider>(context, listen: false);
      final res = await provider.getCoinMissionsApi(context);
      if (res == null || res['success'] != true) return;
      final list = List<Map<String, dynamic>>.from(res['data'] ?? []);
      final open = list.where((m) => m['status'] != 'claimed').toList();
      open.sort((a, b) {
        int rank(Map<String, dynamic> m) => m['status'] == 'completed' ? 0 : 1;
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        return ((a['remaining'] ?? 1e9) as num).compareTo((b['remaining'] ?? 1e9) as num);
      });
      if (!mounted) return;
      setState(() {
        _availableMissions = open.length;
        _topMission = open.isNotEmpty ? open.first : null;
      });
    } catch (e) {
      debugPrint('[Missions] load error: $e');
    }
  }

  Future<void> _loadHomeAndShopAddresses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _homeAddress = prefs.getString('retailer_home_address') ?? "";
        _homeLat = prefs.getDouble('retailer_home_lat');
        _homeLng = prefs.getDouble('retailer_home_lng');

        _shopAddress = prefs.getString('retailer_shop_address') ?? "";
        _shopLat = prefs.getDouble('retailer_shop_lat');
        _shopLng = prefs.getDouble('retailer_shop_lng');
      });
    } catch (e) {
      debugPrint('loadHomeAndShopAddresses error: $e');
    }
  }

  Future<void> _loadSavedAddresses() async {
    try {
      final data = await getData('user/saved_addresses', context, headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
      });
      if (!mounted) return;
      if (data != null && data['success'] == true) {
        setState(() {
          _savedAddresses = List<Map<String, dynamic>>.from(data['data'] ?? []);
        });
      }
    } catch (e) {
      debugPrint('loadSavedAddresses error: $e');
    }
  }

  // "Deliver Here" card — pick a saved location and go straight to the
  // vehicle-choosing screen (skips the pickup/drop location phase entirely).
  void _showSavedAddressesSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Deliver to a Saved Location',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: AppFont.fontFamily,
                  ),
                ),
              ),
              if (_savedAddresses.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      const Icon(Icons.bookmark_border_rounded, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text(
                        'No saved addresses yet',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                          fontFamily: AppFont.fontFamily,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColor.themeColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () async {
                          Navigator.pop(context);
                          await showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            isScrollControlled: true,
                            builder: (_) => _SaveAddressSheet(
                              currentLatLng: _currentLatLng,
                            ),
                          );
                          _loadSavedAddresses();
                        },
                        child: const Text('Add New Address', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _savedAddresses.length,
                    itemBuilder: (context, index) {
                      final loc = _savedAddresses[index];
                      final label = loc['label']?.toString() ?? 'Address';
                      final iconData = _savedAddressIcon(label);
                      final contactName  = loc['contact_name']?.toString()  ?? '';
                      final contactPhone = loc['contact_phone']?.toString() ?? '';
                      final titleLine = contactName.isNotEmpty ? '$label · $contactName' : label;

                      return ListTile(
                        leading: Icon(iconData, color: AppColor.themeColor),
                        title: Text(
                          titleLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            fontFamily: AppFont.fontFamily,
                            color: AppColor.fontColor,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loc['address']?.toString() ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: AppFont.fontFamily,
                                fontSize: 12.5,
                                color: AppColor.hintTextColor,
                              ),
                            ),
                            if (contactPhone.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                contactPhone,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: AppFont.fontFamily,
                                  fontSize: 12,
                                  color: AppColor.hintTextColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                        isThreeLine: true,
                        onTap: () {
                          Navigator.pop(context);
                          final mapForPrevious = {
                            'address':       loc['address'],
                            'lat':           _toDouble(loc['lat']),
                            'lng':           _toDouble(loc['lng']),
                            'contact_name':  contactName,
                            'contact_phone': contactPhone,
                          };
                          _selectPreviousLocation(mapForPrevious);
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // "Save Address" card — manage (edit/delete) existing saved addresses,
  // with an Add New Address button.
  void _showManageSavedAddressesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> refresh() async {
              await _loadSavedAddresses();
              setSheetState(() {});
            }

            Future<void> openAddOrEdit({Map<String, dynamic>? existing}) async {
              await showModalBottomSheet(
                context: sheetContext,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => _SaveAddressSheet(
                  currentLatLng: _currentLatLng,
                  existing: existing,
                ),
              );
              await refresh();
            }

            Future<void> deleteAddress(Map<String, dynamic> loc) async {
              final id = loc['_id']?.toString();
              if (id == null || id.isEmpty) return;
              final confirmed = await showDialog<bool>(
                context: sheetContext,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('Delete Address', style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600)),
                  content: Text(
                    'Remove "${loc['label'] ?? 'this address'}" from your saved addresses?',
                    style: const TextStyle(fontFamily: AppFont.fontFamily),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              final res = await deleteJsonData(
                'user/saved_address/$id',
                {},
                sheetContext,
                headers: {'Authorization': 'Bearer ${AppConstant.token}'},
              );
              if (res != null && res['success'] == true) {
                await refresh();
              }
            }

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.75),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Manage Saved Addresses',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          fontFamily: AppFont.fontFamily,
                        ),
                      ),
                    ),
                    if (_savedAddresses.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        child: Column(
                          children: [
                            Icon(Icons.bookmark_border_rounded, size: 48, color: Colors.grey),
                            SizedBox(height: 12),
                            Text(
                              'No saved addresses yet',
                              style: TextStyle(color: Colors.grey, fontSize: 14, fontFamily: AppFont.fontFamily),
                            ),
                          ],
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _savedAddresses.length,
                          itemBuilder: (context, index) {
                            final loc = _savedAddresses[index];
                            final label = loc['label']?.toString() ?? 'Address';
                            final iconData = _savedAddressIcon(label);
                            final contactName  = loc['contact_name']?.toString()  ?? '';
                            final contactPhone = loc['contact_phone']?.toString() ?? '';
                            final titleLine = contactName.isNotEmpty ? '$label · $contactName' : label;

                            return ListTile(
                              leading: Icon(iconData, color: AppColor.themeColor),
                              title: Text(
                                titleLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  fontFamily: AppFont.fontFamily,
                                  color: AppColor.fontColor,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    loc['address']?.toString() ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: AppFont.fontFamily,
                                      fontSize: 12.5,
                                      color: AppColor.hintTextColor,
                                    ),
                                  ),
                                  if (contactPhone.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      contactPhone,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: AppFont.fontFamily,
                                        fontSize: 12,
                                        color: AppColor.hintTextColor,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: AppColor.themeColor, size: 20),
                                    onPressed: () => openAddOrEdit(existing: loc),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                                    onPressed: () => deleteAddress(loc),
                                  ),
                                ],
                              ),
                              onTap: () => openAddOrEdit(existing: loc),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColor.themeColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => openAddOrEdit(),
                          icon: const Icon(Icons.add_rounded, color: Colors.white),
                          label: const Text('Add New Address', style: TextStyle(color: Colors.white, fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) => _loadSavedAddresses());
  }

  IconData _savedAddressIcon(String label) {
    final l = label.toLowerCase();
    if (l == 'home') return Icons.home_outlined;
    if (l == 'work' || l == 'office') return Icons.corporate_fare_rounded;
    if (l.contains('godown') || l.contains('warehouse')) return Icons.warehouse_outlined;
    return Icons.place_outlined;
  }

  // Tapping a saved address: pickup = current location, drop = the saved
  // address (with its own contact if one was attached when saved) — same
  // shortcut pattern as tapping a recent location.
  Future<void> _selectSavedAddress(Map<String, dynamic> addr) async {
    final lat = addr['lat'];
    final lng = addr['lng'];
    if (lat == null || lng == null) return;

    await _ensureFreshLocation();
    if (!mounted) return;
    final (pickupLatLng, pickupAddress) = _resolvePickupLatLngAndAddress();
    if (pickupLatLng == null || pickupAddress.isEmpty) {
      SnackBarToastMessage.showSnackBar(
          context, 'Unable to detect your current location');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RouteVehicleScreen(
          pickupLatLng:      pickupLatLng,
          pickupAddress:     pickupAddress,
          pickupContactName:  '',
          pickupContactPhone: '',
          dropLatLng:  LatLng((lat as num).toDouble(), (lng as num).toDouble()),
          dropAddress: (addr['address'] ?? '').toString(),
          dropContactName:  (addr['contact_name']  ?? '').toString(),
          dropContactPhone: (addr['contact_phone'] ?? '').toString(),
          skipLocationPhase: true,
        ),
      ),
    );
  }

  Future<void> _addHomeOrShopAddress(String type) async {
    try {
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => MapPickerScreen(
            initialLocation: _currentLatLng ?? const LatLng(22.7196, 75.8577),
            isDropLocation: true,
          ),
        ),
      );
      if (result != null && mounted) {
        final LatLng location = result['location'] as LatLng;
        final String addr     = result['address']?.toString() ?? '';

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('retailer_${type}_address', addr);
        await prefs.setDouble('retailer_${type}_lat', location.latitude);
        await prefs.setDouble('retailer_${type}_lng', location.longitude);

        _loadHomeAndShopAddresses();
      }
    } catch (e) {
      debugPrint('addHomeOrShopAddress error: $e');
    }
  }

  void _manageShortcutAddress(String type, String currentAddr, double lat, double lng) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Quick Address: ${type.toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  currentAddr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.navigation_outlined, color: AppColor.themeColor),
                title: const Text('Book Shipment to this location'),
                onTap: () {
                  Navigator.pop(context);
                  _selectShortcutLocation(currentAddr, lat, lng);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Colors.blue),
                title: const Text('Change Location'),
                onTap: () {
                  Navigator.pop(context);
                  _addHomeOrShopAddress(type);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove shortcut'),
                onTap: () async {
                  Navigator.pop(context);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('retailer_${type}_address');
                  await prefs.remove('retailer_${type}_lat');
                  await prefs.remove('retailer_${type}_lng');
                  _loadHomeAndShopAddresses();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _selectShortcutLocation(String address, double lat, double lng) async {
    await _ensureFreshLocation();
    if (!mounted) return;
    final (pickupLatLng, pickupAddress) = _resolvePickupLatLngAndAddress();
    if (pickupLatLng == null || pickupAddress.isEmpty) {
      SnackBarToastMessage.showSnackBar(
          context, 'Unable to detect your current location');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RouteVehicleScreen(
          pickupLatLng:      pickupLatLng,
          pickupAddress:     pickupAddress,
          pickupContactName:  '',
          pickupContactPhone: '',
          dropLatLng:  LatLng(lat, lng),
          dropAddress: address,
          dropContactName:  '',
          dropContactPhone: '',
          skipLocationPhase: true,
        ),
      ),
    );
  }

  bool _isTerminalBookingStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'delivered' ||
        normalized == 'cancelled' ||
        normalized == 'rejected';
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  void _bookAgain(Map item) {
    final Map pickupLoc = item['pickup_location'] is Map ? item['pickup_location'] : {};
    final Map dropLoc   = item['dropoff_location'] is Map ? item['dropoff_location'] : {};

    final double? pickupLat = _toDouble(pickupLoc['latitude']);
    final double? pickupLng = _toDouble(pickupLoc['longitude']);
    final double? dropLat   = _toDouble(dropLoc['latitude']);
    final double? dropLng   = _toDouble(dropLoc['longitude']);

    if (pickupLat == null || pickupLng == null || dropLat == null || dropLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location details missing for this booking.')),
      );
      return;
    }

    // Multi-drop bookings carry every stop (final drop included) in extra_drops.
    // Route those through the main vehicle-selection flow (RouteVehicleScreen
    // → NewConfirmScreen), pre-filled and skipped straight to the booking
    // phase, so stops/contacts aren't dropped and "Book Again" lands on the
    // same screen as a normal booking would.
    final List<dynamic> extraDrops = item['extra_drops'] is List ? item['extra_drops'] as List : [];
    if (extraDrops.length > 1) {
      final validDrops = <Map<String, dynamic>>[];
      for (final d in extraDrops) {
        if (d is! Map) continue;
        final lat = _toDouble(d['latitude']);
        final lng = _toDouble(d['longitude']);
        if (lat == null || lng == null) continue;
        validDrops.add({
          'address':      (d['address'] ?? '').toString(),
          'lat':          lat,
          'lng':          lng,
          'contactName':  (d['contact_name']  ?? '').toString(),
          'contactPhone': (d['contact_phone'] ?? '').toString(),
        });
      }
      if (validDrops.length > 1) {
        // extra_drops' last entry is the final destination — the rest are
        // the intermediate stops RouteVehicleScreen's _extraStops expects.
        final finalStop = validDrops.removeLast();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RouteVehicleScreen(
              pickupLatLng:        LatLng(pickupLat, pickupLng),
              pickupAddress:       (pickupLoc['address'] ?? '').toString(),
              pickupContactName:   (item['sender_name']  ?? item['customer_name']  ?? '').toString(),
              pickupContactPhone:  (item['sender_phone'] ?? item['customer_phone'] ?? '').toString(),
              dropLatLng:          LatLng(finalStop['lat'] as double, finalStop['lng'] as double),
              dropAddress:         finalStop['address'] as String,
              dropContactName:     finalStop['contactName'] as String,
              dropContactPhone:    finalStop['contactPhone'] as String,
              initialExtraStops:   validDrops,
              skipLocationPhase:   true,
            ),
          ),
        );
        return;
      }
    }

    int wheelCount(String tag) {
      final t = tag.toLowerCase();
      if (t.contains('2w') || t.contains('scooter') || t.contains('bike')) return 2;
      if (t.contains('3w') || t.contains('loader'))  return 3;
      return 4;
    }

    String extractId(dynamic field) {
      if (field == null) return '';
      if (field is Map) return (field['_id'] ?? '').toString();
      return field.toString();
    }

    final String requiredTag = (item['required_tag'] ?? item['vehicle_category'] ?? '').toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RetailerConfirmScreen(
          vehicleTypeId:    extractId(item['vehicleType_id'] ?? item['vehicle_type_id']),
          subVehicleTypeId: extractId(item['subVehicleType_id'] ?? item['sub_vehicle_type_id']),
          vehicleData: {
            'name':               (item['requested_vehicle_name'] ?? item['display_vehicle_name'] ?? 'Vehicle').toString(),
            'wheelCount':         wheelCount(requiredTag),
            'vehicleCategory':    (item['vehicle_category'] ?? requiredTag).toString(),
            'pricingModifier':    '1.0',
            'vehicleKey':         (item['vehicle_key'] ?? '').toString(),
            'requiredTag':        requiredTag,
            'bookingFlow':        (item['booking_flow'] ?? 'retailer').toString(),
            'displayVehicleName': (item['display_vehicle_name'] ?? '').toString(),
          },
          pickupData: {
            'address': (pickupLoc['address'] ?? '').toString(),
            'lat': pickupLat,
            'lng': pickupLng,
          },
          dropData: {
            'address': (dropLoc['address'] ?? '').toString(),
            'lat': dropLat,
            'lng': dropLng,
          },
          rawDistanceKm:  _toDouble(item['distance_in_km'] ?? item['rounded_distance_km'] ?? item['actual_distance_km']) ?? 0.0,
          estimatedFare:  int.tryParse((item['booking_price'] ?? '0').toString()) ?? 0,
          subVehicleTypeList: const [],
          initialReceiverName:  (item['receiver_name']  ?? '').toString(),
          initialReceiverPhone: (item['receiver_phone'] ?? '').toString(),
          initialSenderName:    (item['sender_name']  ?? item['customer_name']  ?? '').toString(),
          initialSenderPhone:   (item['sender_phone'] ?? item['customer_phone'] ?? '').toString(),
          initialNote:          (item['note'] ?? '').toString(),
          initialGoodsTypeId:   extractId(item['item_category_id']),
          initialIsPriorityPickup: item['isPriorityPickup'] == true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final user = Provider.of<UserController>(context);

    // Filter recent drops + favorite locations for the lists
    final locations = _displayedLocations;

    return PopScope(
      canPop: false,
      onPopInvoked: (_) {
        final now = DateTime.now();
        const maxDuration = Duration(seconds: 2);
        final isWarning = _homeLastPressed == null ||
            now.difference(_homeLastPressed!) > maxDuration;
        if (isWarning) {
          _homeLastPressed = now;
          SnackBarToastMessage.showSnackBar(
              context, AppLanguage.pressAgainExitText[language]);
        } else {
          SystemChannels.platform.invokeMethod('SystemNavigator.pop');
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xffF4F6F9), // Light background matching mockup
        drawer: Drawer(
          backgroundColor: Colors.white,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(
                  color: AppColor.themeColor,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: user.getUserImage.isNotEmpty
                          ? Image.network(
                              "${AppConfigProvider.imgUrl}${user.getUserImage}",
                              height: 60,
                              width: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Image.asset(
                                AppImage.userdummyimage,
                                height: 60,
                                width: 60,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Image.asset(
                              AppImage.userdummyimage,
                              height: 60,
                              width: 60,
                              fit: BoxFit.cover,
                            ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      user.getUserName.isNotEmpty ? user.getUserName : 'User',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      user.getUserMobile,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Home'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.assignment_outlined),
                title: const Text('Orders'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CustomBottomNav(
                        userType: UserType.retailer,
                        initialIndex: 1, // Orders
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.stars_outlined),
                title: const Text('Coins'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CustomBottomNav(
                        userType: UserType.retailer,
                        initialIndex: 2, // Coins
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('Account'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CustomBottomNav(
                        userType: UserType.retailer,
                        initialIndex: 3, // Account
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Help & Support'),
                onTap: () {
                  Navigator.pop(context);
                  Get.to(() => const HelpAndSupportscreen());
                },
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            // ── Top Header Container ──────────────────────────────────────────
            Container(
              color: AppColor.themeColor,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + size.height * 0.012,
                bottom: size.height * 0.018,
                left: size.width * 0.045,
                right: size.width * 0.035,
              ),
              child: Row(
                children: [
                  // Hamburger Menu Icon
                  GestureDetector(
                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                    child: const Icon(Icons.menu, color: Colors.white, size: 28),
                  ),
                  SizedBox(width: size.width * 0.035),

                  // Greeting & Location Dropdown
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                "Hey, ${user.getUserName.isNotEmpty ? user.getUserName : 'User'}",
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: AppFont.fontFamily,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              "👋",
                              style: TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        GestureDetector(
                          onTap: () => _openLocationSelection(),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(AppImage.address, height: 11, width: 9, color: Colors.white70),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  "Shop: ${user.getAddress.isNotEmpty ? user.getAddress : 'Scheme 54, Indore'}",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontFamily: AppFont.fontFamily,
                                    fontWeight: FontWeight.w400,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 16),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Coin Ticker Pill
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CoinWalletScreen()),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 18,
                            width: 18,
                            decoration: const BoxDecoration(
                              color: Colors.amber,
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(Icons.star, color: Colors.white, size: 12),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _coinBalance.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Noticeboard entry
                  InkWell(
                    key: _noticeboardIconKey,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const NoticeboardScreen()),
                    ),
                    borderRadius: BorderRadius.circular(24),
                    child: const Icon(Icons.campaign_outlined,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 10),

                  // Notification Bell with Badge
                  Consumer<NotificationUnreadCountController>(
                    builder: (_, nc, __) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        InkWell(
                          onTap: () async {
                            await Get.to(() => const NotificationScreen());
                            if (mounted) {
                              Provider.of<NotificationUnreadCountController>(
                                      context, listen: false)
                                  .getUnreadNotificationCount(context);
                            }
                          },
                          borderRadius: BorderRadius.circular(24),
                          child: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 28),
                        ),
                        if (nc.hasUnread)
                          Positioned(
                            right: 2,
                            top: 2,
                            child: Container(
                              height: 9,
                              width: 9,
                              decoration: const BoxDecoration(
                                  color: Colors.red, shape: BoxShape.circle),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Scrollable Body ──────────────────────────────────────────────
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                color: AppColor.themeColor,
                child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics()),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: size.width * 0.045),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),

                      // Promo banner carousel — backend-driven (admin panel).
                      // Renders nothing while loading or when there are no
                      // active banners for the retailer audience.
                      _PromoBannerCarousel(key: ValueKey('promo_$_refreshTick')),

                      // "New mission for you" — shown above the search bar
                      // whenever the retailer has an unclaimed coin mission.
                      if (_topMission != null)
                        Padding(
                          key: _missionBannerKey,
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _MissionHomeBanner(
                            mission: _topMission!,
                            count: _availableMissions,
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const CoinMissionsScreen()),
                              );
                              _loadMissions();
                              _loadCoinBalance();
                            },
                            onClaimSuccess: () {
                              _loadMissions();
                              _loadCoinBalance();
                            },
                          ),
                        ),

                      // Destination Search Bar — animated gradient border + rotating hint
                      GestureDetector(
                        key: _bookRideSearchBarKey,
                        onTap: () => _openLocationSelection(),
                        child: _AnimatedGradientBorder(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xffF6F7FB),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              children: const [
                                Icon(Icons.search_rounded, color: AppColor.themeColor, size: 22),
                                SizedBox(width: 12),
                                Expanded(child: _RotatingSearchHint()),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Recent searches (last 5)
                      if (locations.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "RECENT LOCATIONS",
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 0.8,
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => _openLocationSelection(),
                              child: const Text(
                                "View All",
                                style: TextStyle(
                                  color: Colors.blueAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: math.min(locations.length, 5),
                          itemBuilder: (context, index) {
                            final loc = locations[index];
                            final isFavorite = _favoriteLocations.any(
                                (f) => _locationKey(f) == _locationKey(loc));

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade100),
                              ),
                              child: ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                leading: const Icon(Icons.access_time_outlined, color: Colors.grey),
                                title: Text(
                                  (loc['address'] ?? '').toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.black,
                                  ),
                                ),
                                trailing: GestureDetector(
                                  onTap: () => _toggleFavoriteLocation(loc),
                                  child: Icon(
                                    isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                                    color: isFavorite ? Colors.amber : Colors.grey,
                                    size: 22,
                                  ),
                                ),
                                onTap: () => _selectPreviousLocation(loc),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Side-by-side Dynamic Quick Action Cards (Rapido style)
                      Row(
                        children: [
                          _DynamicHomeCard(
                            key: const ValueKey('save_address_card'),
                            category: "MANAGE PLACES",
                            title: "Save Address",
                            images: const [AppImage.threeDPinBox],
                            onTap: _showManageSavedAddressesSheet,
                          ),
                          const SizedBox(width: 12),
                          _DynamicHomeCard(
                            key: const ValueKey('deliver_saved_card'),
                            category: "SAVED LOCATIONS",
                            title: "Deliver Here",
                            images: const [
                              AppImage.threeDBike,
                              AppImage.threeDScooter,
                              AppImage.threeDEloader,
                              AppImage.threeDDiesel3w,
                              AppImage.threeDTataace,
                            ],
                            onTap: _showSavedAddressesSheet,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Movigo Promotional/Marketing Banner
                      const _MovigoStaticBanner(),
                      const SizedBox(height: 14),

                      // Noticeboard — auto-scrolling banner of active announcements
                      _NoticeboardBanner(key: ValueKey('notice_$_refreshTick')),

                      // Active-booking tracker (retailer only)
                      Consumer2<UserController, RetailerHomeController>(
                        builder: (_, u, homeCtrl, __) {
                          final isRetailer = u.getUserType.toLowerCase() == 'retailer';
                          if (!isRetailer || homeCtrl.ongoingBookings.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          final booking = Map<String, dynamic>.from(
                              homeCtrl.ongoingBookings.first as Map);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: _ActiveBookingTracker(
                              booking: booking,
                              userId: u.getUserId,
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// Slim, always-visible top ticker promoting the coins loyalty program.
// Auto-scrolls its message continuously (no user gesture needed) and has a
// "New mission for you" — home-screen mission banner, mirroring the driver
// app's mission caution banner (eyebrow + title + progress bar + Claim pill).
// Shown above the destination search bar whenever the retailer has an
// unclaimed coin mission; tapping opens the full missions screen.
class _MissionHomeBanner extends StatefulWidget {
  final Map<String, dynamic> mission;
  final int count;
  final VoidCallback onTap;
  final VoidCallback? onClaimSuccess;

  const _MissionHomeBanner({
    super.key,
    required this.mission,
    required this.count,
    required this.onTap,
    this.onClaimSuccess,
  });

  @override
  State<_MissionHomeBanner> createState() => _MissionHomeBannerState();
}

class _MissionHomeBannerState extends State<_MissionHomeBanner> {
  bool _claiming = false;

  int _asInt(dynamic v) => (v is int) ? v : int.tryParse('${v ?? 0}') ?? 0;

  Future<void> _handleDirectClaim() async {
    final id = widget.mission['_id']?.toString() ?? '';
    if (id.isEmpty || _claiming) return;

    setState(() => _claiming = true);
    try {
      final provider = Provider.of<PostApiProvider>(context, listen: false);
      final res = await provider.claimCoinMissionApi(context, missionId: id);
      if (!mounted) return;
      setState(() => _claiming = false);

      final bool success = res?['success'] == true;
      final int reward = _asInt(widget.mission['reward_coins']);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0F172A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF34D399), width: 1.2),
            ),
            content: Row(
              children: [
                const Text('🎉', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Success! +$reward Coins added to your wallet.',
                    style: const TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        widget.onClaimSuccess?.call();
      } else {
        final String message = ((res?['message'] as List?)?.isNotEmpty == true)
            ? res!['message'][0].toString()
            : 'Could not claim mission reward';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _claiming = false);
      debugPrint('[MissionHomeBanner] claim error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isHindi = language == 1;
    final bool isReadyToClaim = widget.mission['status'] == 'completed';

    final String titleEn = (widget.mission['title_en'] ?? '').toString();
    final String titleHi = (widget.mission['title_hi'] ?? '').toString();
    final String displayTitle = isHindi && titleHi.isNotEmpty
        ? titleHi
        : (titleEn.isNotEmpty ? titleEn : 'Mission Reward');

    final int reward = _asInt(widget.mission['reward_coins']);
    final int remaining = _asInt(widget.mission['remaining']);
    final int total = _asInt(widget.mission['target_orders']) > 0
        ? _asInt(widget.mission['target_orders'])
        : (remaining <= 0 ? 1 : remaining);
    final int done = (total - remaining).clamp(0, total);
    final double targetProgress =
        total > 0 ? (done / total).clamp(0.0, 1.0) : (isReadyToClaim ? 1.0 : 0.0);

    final num minFare = (widget.mission['min_order_fare'] ?? 0) as num;
    final String iconEmoji = widget.mission['icon']?.toString() ?? '🎯';

    // Dynamic Theme Colors:
    // Active: Deep Obsidian with warm Amber/Gold highlights
    // Ready to Claim: Deep Emerald with Mint & Gold celebration
    final Color cardBorderColor = isReadyToClaim
        ? const Color(0xFF34D399).withOpacity(0.55)
        : const Color(0xFFFFB800).withOpacity(0.35);

    final List<Color> cardGradient = isReadyToClaim
        ? const [Color(0xFF044E3B), Color(0xFF065F46), Color(0xFF0F3E33)]
        : const [Color(0xFF0F172A), Color(0xFF1E293B)];

    final Color accentGlow = isReadyToClaim
        ? const Color(0xFF10B981)
        : const Color(0xFFFFB800);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: cardGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: cardBorderColor, width: 1.3),
          boxShadow: [
            BoxShadow(
              color: accentGlow.withOpacity(0.16),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.20),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              // Ambient radial glow orbs
              Positioned(
                right: -20,
                top: -20,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentGlow.withOpacity(0.12),
                  ),
                ),
              ),
              Positioned(
                left: -30,
                bottom: -30,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (isReadyToClaim ? const Color(0xFF059669) : const Color(0xFFFF8F00))
                        .withOpacity(0.08),
                  ),
                ),
              ),

              // Main content
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Header Row: Status Chip + Count + Reward Pill
                    Row(
                      children: [
                        // Status Eyebrow Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isReadyToClaim
                                ? const Color(0xFF34D399).withOpacity(0.18)
                                : const Color(0xFFFFB800).withOpacity(0.16),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isReadyToClaim
                                  ? const Color(0xFF34D399).withOpacity(0.5)
                                  : const Color(0xFFFFB800).withOpacity(0.45),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isReadyToClaim ? Icons.celebration_rounded : Icons.bolt_rounded,
                                size: 12,
                                color: isReadyToClaim ? const Color(0xFF34D399) : const Color(0xFFFFB800),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isReadyToClaim
                                    ? (isHindi ? 'मिशन पूरा हुआ!' : 'MISSION COMPLETED')
                                    : (isHindi ? 'सक्रिय मिशन' : 'ACTIVE MISSION'),
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: AppFont.fontFamily,
                                  color: isReadyToClaim ? const Color(0xFF34D399) : const Color(0xFFFFB800),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),

                        if (widget.count > 1) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '+${widget.count - 1} more',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white70,
                                fontFamily: AppFont.fontFamily,
                              ),
                            ),
                          ),
                        ],

                        if (minFare > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Min ₹${minFare.toInt()}',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: Colors.white60,
                                fontFamily: AppFont.fontFamily,
                              ),
                            ),
                          ),
                        ],

                        const Spacer(),

                        // Reward Gold Chip (1 Coin = ₹1)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD54F), Color(0xFFFF9800)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF9800).withOpacity(0.35),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('🪙', style: TextStyle(fontSize: 11)),
                              const SizedBox(width: 4),
                              Text(
                                '+$reward Coins (₹$reward)',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: AppFont.fontFamily,
                                  color: Color(0xFF3E2723),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Middle Row: 3D Medallion + Title/Subtitle
                    Row(
                      children: [
                        _MissionMedallion(
                          isCompleted: isReadyToClaim,
                          iconEmoji: iconEmoji,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: AppFont.fontFamily,
                                  color: Colors.white,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                isReadyToClaim
                                    ? (isHindi
                                        ? 'बधाई हो! तुरंत अपने सिक्के क्लेम करें'
                                        : 'Great job! Tap Claim to add to wallet')
                                    : (isHindi
                                        ? '$remaining और डिलीवरी पूरी करें और $reward सिक्के पाएं'
                                        : '$remaining more order${remaining == 1 ? '' : 's'} to unlock $reward bonus coins'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: AppFont.fontFamily,
                                  color: isReadyToClaim
                                      ? const Color(0xFF6EE7B7)
                                      : Colors.white.withOpacity(0.75),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // If Ready to claim, show Claim button right here
                        if (isReadyToClaim) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _claiming ? null : _handleDirectClaim,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFF6EE7B7), width: 1.2),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withOpacity(0.45),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: _claiming
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.stars_rounded, color: Colors.white, size: 14),
                                        const SizedBox(width: 4),
                                        Text(
                                          isHindi ? 'क्लेम करें' : 'CLAIM',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w900,
                                            fontFamily: AppFont.fontFamily,
                                            color: Colors.white,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                        ],
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Milestone Stepped or Continuous Progress Bar
                    _MilestoneProgressBar(
                      total: total,
                      done: done,
                      progress: targetProgress,
                      isCompleted: isReadyToClaim,
                    ),

                    const SizedBox(height: 6),

                    // Bottom Counters Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$done / $total ${total == 1 ? 'order' : 'orders'} completed',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            fontFamily: AppFont.fontFamily,
                            color: isReadyToClaim ? const Color(0xFF34D399) : const Color(0xFFFFC107),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isReadyToClaim
                                  ? (isHindi ? 'वॉलेट में जोड़ें' : 'Ready to collect')
                                  : (isHindi ? 'सभी मिशन देखें' : 'View all missions'),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                fontFamily: AppFont.fontFamily,
                                color: Colors.white.withOpacity(0.55),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.55), size: 14),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 3D GOLDEN COIN / TROPHY MEDALLION ─────────────────────────────────────────
class _MissionMedallion extends StatelessWidget {
  final bool isCompleted;
  final String iconEmoji;

  const _MissionMedallion({
    required this.isCompleted,
    required this.iconEmoji,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: isCompleted
              ? const [Color(0xFF6EE7B7), Color(0xFF10B981), Color(0xFF047857)]
              : const [Color(0xFFFFEE58), Color(0xFFFFB300), Color(0xFFFF8F00)],
          center: const Alignment(-0.25, -0.3),
          radius: 0.85,
        ),
        boxShadow: [
          BoxShadow(
            color: (isCompleted ? const Color(0xFF10B981) : const Color(0xFFFF9800))
                .withOpacity(0.45),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: isCompleted ? const Color(0xFFA7F3D0) : const Color(0xFFFFF176),
          width: 2,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Inner circular engraved groove
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isCompleted
                    ? const Color(0xFF065F46).withOpacity(0.4)
                    : const Color(0xFFE65100).withOpacity(0.35),
                width: 1,
              ),
            ),
          ),
          if (isCompleted)
            const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 24)
          else if (iconEmoji.isNotEmpty && iconEmoji != '🎯')
            Text(iconEmoji, style: const TextStyle(fontSize: 21))
          else
            const Icon(Icons.monetization_on_rounded, color: Color(0xFF5D4037), size: 24),
        ],
      ),
    );
  }
}

// ── STEPPED MILESTONE OR CONTINUOUS PROGRESS CAPSULE ──────────────────────────
class _MilestoneProgressBar extends StatelessWidget {
  final int total;
  final int done;
  final double progress;
  final bool isCompleted;

  const _MilestoneProgressBar({
    required this.total,
    required this.done,
    required this.progress,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final bool usePips = total > 1 && total <= 6;
    final Color trackBg = Colors.white.withOpacity(0.12);

    final List<Color> fillColors = isCompleted
        ? const [Color(0xFF34D399), Color(0xFF10B981)]
        : const [Color(0xFFFFD54F), Color(0xFFFF9800), Color(0xFFFF5722)];

    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = constraints.maxWidth;

        return Stack(
          alignment: Alignment.centerLeft,
          clipBehavior: Clip.none,
          children: [
            // Background track
            Container(
              height: 8,
              width: barWidth,
              decoration: BoxDecoration(
                color: trackBg,
                borderRadius: BorderRadius.circular(6),
              ),
            ),

            // Animated progress fill
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 0.0, end: progress),
              builder: (context, val, _) {
                return Container(
                  height: 8,
                  width: barWidth * val,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: fillColors),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: fillColors.last.withOpacity(0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Stepped pips (if total <= 6)
            if (usePips)
              Positioned.fill(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(total, (index) {
                    final orderNum = index + 1;
                    final bool isStepDone = orderNum <= done;
                    final bool isFinalStep = orderNum == total;

                    return Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isStepDone
                            ? (isCompleted ? const Color(0xFF10B981) : const Color(0xFFFF9800))
                            : const Color(0xFF1E293B),
                        border: Border.all(
                          color: isStepDone
                              ? Colors.white
                              : Colors.white.withOpacity(0.35),
                          width: 1.5,
                        ),
                        boxShadow: isStepDone
                            ? [
                                BoxShadow(
                                  color: (isCompleted
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFFF9800))
                                      .withOpacity(0.5),
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: isStepDone
                            ? const Icon(Icons.check, size: 8.5, color: Colors.white)
                            : (isFinalStep
                                ? const Text('🪙', style: TextStyle(fontSize: 7))
                                : Text(
                                    '$orderNum',
                                    style: TextStyle(
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white.withOpacity(0.6),
                                      fontFamily: AppFont.fontFamily,
                                    ),
                                  )),
                      ),
                    );
                  }),
                ),
              ),
          ],
        );
      },
    );
  }
}

// Animated and eye-catching top banner promoting the coins loyalty program.
// Sits directly under the header, above the scrollable body.
class _CoinsTickerBar extends StatefulWidget {
  final VoidCallback onTap;

  const _CoinsTickerBar({required this.onTap});

  @override
  State<_CoinsTickerBar> createState() => _CoinsTickerBarState();
}

class _CoinsTickerBarState extends State<_CoinsTickerBar> {
  @override
  Widget build(BuildContext context) {
    final isHindi = language == 1;

    final slide = _PromoSlideData(
      titleEn: "Scratch & Win Coins! 🪙",
      titleHi: "हर राइड पर सिक्के जीतें! 🪙",
      subEn: "Get 5 to 10 coins automatically after completing each delivery.",
      subHi: "हर डिलीवरी पूरी होने पर अपने आप 5 से 10 सिक्के पाएं।",
      colors: [const Color(0xFF1E1B18), const Color(0xFFFF9E00)],
      iconWidget: const _Animated3DCoin(),
      actionLabelEn: "Claim Rewards",
      actionLabelHi: "इनाम पाएं",
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 106,
        child: GestureDetector(
                onTap: widget.onTap,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        slide.colors[0],
                        slide.colors[1].withOpacity(0.18),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: slide.colors[1].withOpacity(0.38),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: slide.colors[1].withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Floating background particles
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: _ParticleEffect(color: slide.colors[1]),
                        ),
                      ),
                      // Background glow circle
                      Positioned(
                        right: -10,
                        top: -15,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: slide.colors[1].withOpacity(0.08),
                          ),
                        ),
                      ),
                      // Content Row
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        child: Row(
                          children: [
                            // Animated graphic on the left
                            Center(child: slide.iconWidget),
                            const SizedBox(width: 12),
                            // Text & Info in the middle
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Hot/New Badge
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: slide.colors[1].withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: slide.colors[1].withOpacity(0.55),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          isHindi ? "नया" : "NEW PROMO",
                                          style: TextStyle(
                                            fontFamily: AppFont.fontFamily,
                                            fontSize: 7.5,
                                            fontWeight: FontWeight.w800,
                                            color: slide.colors[1],
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  // Title
                                  Text(
                                    isHindi ? slide.titleHi : slide.titleEn,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: AppFont.fontFamily,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  // Subtitle
                                  Text(
                                    isHindi ? slide.subHi : slide.subEn,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: AppFont.fontFamily,
                                      fontSize: 10.5,
                                      color: Colors.white.withOpacity(0.65),
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Action Button on the right
                            const SizedBox(width: 8),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        slide.colors[1],
                                        slide.colors[1].withAlpha(200),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: slide.colors[1].withOpacity(0.25),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      )
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        isHindi
                                            ? slide.actionLabelHi
                                            : slide.actionLabelEn,
                                        style: const TextStyle(
                                          fontFamily: AppFont.fontFamily,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      const Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        color: Colors.white,
                                        size: 8,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _PromoSlideData {
  final String titleEn;
  final String titleHi;
  final String subEn;
  final String subHi;
  final List<Color> colors;
  final Widget iconWidget;
  final String actionLabelEn;
  final String actionLabelHi;

  _PromoSlideData({
    required this.titleEn,
    required this.titleHi,
    required this.subEn,
    required this.subHi,
    required this.colors,
    required this.iconWidget,
    required this.actionLabelEn,
    required this.actionLabelHi,
  });
}

// Drifting glowing background particles
class _ParticleEffect extends StatefulWidget {
  final Color color;
  const _ParticleEffect({required this.color});

  @override
  State<_ParticleEffect> createState() => _ParticleEffectState();
}

class _ParticleEffectState extends State<_ParticleEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final List<_Particle> _particles = [];
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    for (int i = 0; i < 12; i++) {
      _particles.add(_Particle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        speed: 0.03 + _random.nextDouble() * 0.05,
        size: 1.5 + _random.nextDouble() * 3.5,
        opacity: 0.08 + _random.nextDouble() * 0.35,
      ));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        for (var p in _particles) {
          p.y -= p.speed * 0.01;
          if (p.y < 0) {
            p.y = 1.0;
            p.x = _random.nextDouble();
          }
        }
        return CustomPaint(
          painter: _ParticlePainter(_particles, widget.color),
          child: Container(),
        );
      },
    );
  }
}

class _Particle {
  double x;
  double y;
  double speed;
  double size;
  double opacity;
  _Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.opacity,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final Color color;
  _ParticlePainter(this.particles, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var p in particles) {
      paint.color = color.withOpacity(p.opacity);
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// 3D Spinning Gold Coin Widget
class _Animated3DCoin extends StatefulWidget {
  const _Animated3DCoin();

  @override
  State<_Animated3DCoin> createState() => _Animated3DCoinState();
}

class _Animated3DCoinState extends State<_Animated3DCoin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final spinAngle = _controller.value * 2 * math.pi;
        final bounceOffset = 4.0 * math.sin(_controller.value * 2 * math.pi * 2);
        return Transform.translate(
          offset: Offset(0, bounceOffset),
          child: Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.002) // perspective
              ..rotateY(spinAngle),
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [Color(0xFFFFEA00), Color(0xFFFF9100)],
            center: Alignment(-0.3, -0.3),
            radius: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF9100).withOpacity(0.4),
              blurRadius: 8,
              spreadRadius: 1,
            )
          ],
          border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
        ),
        child: const Center(
          child: Text(
            '🪙',
            style: TextStyle(fontSize: 22),
          ),
        ),
      ),
    );
  }
}

// Thin horizontal dashed line used to separate list rows (e.g. recent
// locations) without pulling in a dedicated package for it.
// A rounded border whose colors continuously sweep around the edge, then
// reverse direction every few seconds instead of snapping back — driven by
// a single ping-ponging AnimationController so it's cheap to keep running.
class _AnimatedGradientBorder extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final double strokeWidth;

  const _AnimatedGradientBorder({
    required this.child,
    required this.borderRadius,
    this.strokeWidth = 2.2,
  });

  @override
  State<_AnimatedGradientBorder> createState() =>
      _AnimatedGradientBorderState();
}

class _AnimatedGradientBorderState extends State<_AnimatedGradientBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _colors = [
    AppColor.themeColor,
    Colors.orangeAccent,
    Colors.blueAccent,
  ];

  @override
  void initState() {
    super.initState();
    // One full sweep every 6.5s, then reverses — repeat(reverse: true)
    // ping-pongs 0→1→0 forever, which is exactly "run one way, then flip".
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => CustomPaint(
        foregroundPainter: _GradientBorderPainter(
          progress: _controller.value,
          radius: widget.borderRadius,
          strokeWidth: widget.strokeWidth,
          colors: _colors,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _GradientBorderPainter extends CustomPainter {
  final double progress;
  final BorderRadius radius;
  final double strokeWidth;
  final List<Color> colors;

  _GradientBorderPainter({
    required this.progress,
    required this.radius,
    required this.strokeWidth,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect).deflate(strokeWidth / 2);

    final gradient = SweepGradient(
      colors: [...colors, colors.first],
      stops: List.generate(colors.length + 1, (i) => i / colors.length),
      transform: GradientRotation(progress * 2 * math.pi),
    );

    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _GradientBorderPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// Cycles through a few short prompts in the search bar instead of a static
// "Where to?" — owns its own timer so it repaints in isolation rather than
// rebuilding the whole home screen every few seconds.
class _RotatingSearchHint extends StatefulWidget {
  const _RotatingSearchHint();

  static const _hints = [
    "Send a parcel now",
    "Book a delivery in seconds",
    "Get instant fare estimates",
  ];

  @override
  State<_RotatingSearchHint> createState() => _RotatingSearchHintState();
}

class _RotatingSearchHintState extends State<_RotatingSearchHint> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() =>
          _index = (_index + 1) % _RotatingSearchHint._hints.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.4),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: Text(
          _RotatingSearchHint._hints[_index],
          key: ValueKey(_index),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColor.hintTextColor,
            fontFamily: AppFont.fontFamily,
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    const dashWidth = 4.0;
    const dashSpace = 4.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final dashCount =
            (constraints.maxWidth / (dashWidth + dashSpace)).floor();
        return SizedBox(
          height: 1,
          child: Row(
            children: List.generate(
              dashCount,
              (_) => Padding(
                padding: const EdgeInsets.only(right: dashSpace),
                child: Container(
                  width: dashWidth,
                  height: 1,
                  color: AppColor.borderColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VehicleOption {
  final IconData icon;
  final String label;
  final String key;
  final String imagePath;
  const _VehicleOption(this.icon, this.label, this.key, this.imagePath);
}

// Rectangular banner shown on the retailer home screen while a booking is
// Pending/Accepted/Arrived/Pickup/Ongoing — tapping jumps straight into live
// driver tracking instead of the multi-tab booking list.
class _ActiveBookingTracker extends StatelessWidget {
  final Map<String, dynamic> booking;
  final String userId;
  const _ActiveBookingTracker({required this.booking, required this.userId});

  static const Map<String, String> _statusLabel = {
    'pending': 'Finding a driver…',
    'accepted': 'Driver is on the way to pickup',
    'arrived': 'Driver has arrived at pickup',
    'pickup': 'Order picked up',
    'ongoing': 'Order is on the way',
  };

  double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  @override
  Widget build(BuildContext context) {
    final String bookingId = booking['_id']?.toString() ?? '';
    final String bookingCode = booking['booking_code']?.toString() ?? '';
    final String status = (booking['booking_status'] ?? '').toString();
    final String statusKey = status.toLowerCase();

    final driver = booking['driver_id'] is Map
        ? Map<String, dynamic>.from(booking['driver_id'] as Map)
        : null;
    final vehicle = booking['vehicleType_id'] is Map
        ? Map<String, dynamic>.from(booking['vehicleType_id'] as Map)
        : null;
    final pickup = booking['pickup_location'] is Map
        ? Map<String, dynamic>.from(booking['pickup_location'] as Map)
        : null;
    final drop = booking['dropoff_location'] is Map
        ? Map<String, dynamic>.from(booking['dropoff_location'] as Map)
        : null;

    final String subtitle = _statusLabel[statusKey] ??
        (driver != null ? 'Driver assigned' : 'Looking for a driver');

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RTrackDriverScreen(
              userId: userId,
              bookingId: bookingId,
              driverId: driver?['_id']?.toString(),
              vehicleName: vehicle?['name']?.toString(),
              vehicleImage: vehicle?['image']?.toString(),
              pickupLat: _num(pickup?['latitude']),
              pickupLng: _num(pickup?['longitude']),
              dropLat: _num(drop?['latitude']),
              dropLng: _num(drop?['longitude']),
              bookingStatus: status,
            ),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColor.themeColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColor.themeColor.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.local_shipping_rounded,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bookingCode.isNotEmpty
                        ? 'Track booking #$bookingCode'
                        : 'Track your ongoing booking',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: AppFont.fontFamily,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontFamily: AppFont.fontFamily,
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String imagePath;
  final IconData fallbackIcon;
  final String label;
  final VoidCallback? onTap;
  const _QuickChip({required this.imagePath, required this.fallbackIcon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isTataAce = label.toLowerCase().contains('tata') || label.toLowerCase().contains('ace');

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xffE2E8F0),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.025),
              blurRadius: 8,
              offset: const Offset(0, 3),
            )
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      child: Image.asset(
                        imagePath,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            fallbackIcon,
                            color: AppColor.themeColor,
                            size: 26,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColor.fontColor,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isTataAce)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColor.successCOlor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'HOT',
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 7,
                      fontWeight: FontWeight.w900,
                      color: AppColor.successCOlor,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Bottom sheet: ask user whether shared location is Pickup or Drop â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _LocationRoleSheet extends StatelessWidget {
  final String address;
  const _LocationRoleSheet({required this.address});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 20),

          // Icon
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColor.themeColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.location_on_rounded,
                color: AppColor.themeColor, size: 28),
          ),
          const SizedBox(height: 14),

          // Title
          const Text(
            'Use this location as?',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              fontFamily: AppFont.fontFamily,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),

          // Address preview
          Text(
            address,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontFamily: AppFont.fontFamily,
            ),
          ),
          const SizedBox(height: 24),

          // Buttons
          Row(
            children: [
              Expanded(
                child: _RoleButton(
                  label: 'Pickup',
                  icon: Icons.trip_origin_rounded,
                  color: Colors.green.shade600,
                  bgColor: Colors.green.shade50,
                  onTap: () => Navigator.pop(context, 'pickup'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RoleButton(
                  label: 'Drop',
                  icon: Icons.location_on_rounded,
                  color: AppColor.themeColor,
                  bgColor: AppColor.themeColor.withOpacity(0.08),
                  onTap: () => Navigator.pop(context, 'drop'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _RoleButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFamily: AppFont.fontFamily,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Multidrop Banner â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _MultidropBanner extends StatefulWidget {
  const _MultidropBanner();

  @override
  State<_MultidropBanner> createState() => _MultidropBannerState();
}

class _MultidropBannerState extends State<_MultidropBanner>
    with SingleTickerProviderStateMixin {
  static const _vehicles = [
    _VehicleSlide(image: AppImage.mini3w,       label: 'Mini 3-Wheeler', color: Color(0xFFFF9A3C)),
    _VehicleSlide(image: AppImage.twowheel,     label: '2-Wheeler',      color: Color(0xFF6C63FF)),
    _VehicleSlide(image: AppImage.threewheeler, label: '3-Wheeler',      color: Color(0xFF00BFA5)),
    _VehicleSlide(image: AppImage.minitruck,    label: 'Mini Truck',     color: Color(0xFFFF6B6B)),
    _VehicleSlide(image: AppImage.eloader,      label: 'E-Loader',       color: Color(0xFF43E97B)),
  ];

  int _current = 0;
  late final AnimationController _ctrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim  = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _scaleAnim = Tween<double>(begin: 0.72, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    _startCycle();
  }

  void _startCycle() {
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _ctrl.reverse().then((_) {
        if (!mounted) return;
        setState(() => _current = (_current + 1) % _vehicles.length);
        _ctrl.forward();
        _startCycle();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = _vehicles[_current];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1A1A2E),
              slide.color.withOpacity(0.18),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          border: Border.all(color: slide.color.withOpacity(0.35), width: 1.5),
          boxShadow: [
            BoxShadow(color: slide.color.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 6)),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Background glow circle
            Positioned(
              right: -10, top: -18,
              child: Container(
                width: 110, height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: slide.color.withOpacity(0.12),
                ),
              ),
            ),
            // Dot indicators
            Positioned(
              bottom: 10, right: 14,
              child: Row(
                children: List.generate(_vehicles.length, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(left: 4),
                  width: i == _current ? 16 : 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: i == _current ? slide.color : slide.color.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                )),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 28),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left â€” text content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: slide.color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: slide.color.withOpacity(0.45), width: 1),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.route_rounded, color: slide.color, size: 10),
                            const SizedBox(width: 4),
                            Text('MULTI-DROP', style: TextStyle(
                              fontFamily: AppFont.fontFamily, fontSize: 9,
                              fontWeight: FontWeight.w800, color: slide.color, letterSpacing: 1,
                            )),
                          ]),
                        ),
                        const SizedBox(height: 8),
                        const Text('One Pickup.\nMultiple Drops.',
                          style: TextStyle(
                            fontFamily: AppFont.fontFamily, fontSize: 17,
                            fontWeight: FontWeight.w900, color: Colors.white, height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('Deliver to 2+ locations in a\nsingle trip. Pay per drop.',
                          style: TextStyle(
                            fontFamily: AppFont.fontFamily, fontSize: 11,
                            color: Colors.white.withOpacity(0.55), height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Feature pills
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          _pill(Icons.location_on_rounded,     'Multi-stop',    slide.color),
                          _pill(Icons.calculate_outlined,      'Auto pricing',  slide.color),
                          _pill(Icons.speed_rounded,           'Save time',     slide.color),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Right â€” vehicle sticker
                  SizedBox(
                    width: 110, height: 110,
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: ScaleTransition(
                        scale: _scaleAnim,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Transform.rotate(
                              angle: -0.07,
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.18),
                                      blurRadius: 10, offset: const Offset(2, 4),
                                    ),
                                    BoxShadow(
                                      color: slide.color.withOpacity(0.22),
                                      blurRadius: 16, spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Image.asset(
                                  slide.image, width: 72, height: 54,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(slide.label,
                              style: TextStyle(
                                fontFamily: AppFont.fontFamily, fontSize: 10,
                                fontWeight: FontWeight.w700, color: slide.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.06),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withOpacity(0.1)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 9, color: color.withOpacity(0.8)),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(
        fontFamily: AppFont.fontFamily, fontSize: 9.5,
        fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.65),
      )),
    ]),
  );
}

class _VehicleSlide {
  final String image;
  final String label;
  final Color color;
  const _VehicleSlide({required this.image, required this.label, required this.color});
}

// ── Bike Delivery Animation ──────────────────────────────────────────────────

class _BikeDeliveryAnimation extends StatefulWidget {
  const _BikeDeliveryAnimation();

  @override
  State<_BikeDeliveryAnimation> createState() => _BikeDeliveryAnimationState();
}

class _BikeDeliveryAnimationState extends State<_BikeDeliveryAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _loop();
  }

  Future<void> _loop() async {
    try {
      while (mounted) {
        _ctrl.reset();
        await _ctrl.forward();
        if (!mounted) break;
        await Future.delayed(const Duration(milliseconds: 1400));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static Offset _bezier(
      double t, Offset p0, Offset p1, Offset p2, Offset p3) {
    final mt = 1 - t;
    return Offset(
      mt * mt * mt * p0.dx + 3 * mt * mt * t * p1.dx +
          3 * mt * t * t * p2.dx + t * t * t * p3.dx,
      mt * mt * mt * p0.dy + 3 * mt * mt * t * p1.dy +
          3 * mt * t * t * p2.dy + t * t * t * p3.dy,
    );
  }

  static double _bezierAngle(
      double t, Offset p0, Offset p1, Offset p2, Offset p3) {
    final mt = 1 - t;
    final dx = 3 * mt * mt * (p1.dx - p0.dx) +
        6 * mt * t * (p2.dx - p1.dx) +
        3 * t * t * (p3.dx - p2.dx);
    final dy = 3 * mt * mt * (p1.dy - p0.dy) +
        6 * mt * t * (p2.dy - p1.dy) +
        3 * t * t * (p3.dy - p2.dy);
    return math.atan2(dy, dx);
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    const height = 155.0;
    const hPad = 16.0;
    final w = screenW - hPad * 2;

    final p0 = Offset(w * 0.05, height * 0.70);
    final p1 = Offset(w * 0.30, height * 0.15);
    final p2 = Offset(w * 0.68, height * 0.78);
    final p3 = Offset(w * 0.95, height * 0.22);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: hPad),
      child: SizedBox(
        height: height,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_ctrl.value);
              final pos = _bezier(t, p0, p1, p2, p3);
              final angle = _bezierAngle(t, p0, p1, p2, p3);
              final pickupFade = ((t - 0.15) / 0.10).clamp(0.0, 1.0);
              final deliveryFade = ((t - 0.85) / 0.08).clamp(0.0, 1.0);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  CustomPaint(
                    size: Size(w, height),
                    painter: _RoutePainter(
                        p0: p0, p1: p1, p2: p2, p3: p3, progress: t),
                  ),
                  Positioned(
                    left: p0.dx - 10,
                    top: p0.dy - 26,
                    child: const _RoutePin(
                        color: Color(0xff091932), label: 'P'),
                  ),
                  Positioned(
                    left: p3.dx - 10,
                    top: p3.dy - 26,
                    child: const _RoutePin(
                        color: Color(0xffE53935), label: 'D'),
                  ),
                  Positioned(
                    left: pos.dx - 22,
                    top: pos.dy - 22,
                    child: Transform.rotate(
                      angle: angle,
                      child: const _BikeMarker(),
                    ),
                  ),
                  Positioned(
                    left: (p0.dx - 44).clamp(0.0, double.infinity),
                    top: p0.dy - 58,
                    child: Opacity(
                      opacity: pickupFade,
                      child: const _DoneBadge(label: 'Pickup Done'),
                    ),
                  ),
                  Positioned(
                    left: (p3.dx - 52).clamp(0.0, double.infinity),
                    top: p3.dy - 58,
                    child: Opacity(
                      opacity: deliveryFade,
                      child: const _DoneBadge(label: 'Delivered !'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final Offset p0, p1, p2, p3;
  final double progress;

  const _RoutePainter(
      {required this.p0,
      required this.p1,
      required this.p2,
      required this.p3,
      required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final trackPath = Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);

    // Dashed background track
    final dashPaint = Paint()
      ..color = const Color(0xffCBD5E1)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const dashW = 10.0, gapW = 6.0;
    for (final metric in trackPath.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        canvas.drawPath(
            metric.extractPath(dist, (dist + dashW).clamp(0, metric.length)),
            dashPaint);
        dist += dashW + gapW;
      }
    }

    // Filled progress strip
    if (progress > 0.01) {
      final metrics = trackPath.computeMetrics().toList();
      if (metrics.isNotEmpty) {
        canvas.drawPath(
          metrics.first.extractPath(0, metrics.first.length * progress),
          Paint()
            ..color = const Color(0xff091932)
            ..strokeWidth = 3.5
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.progress != progress;
}

class _RoutePin extends StatelessWidget {
  final Color color;
  final String label;
  const _RoutePin({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.35),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
            color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _DoneBadge extends StatelessWidget {
  final String label;
  const _DoneBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xff22C55E),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: const Color(0xff22C55E).withOpacity(0.30),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ── Bike marker (Rapido / Zepto style) ───────────────────────────────────────

class _BikeMarker extends StatelessWidget {
  const _BikeMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xff091932),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xff091932).withOpacity(0.35),
            blurRadius: 10,
            spreadRadius: 1,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Icon(
        Icons.delivery_dining,
        color: Colors.white,
        size: 26,
      ),
    );
  }
}

// (old _BikePainter removed — see _BikeMarker)

// ── Save Address Sheet ─────────────────────────────────────────────────────────
class _SaveAddressSheet extends StatefulWidget {
  final LatLng? currentLatLng;
  // When set, the sheet opens in edit mode for this existing saved address
  // (must contain at least '_id', 'label', 'address', 'lat', 'lng').
  final Map<String, dynamic>? existing;
  const _SaveAddressSheet({this.currentLatLng, this.existing});

  @override
  State<_SaveAddressSheet> createState() => _SaveAddressSheetState();
}

class _SaveAddressSheetState extends State<_SaveAddressSheet> {
  // Label
  String? _label;
  final _customLabelCtrl = TextEditingController();

  // Location
  final _addrCtrl  = FocusNode();
  final _addrText  = TextEditingController();
  LatLng? _pickedLatLng;
  String  _pickedAddress = '';
  List<Map<String, dynamic>> _suggestions = [];
  Timer?  _debounce;
  bool    _isLoadingSugg = false;
  // Bundles an Autocomplete typing sequence + its terminating Details call
  // into one billed Places session instead of billing every request alone.
  String? _sessionToken;

  // Contact
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();

  static const _labels = ['Home', 'Work', 'Office', 'Other'];
  static const _labelIcons = <String, IconData>{
    'Home':   Icons.home_outlined,
    'Work':   Icons.work_outline_rounded,
    'Office': Icons.corporate_fare_rounded,
    'Other':  Icons.place_outlined,
  };

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) return;

    final existingLabel = existing['label']?.toString() ?? '';
    if (_labels.contains(existingLabel)) {
      _label = existingLabel;
    } else {
      _label = 'Other';
      _customLabelCtrl.text = existingLabel;
    }

    final addr = existing['address']?.toString() ?? '';
    _addrText.text  = addr;
    _pickedAddress  = addr;
    final lat = existing['lat'];
    final lng = existing['lng'];
    if (lat is num && lng is num) {
      _pickedLatLng = LatLng(lat.toDouble(), lng.toDouble());
    }

    _nameCtrl.text  = existing['contact_name']?.toString()  ?? '';
    _phoneCtrl.text = existing['contact_phone']?.toString() ?? '';
  }

  @override
  void dispose() {
    _customLabelCtrl.dispose();
    _addrText.dispose();
    _addrCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Places autocomplete ────────────────────────────────────────────────────
  void _onAddrChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      _sessionToken = null;
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _fetchSugg(q.trim()));
  }

  Future<void> _fetchSugg(String input) async {
    setState(() => _isLoadingSugg = true);
    _sessionToken ??= PlacesSessionToken.generate();
    try {
      final lat = widget.currentLatLng?.latitude  ?? 22.7196;
      final lng = widget.currentLatLng?.longitude ?? 75.8577;
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(input)}'
        '&location=$lat,$lng'
        '&radius=50000'
        '&components=country:in'
        '&region=in'
        '&sessiontoken=$_sessionToken'
        '&key=${AppConstant.googleApiKey}',
      );
      final res  = await http.get(url);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final preds = data['predictions'] as List? ?? [];
      setState(() {
        _suggestions = preds.map<Map<String, dynamic>>((p) => {
          'place_id':      p['place_id'],
          'description':   p['description'],
          'main_text':     (p['structured_formatting']?['main_text']) ?? '',
          'secondary_text':(p['structured_formatting']?['secondary_text']) ?? '',
        }).toList();
      });
    } catch (_) {
      if (mounted) setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _isLoadingSugg = false);
    }
  }

  Future<void> _pickSuggestion(Map<String, dynamic> s) async {
    _addrCtrl.unfocus();
    setState(() { _suggestions = []; _isLoadingSugg = true; });
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=${s['place_id']}'
        '&fields=geometry,formatted_address,name'
        '&sessiontoken=$_sessionToken'
        '&key=${AppConstant.googleApiKey}',
      );
      // Details call ends the session — next search starts a fresh one.
      _sessionToken = null;
      final res  = await http.get(url);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final loc  = data['result']?['geometry']?['location'];
      if (loc != null && mounted) {
        final addr = data['result']['formatted_address'] ?? s['description'];
        _addrText.text = addr;
        setState(() {
          _pickedLatLng  = LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
          _pickedAddress = addr;
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _isLoadingSugg = false);
    }
  }

  // ── Map picker ─────────────────────────────────────────────────────────────
  Future<void> _openMap() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLocation: widget.currentLatLng ?? const LatLng(22.7196, 75.8577),
          isDropLocation: true,
        ),
      ),
    );
    if (result != null && mounted) {
      // MapPickerScreen returns {"location": LatLng, "address": String}
      final LatLng location = result['location'] as LatLng;
      final String addr     = result['address']?.toString() ?? '';
      _addrText.text = addr;
      setState(() {
        _pickedLatLng  = location;
        _pickedAddress = addr;
        _suggestions   = [];
      });
    }
  }

  // ── Save ───────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    final effectiveLabel = _label == 'Other'
        ? _customLabelCtrl.text.trim().isEmpty ? 'Other' : _customLabelCtrl.text.trim()
        : _label!;
    if (_pickedLatLng == null || _pickedAddress.isEmpty) {
      SnackBarToastMessage.showSnackBar(context, 'Please select a location first');
      return;
    }
    final body = {
      'label':         effectiveLabel,
      'address':       _pickedAddress,
      'lat':           _pickedLatLng!.latitude,
      'lng':           _pickedLatLng!.longitude,
      'contact_name':  _nameCtrl.text.trim(),
      'contact_phone': _phoneCtrl.text.trim(),
    };
    try {
      final res = _isEditing
          ? await putJsonData(
              'user/saved_address/${widget.existing!['_id']}',
              body,
              context,
              headers: {'Authorization': 'Bearer ${AppConstant.token}'},
            )
          : await postJsonData(
              'user/save_address',
              body,
              context,
              headers: {'Authorization': 'Bearer ${AppConstant.token}'},
            );
      if (!mounted) return;
      if (res != null && res['success'] == true) {
        Navigator.pop(context);
        SnackBarToastMessage.showSnackBar(
            context, _isEditing ? 'Address updated' : 'Address saved as "$effectiveLabel"');
      } else {
        SnackBarToastMessage.showSnackBar(context, 'Could not save address. Try again.');
      }
    } catch (_) {
      if (mounted) SnackBarToastMessage.showSnackBar(context, 'Could not save address. Try again.');
    }
  }

  Future<void> _pickContact() async {
    try {
      final ok = await ContactsPermissionHelper.ensureContactsPermission(context);
      if (!ok) {
        if (mounted) SnackBarToastMessage.showSnackBar(context, 'Contacts permission denied. Enable in settings.');
        return;
      }
      final contact = await FlutterContacts.openExternalPick();
      if (contact == null) return;
      final full = await FlutterContacts.getContact(contact.id, withProperties: true);
      if (full == null || !mounted) return;
      String phone = '';
      if (full.phones.isNotEmpty) {
        phone = full.phones.first.number.replaceAll(RegExp(r'\D'), '');
        if (phone.length > 10) {
          if (phone.startsWith('91'))     phone = phone.substring(2);
          else if (phone.startsWith('0')) phone = phone.substring(1);
        }
        if (phone.length > 10) phone = phone.substring(phone.length - 10);
      }
      setState(() {
        _nameCtrl.text  = full.displayName;
        _phoneCtrl.text = phone;
      });
    } catch (e) {
      if (mounted) SnackBarToastMessage.showSnackBar(context, 'Could not pick contact.');
    }
  }

  bool get _canSave => _label != null && _pickedLatLng != null;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 28),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              _isEditing ? 'Edit Address' : 'Save Address',
              style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 17, color: AppColor.blackColor),
            ),
            const SizedBox(height: 4),
            const Text(
              'Quick-book your frequent locations with one tap',
              style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, color: AppColor.hintTextColor),
            ),
            const SizedBox(height: 20),

            // ── Label selector ──────────────────────────────────────────────
            const Text('Location Type', style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 12, color: AppColor.fontColor)),
            const SizedBox(height: 8),
            Row(
              children: _labels.map((lbl) {
                final selected = _label == lbl;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: GestureDetector(
                      onTap: () => setState(() { _label = lbl; }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: selected ? AppColor.themeColor : AppColor.themeColor.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: selected ? AppColor.themeColor : AppColor.themeColor.withOpacity(0.25)),
                        ),
                        child: Column(
                          children: [
                            Icon(_labelIcons[lbl]!, color: selected ? Colors.white : AppColor.themeColor, size: 20),
                            const SizedBox(height: 4),
                            Text(lbl, style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColor.themeColor)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            // Custom label field when Other is selected
            if (_label == 'Other') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customLabelCtrl,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13),
                decoration: _fieldDecor('e.g. Mom\'s place, Gym, Hospital', Icons.label_outline_rounded),
                onChanged: (_) => setState(() {}),
              ),
            ],

            const SizedBox(height: 20),

            // ── Location search ─────────────────────────────────────────────
            const Text('Location', style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 12, color: AppColor.fontColor)),
            const SizedBox(height: 8),
            TextField(
              controller: _addrText,
              focusNode: _addrCtrl,
              style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13),
              decoration: _fieldDecor('Search area, street or landmark', Icons.search_rounded),
              onChanged: _onAddrChanged,
            ),

            // Suggestions list
            if (_isLoadingSugg)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColor.themeColor))),
              )
            else if (_suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xffE2E8F0)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _suggestions.length > 5 ? 5 : _suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 44),
                  itemBuilder: (_, i) {
                    final s = _suggestions[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined, color: AppColor.themeColor, size: 18),
                      title: Text(s['main_text'] ?? s['description'], style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, fontWeight: FontWeight.w600, color: AppColor.blackColor)),
                      subtitle: s['secondary_text']?.toString().isNotEmpty == true
                          ? Text(s['secondary_text'], style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11, color: AppColor.hintTextColor))
                          : null,
                      onTap: () => _pickSuggestion(s),
                    );
                  },
                ),
              ),

            const SizedBox(height: 10),

            // Select on Map button
            GestureDetector(
              onTap: _openMap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xffF6F7FB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xffE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.map_outlined, color: AppColor.themeColor, size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Select on Map', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, fontWeight: FontWeight.w600, color: AppColor.themeColor)),
                    ),
                    if (_pickedLatLng != null)
                      const Icon(Icons.check_circle_rounded, color: AppColor.successCOlor, size: 16),
                  ],
                ),
              ),
            ),

            // Confirmed address chip
            if (_pickedAddress.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColor.successCOlor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColor.successCOlor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded, color: AppColor.successCOlor, size: 15),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _pickedAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, color: AppColor.fontColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── Contact ─────────────────────────────────────────────────────
            const Text('Contact (Optional)', style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 12, color: AppColor.fontColor)),
            const SizedBox(height: 8),

            // Pick from Contacts pill button
            GestureDetector(
              onTap: _pickContact,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColor.themeColor.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColor.themeColor.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.contacts_rounded, size: 16, color: AppColor.themeColor),
                    SizedBox(width: 7),
                    Text(
                      'Pick from Contacts',
                      style: TextStyle(
                        fontFamily: AppFont.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColor.themeColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13),
              decoration: _fieldDecor('Contact name', Icons.person_outline_rounded),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [PhoneNumberFormatter()],
              style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, letterSpacing: 1.5),
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              decoration: _fieldDecor('10-digit mobile number', Icons.phone_iphone_rounded),
            ),

            const SizedBox(height: 24),

            // ── Save button ─────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _canSave ? _save : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColor.themeColor,
                  disabledBackgroundColor: Colors.grey.shade200,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(
                  _canSave
                      ? (_isEditing ? 'Update Address' : 'Save Address')
                      : 'Select a label and location first',
                  style: TextStyle(
                    fontFamily: AppFont.fontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: _canSave ? Colors.white : Colors.grey.shade400,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecor(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, color: AppColor.hintTextColor),
    prefixIcon: Icon(icon, color: AppColor.hintTextColor, size: 18),
    filled: true,
    fillColor: const Color(0xffF6F7FB),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColor.themeColor, width: 1.5)),
  );
}

class _DynamicHomeCard extends StatefulWidget {
  final String category;
  final String title;
  final List<String> images;
  final VoidCallback onTap;

  const _DynamicHomeCard({
    super.key,
    required this.category,
    required this.title,
    required this.images,
    required this.onTap,
  });

  @override
  State<_DynamicHomeCard> createState() => _DynamicHomeCardState();
}

class _DynamicHomeCardState extends State<_DynamicHomeCard> {
  late Timer _timer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted && widget.images.length > 1) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % widget.images.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xffE3E3E3).withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Positioned(
                  left: 14,
                  top: 14,
                  bottom: 14,
                  right: 76,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.category,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          fontFamily: AppFont.fontFamily,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF091932),
                          fontFamily: AppFont.fontFamily,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  top: 12,
                  width: 72,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 700),
                      transitionBuilder: (child, animation) {
                        // Incoming widget: slide in from right to center
                        final inAnimation = Tween<Offset>(
                          begin: const Offset(1.5, 0.0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeInOut,
                        ));

                        // Outgoing widget: slide out from center to left
                        final outAnimation = Tween<Offset>(
                          begin: const Offset(-1.5, 0.0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeInOut,
                        ));

                        if (child.key == ValueKey(_currentIndex)) {
                          return SlideTransition(
                            position: inAnimation,
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          );
                        } else {
                          return SlideTransition(
                            position: outAnimation,
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          );
                        }
                      },
                      child: widget.images.isEmpty
                          ? const SizedBox.shrink()
                          : Image.asset(
                              widget.images[_currentIndex],
                              key: ValueKey(_currentIndex),
                              fit: BoxFit.contain,
                              alignment: Alignment.bottomRight,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MovigoStaticBanner extends StatelessWidget {
  const _MovigoStaticBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 135,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffE3E3E3).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Left content: Logo and tagline
            Positioned(
              left: 20,
              top: 14,
              bottom: 14,
              right: 155, // Leave space for boxes on the right
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    AppImage.applogo,
                    height: 36,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Apna Saaman,\nApni Company.",
                    style: TextStyle(
                      color: Color(0xFF091932),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                      fontFamily: AppFont.fontFamily,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Fast • Reliable • Indori Delivery",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                      fontFamily: AppFont.fontFamily,
                    ),
                  ),
                ],
              ),
            ),

            // Right content: Packaging boxes + gift box matching first mockup screen
            Positioned(
              right: 8,
              top: 8,
              bottom: 8,
              width: 140,
              child: Image.asset(
                AppImage.threeDBoxes,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Noticeboard Banner ──────────────────────────────────────────────────────
// Auto-scrolling carousel of active announcements/social links/festival
// greetings, sourced from the backend (see Notice model / /notices API) —
// admin can post new slides here without an app update. Renders nothing
// while loading or when there are no active notices.
class _NoticeboardBanner extends StatefulWidget {
  const _NoticeboardBanner({super.key});

  @override
  State<_NoticeboardBanner> createState() => _NoticeboardBannerState();
}

class _NoticeboardBannerState extends State<_NoticeboardBanner> {
  final PageController _pageController = PageController();
  Timer? _timer;
  int _currentPage = 0;
  List<NoticeModel> _notices = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNotices());
  }

  Future<void> _loadNotices() async {
    if (!mounted) return;
    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final res = await provider.getNoticesApi(context);
    final list = (res?['data'] as List?) ?? [];
    if (!mounted) return;
    setState(() {
      _notices = list
          .whereType<Map>()
          .map((e) => NoticeModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _loaded = true;
    });
    if (_notices.length > 1) _startAutoScroll();
  }

  void _startAutoScroll() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageController.hasClients || _notices.isEmpty) return;
      _currentPage = (_currentPage + 1) % _notices.length;
      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Color _accentColor(NoticeModel n) {
    if (n.themeColor.isNotEmpty) {
      try {
        final hex = n.themeColor.replaceAll('#', '');
        return Color(int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16));
      } catch (_) {}
    }
    return AppColor.themeColor;
  }

  String _defaultEmoji(String type) {
    switch (type) {
      case 'update':
        return '🆕';
      case 'festival':
        return '🎉';
      case 'maintenance':
        return '🛠️';
      default:
        return '📣';
    }
  }

  Future<void> _onTapNotice(NoticeModel n) async {
    if (n.linkUrl.isNotEmpty) {
      final uri = Uri.tryParse(n.linkUrl);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NoticeboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _notices.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          SizedBox(
            height: 78,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _notices.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (context, index) {
                final n = _notices[index];
                final accent = _accentColor(n);
                final emoji = n.icon.isNotEmpty ? n.icon : _defaultEmoji(n.noticeType);
                return GestureDetector(
                  onTap: () => _onTapNotice(n),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accent.withOpacity(0.25)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: accent.withOpacity(0.12),
                          child: Text(emoji, style: const TextStyle(fontSize: 17)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                n.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: AppFont.fontFamily,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: AppColor.fontColor,
                                ),
                              ),
                              if (n.body.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  n.body,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: AppFont.fontFamily,
                                    fontSize: 11.5,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: accent, size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_notices.length > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_notices.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColor.themeColor
                        : AppColor.themeColor.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Promo Banner Carousel ──────────────────────────────────────────────────
// Auto-scrolling carousel of admin-managed promo banners, sourced from the
// backend (GET /promo-banners?audience=retailer). Admin can add/edit/retire
// slides from the admin panel with no app update. Renders nothing while
// loading or when there are no active banners.
class _PromoBannerCarousel extends StatefulWidget {
  const _PromoBannerCarousel({super.key});

  @override
  State<_PromoBannerCarousel> createState() => _PromoBannerCarouselState();
}

class _PromoBannerCarouselState extends State<_PromoBannerCarousel> {
  final PageController _pageController = PageController(viewportFraction: 0.92);
  Timer? _timer;
  int _currentPage = 0;
  List<Map<String, dynamic>> _banners = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final res = await provider.getPromoBannersApi(context);
    final list = (res?['data'] as List?) ?? [];
    if (!mounted) return;
    setState(() {
      _banners = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((b) => (b['image'] ?? '').toString().isNotEmpty)
          .toList();
      _loaded = true;
    });
    if (_banners.length > 1) _startAutoScroll();
  }

  void _startAutoScroll() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageController.hasClients || _banners.isEmpty) return;
      _currentPage = (_currentPage + 1) % _banners.length;
      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  IconData _badgeIcon(String? key) {
    switch (key) {
      case 'groups':
        return Icons.groups_rounded;
      case 'play_circle':
        return Icons.play_circle_fill_rounded;
      case 'card_giftcard':
        return Icons.card_giftcard;
      case 'trending_up':
        return Icons.trending_up_rounded;
      case 'bolt':
        return Icons.bolt;
      case 'star':
        return Icons.star_rounded;
      case 'celebration':
        return Icons.celebration_rounded;
      case 'local_offer':
      default:
        return Icons.local_offer_rounded;
    }
  }

  // Fixed, explicit set of in-app targets a banner's action_value can name —
  // a typo in the admin panel can never crash navigation; unrecognized
  // values just no-op.
  Future<void> _onTap(Map<String, dynamic> banner) async {
    final actionType = (banner['action_type'] ?? 'url').toString();
    final actionValue = (banner['action_value'] ?? '').toString();

    if (actionType == 'url') {
      final uri = Uri.tryParse(actionValue);
      if (uri != null && actionValue.isNotEmpty && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else if (actionType == 'tab') {
      final tabIndex = int.tryParse(actionValue);
      if (tabIndex != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CustomBottomNav(
              userType: UserType.retailer,
              initialIndex: tabIndex,
            ),
          ),
        );
      }
    } else if (actionType == 'screen') {
      // 'noticeboard' and any unrecognized screen key both land here, so a
      // banner posted without a specific screen still goes somewhere useful.
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NoticeboardScreen()),
        );
      }
    }
    // 'none' — informational banner, intentionally not tappable.
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _banners.isEmpty) return const SizedBox.shrink();
    final isHindi = language == 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          SizedBox(
            height: 150,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _banners.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (context, index) {
                final b = _banners[index];
                final titleEn = (b['title_en'] ?? '').toString();
                final titleHi = (b['title_hi'] ?? '').toString();
                final subEn = (b['subtitle_en'] ?? '').toString();
                final subHi = (b['subtitle_hi'] ?? '').toString();
                final actionText = isHindi
                    ? (b['action_text_hi'] ?? 'और जानें').toString()
                    : (b['action_text_en'] ?? 'Learn More').toString();
                final title = isHindi && titleHi.isNotEmpty ? titleHi : titleEn;
                final subtitle = isHindi && subHi.isNotEmpty ? subHi : subEn;
                final actionType = (b['action_type'] ?? 'url').toString();

                return GestureDetector(
                  onTap: actionType == 'none' ? null : () => _onTap(b),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Image.network(
                              '${AppConfigProvider.imgUrl}${b['image']}',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppColor.themeColor.withOpacity(0.15),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.black.withOpacity(0.82),
                                    Colors.black.withOpacity(0.32),
                                    Colors.black.withOpacity(0.10),
                                  ],
                                  begin: Alignment.bottomLeft,
                                  end: Alignment.topRight,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.22),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _badgeIcon(b['badge_icon']?.toString()),
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          fontFamily: AppFont.fontFamily,
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withOpacity(0.92),
                                      fontWeight: FontWeight.w600,
                                      fontFamily: AppFont.fontFamily,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                                if (actionType != 'none') ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          actionText,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: AppColor.themeColor,
                                            fontFamily: AppFont.fontFamily,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.arrow_forward_rounded,
                                            size: 12, color: AppColor.themeColor),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_banners.length > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_banners.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColor.themeColor
                        : AppColor.themeColor.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}
