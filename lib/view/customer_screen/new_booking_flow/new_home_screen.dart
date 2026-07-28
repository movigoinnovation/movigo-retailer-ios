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
import 'package:movigo/view/retailer_screen/retailer_booking_screen/track_driver_screen.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_config_provider.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/utilities/phone_number_formatter.dart';
import 'package:movigo/view/customer_screen/account_screen/help_and_support_screen.dart';
import 'package:movigo/view/customer_screen/notification_screen/notification_screen.dart';
import 'location_selection_screen.dart';
import 'route_vehicle_screen.dart';
import 'package:movigo/utilities/battery_optimization_helper.dart';
import 'package:movigo/view/customer_screen/coins/coin_wallet_screen.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:movigo/helper/contacts_permission_helper.dart';
import 'package:movigo/helper/map_picker.dart';
import 'multi_drop_location_screen.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getCurrentLocation();
      Provider.of<NotificationUnreadCountController>(context, listen: false)
          .getUnreadNotificationCount(context);
      // R3: once-only battery optimization prompt (never naggy, dismissible)
      BatteryOptimizationHelper.maybePrompt(context);
    });
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
  // deduped, capped to 3 — what actually gets rendered below the search bar.
  List<Map<String, dynamic>> get _displayedLocations {
    final seen = <String>{};
    final combined = <Map<String, dynamic>>[];
    for (final loc in [..._favoriteLocations, ..._recentDrops]) {
      if (seen.add(_locationKey(loc))) combined.add(loc);
    }
    return combined.take(3).toList();
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

  LatLng _getRetailerFallbackLatLng(UserController user) {
    if (user.getlatitude != 0.0 && user.getlongitude != 0.0) {
      return LatLng(user.getlatitude, user.getlongitude);
    }
    if (user.businessLat != 0.0 && user.businessLng != 0.0) {
      return LatLng(user.businessLat, user.businessLng);
    }
    return const LatLng(22.7196, 75.8577); // Indore fallback
  }

  String _getRetailerFallbackAddress(UserController user) {
    if (user.getAddress.isNotEmpty) {
      return user.getAddress;
    }
    return "Indore, Madhya Pradesh";
  }

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

          final result = await Navigator.push<Map<String, dynamic>>(
            context,
            MaterialPageRoute(
              builder: (_) => LocationSelectionScreen(
                initialPickupLatLng: pickupLatLng,
                initialPickupAddress: pickupAddr,
                initialDropLatLng: targetLatLng,
                initialDropAddress: targetAddress,
              ),
            ),
          );

          if (result != null && mounted) {
            final pickup = result['pickup'] as Map<String, dynamic>;
            final drop   = result['drop']   as Map<String, dynamic>;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RouteVehicleScreen(
                  pickupLatLng:      LatLng(pickup['lat'] as double, pickup['lng'] as double),
                  pickupAddress:     pickup['address'] as String,
                  pickupContactName:  (pickup['contact_name']  ?? '').toString(),
                  pickupContactPhone: (pickup['contact_phone'] ?? '').toString(),
                  dropLatLng:        LatLng(drop['lat'] as double, drop['lng'] as double),
                  dropAddress:       drop['address'] as String,
                  dropContactName:   (drop['contact_name']  ?? '').toString(),
                  dropContactPhone:  (drop['contact_phone'] ?? '').toString(),
                ),
              ),
            );
          }
        } else {
          // Shared location â†' Pickup. Open LocationSelectionScreen with pickup
          // pre-filled; the drop field is focused by default so the user can
          // type the drop address immediately.
          final result = await Navigator.push<Map<String, dynamic>>(
            context,
            MaterialPageRoute(
              builder: (_) => LocationSelectionScreen(
                initialPickupLatLng: targetLatLng,
                initialPickupAddress: targetAddress!,
              ),
            ),
          );

          if (result != null && mounted) {
            final pickup = result['pickup'] as Map<String, dynamic>;
            final drop   = result['drop']   as Map<String, dynamic>;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RouteVehicleScreen(
                  pickupLatLng:      LatLng(pickup['lat'] as double, pickup['lng'] as double),
                  pickupAddress:     pickup['address'] as String,
                  pickupContactName:  (pickup['contact_name']  ?? '').toString(),
                  pickupContactPhone: (pickup['contact_phone'] ?? '').toString(),
                  dropLatLng:        LatLng(drop['lat'] as double, drop['lng'] as double),
                  dropAddress:       drop['address'] as String,
                  dropContactName:   (drop['contact_name']  ?? '').toString(),
                  dropContactPhone:  (drop['contact_phone'] ?? '').toString(),
                ),
              ),
            );
          }
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
  // if we have one, otherwise the retailer's saved business address.
  (LatLng?, String) _resolvePickupLatLngAndAddress() {
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
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationSelectionScreen(
          initialPickupLatLng: initialPickupLatLng,
          initialPickupAddress: initialPickupAddress,
          initialDropLatLng: initialDropLatLng,
          initialDropAddress: initialDropAddress,
          initialDropContactName: initialDropContactName,
          initialDropContactPhone: initialDropContactPhone,
        ),
      ),
    );

    if (result != null && mounted) {
      final pickup = result['pickup'] as Map<String, dynamic>;
      final drop   = result['drop']   as Map<String, dynamic>;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RouteVehicleScreen(
            pickupLatLng:           LatLng(pickup['lat'] as double, pickup['lng'] as double),
            pickupAddress:          pickup['address'] as String,
            pickupContactName:       (pickup['contact_name']  ?? '').toString(),
            pickupContactPhone:      (pickup['contact_phone'] ?? '').toString(),
            dropLatLng:             LatLng(drop['lat'] as double, drop['lng'] as double),
            dropAddress:            drop['address'] as String,
            preSelectedVehicleName: vehicleName,
            dropContactName:        (drop['contact_name']  ?? '').toString(),
            dropContactPhone:       (drop['contact_phone'] ?? '').toString(),
          ),
        ),
      );
    }
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

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
        backgroundColor: Colors.white,
        body: Column(
          children: [
            // â”€â”€ Blue header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Container(
              color: AppColor.themeColor,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + size.height * 0.012,
                bottom: size.height * 0.018,
                left: size.width * 0.045,
                right: size.width * 0.03,
              ),
              child: Row(
                children: [
                  // Profile avatar
                  Consumer<UserController>(
                    builder: (_, user, __) {
                      final img = user.getUserImage;
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const CustomBottomNav(
                                    userType: UserType.retailer,
                                    initialIndex: 3,
                                  )),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: img.isNotEmpty
                              ? Image.network(
                                  "${AppConfigProvider.imgUrl}$img",
                                  height: size.height * 0.055,
                                  width: size.height * 0.055,
                                  fit: BoxFit.cover,
                                  cacheWidth: 200,
                                  errorBuilder: (_, __, ___) => Image.asset(
                                        AppImage.userdummyimage,
                                        height: size.height * 0.055,
                                        width: size.height * 0.055,
                                        fit: BoxFit.cover,
                                      ),
                                )
                              : Image.asset(
                                  AppImage.userdummyimage,
                                  height: size.height * 0.055,
                                  width: size.height * 0.055,
                                  fit: BoxFit.cover,
                                ),
                        ),
                      );
                    },
                  ),
                  SizedBox(width: size.width * 0.025),
                  // Greeting + current city
                  Expanded(
                    child: Consumer<UserController>(
                      builder: (_, user, __) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Hey, ${user.getUserName.isNotEmpty ? user.getUserName : 'User'}",
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: AppFont.fontFamily,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Image.asset(AppImage.address,
                                  height: 11, width: 9),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _currentCity,
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
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Help icon
                  InkWell(
                    onTap: () => Get.to(() => const HelpAndSupportscreen()),
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Image.asset(AppImage.help, height: 22, width: 22),
                    ),
                  ),
                  // Notification bell
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
                          child: Image.asset(AppImage.notiwhite,
                              height: 42, width: 42),
                        ),
                        if (nc.hasUnread)
                          Positioned(
                            right: 6,
                            top: 6,
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

            // â”€â”€ Body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // "Where to?" search bar
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                          size.width * 0.045,
                          size.height * 0.025,
                          size.width * 0.045,
                          0),
                      child: GestureDetector(
                        onTap: () => _openLocationSelection(),
                        child: _AnimatedGradientBorder(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: size.width * 0.04,
                                vertical: size.height * 0.018),
                            decoration: BoxDecoration(
                              color: const Color(0xffF6F7FB),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3)),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.search_rounded,
                                    color: AppColor.themeColor, size: 22),
                                SizedBox(width: size.width * 0.03),
                                const Expanded(child: _RotatingSearchHint()),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Previous drop locations — nothing rendered if empty.
                    Builder(builder: (_) {
                      final locations = _displayedLocations;
                      if (locations.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: EdgeInsets.fromLTRB(size.width * 0.045,
                            size.height * 0.014, size.width * 0.045, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < locations.length; i++) ...[
                              if (i != 0)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 2),
                                  child: _DashedDivider(),
                                ),
                              Builder(builder: (_) {
                                final loc = locations[i];
                                final isFavorite = _favoriteLocations.any(
                                    (f) =>
                                        _locationKey(f) == _locationKey(loc));
                                return Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () =>
                                            _selectPreviousLocation(loc),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 8),
                                          child: Row(
                                            children: [
                                              Container(
                                                height: 32,
                                                width: 32,
                                                decoration: BoxDecoration(
                                                  color: Colors.grey
                                                      .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Icon(
                                                    isFavorite
                                                        ? Icons.push_pin_rounded
                                                        : Icons.history_rounded,
                                                    color: Colors.grey,
                                                    size: 16),
                                              ),
                                              SizedBox(
                                                  width: size.width * 0.03),
                                              Expanded(
                                                child: Text(
                                                  (loc['address'] ?? '')
                                                      .toString(),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontFamily:
                                                        AppFont.fontFamily,
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w400,
                                                    color: AppColor.blackColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () =>
                                          _toggleFavoriteLocation(loc),
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Icon(
                                          isFavorite
                                              ? Icons.favorite_rounded
                                              : Icons.favorite_border_rounded,
                                          size: 19,
                                          color: isFavorite
                                              ? Colors.redAccent
                                              : Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ],
                          ],
                        ),
                      );
                    }),

                    SizedBox(height: size.height * 0.025),

                    // Active-booking tracker (retailer only): shown while a
                    // booking is Pending/Accepted/Arrived/Pickup/Ongoing.
                    Consumer2<UserController, RetailerHomeController>(
                      builder: (_, user, homeCtrl, __) {
                        final isRetailer =
                            user.getUserType.toLowerCase() == 'retailer';
                        if (!isRetailer || homeCtrl.ongoingBookings.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        final booking = Map<String, dynamic>.from(
                            homeCtrl.ongoingBookings.first as Map);
                        return Padding(
                          padding: EdgeInsets.fromLTRB(size.width * 0.045, 0,
                              size.width * 0.045, size.height * 0.02),
                          child: _ActiveBookingTracker(
                            booking: booking,
                            userId: user.getUserId,
                          ),
                        );
                      },
                    ),

                    // Vehicle options: individual = 3, retailer/business = 6 in 3 x 2 grid
                    Consumer<UserController>(
                      builder: (_, user, __) {
                        final isRetailer = user.getUserType.toLowerCase() == 'retailer';
                        final options = isRetailer
                            ? _retailerVehicleOptions
                            : _customerVehicleOptions;

                        return Padding(
                          padding: EdgeInsets.symmetric(horizontal: size.width * 0.045),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: options.length,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.90,
                            ),
                            itemBuilder: (_, index) {
                              final option = options[index];
                              return _QuickChip(
                                imagePath: option.imagePath,
                                fallbackIcon: option.icon,
                                label: option.label,
                                onTap: () => _openLocationSelection(vehicleName: option.key),
                              );
                            },
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    // Save Address quick-access button
                    GestureDetector(
                      onTap: () => showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        builder: (_) => _SaveAddressSheet(
                          currentLatLng: _currentLatLng,
                        ),
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColor.themeColor.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColor.themeColor.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: AppColor.themeColor.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.bookmark_add_outlined, color: AppColor.themeColor, size: 18),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Save an Address',
                                    style: TextStyle(
                                      fontFamily: AppFont.fontFamily,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: AppColor.themeColor,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Home, Work, Office or any frequent location',
                                    style: TextStyle(
                                      fontFamily: AppFont.fontFamily,
                                      fontSize: 11,
                                      color: AppColor.hintTextColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: AppColor.themeColor, size: 20),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Multidrop feature banner
                    const _MultidropBanner(),

                    SizedBox(height: size.height * 0.03),

                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: size.width * 0.045),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Fast & Reliable Delivery",
                            style: TextStyle(
                              fontFamily: AppFont.fontFamily,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: AppColor.blackColor,
                            ),
                          ),
                          SizedBox(height: size.height * 0.006),
                          const Text(
                            "Book a vehicle in seconds, track in real time.",
                            style: TextStyle(
                              fontFamily: AppFont.fontFamily,
                              fontWeight: FontWeight.w400,
                              fontSize: 13,
                              color: AppColor.hintTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: size.height * 0.01),

                    // Animated bike delivery illustration
                    const _BikeDeliveryAnimation(),

                    SizedBox(height: size.height * 0.02),

                    // Indore Rajwada Palace Pride Emblem & Footer
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Opacity(
                            opacity: 0.7,
                            child: Image.asset(
                              AppImage.rajwadaPalace,
                              width: size.width * 0.38,
                              fit: BoxFit.contain,
                            ),
                          ),
                          SizedBox(height: size.height * 0.01),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                "Made with ",
                                style: TextStyle(
                                  fontFamily: AppFont.fontFamily,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColor.hintTextColor,
                                ),
                              ),
                              Icon(
                                Icons.favorite,
                                color: Colors.red,
                                size: 13,
                              ),
                              const Text(
                                " in Indore",
                                style: TextStyle(
                                  fontFamily: AppFont.fontFamily,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColor.themeColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: size.height * 0.03),
                  ],
                ),
              ),
            ),
          ],
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
  const _SaveAddressSheet({this.currentLatLng});

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
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _fetchSugg(q.trim()));
  }

  Future<void> _fetchSugg(String input) async {
    setState(() => _isLoadingSugg = true);
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
        '&key=${AppConstant.googleApiKey}',
      );
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
    try {
      final res = await postJsonData(
        'user/save_address',
        {
          'label':         effectiveLabel,
          'address':       _pickedAddress,
          'lat':           _pickedLatLng!.latitude,
          'lng':           _pickedLatLng!.longitude,
          'contact_name':  _nameCtrl.text.trim(),
          'contact_phone': _phoneCtrl.text.trim(),
        },
        context,
        headers: {'Authorization': 'Bearer ${AppConstant.token}'},
      );
      if (!mounted) return;
      if (res != null && res['success'] == true) {
        Navigator.pop(context);
        SnackBarToastMessage.showSnackBar(context, 'Address saved as "$effectiveLabel"');
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
            const Text(
              'Save Address',
              style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 17, color: AppColor.blackColor),
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
                  _canSave ? 'Save Address' : 'Select a label and location first',
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
