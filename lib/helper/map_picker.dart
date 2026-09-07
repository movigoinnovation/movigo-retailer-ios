// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/helper/geocoding_utils.dart';
import 'package:movigo/helper/places_session_token.dart';

// ─── Indore service area constants ───────────────────────────────────────────
const double _indoreLat = 22.7196;
const double _indoreLng = 75.8577;
const double _serviceRadiusKm = 50.0; // 50 km from Indore centre
// ─────────────────────────────────────────────────────────────────────────────

/// Drag-the-map, pin-stays-fixed-at-centre location picker (Uber/Ola style).
///
/// The pin is a plain overlay widget anchored to the screen centre, not a
/// GoogleMap [Marker] — moving the map never has to redraw a marker, which is
/// what keeps panning smooth on low-end devices.
///
/// Cost note: reverse geocoding does NOT fire on every pan/settle — that
/// billed a Geocoding API call per camera-idle event and was the single
/// biggest driver of Google Maps Platform cost. It now only fires once,
/// lazily, when the user taps "Confirm Location" (or once on initial load
/// for the pickup/current-location case) — same trigger discipline as the
/// pre-rewrite tap-to-select picker, just kept on this UI.
class MapPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;
  final bool isDropLocation;

  const MapPickerScreen({
    Key? key,
    this.initialLocation,
    this.isDropLocation = false,
  }) : super(key: key);

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? mapController;

  LatLng? selectedLocation;
  String selectedAddress = '';
  bool isOutsideServiceArea = false;

  bool isLoading = false;
  bool isLoadingLocation = true;
  bool mapReady = false;

  // True while the user is actively dragging/zooming the map — lifts the pin
  // and suppresses geocoding until the camera comes to rest.
  bool isMoving = false;

  LatLng? _pendingTarget;
  int _geocodeRequestId = 0;

  // True once the pin has moved away from the last point we actually
  // resolved an address for — gates the lazy, tap-to-confirm geocode call.
  bool _needsGeocode = false;
  LatLng? _lastGeocodedLocation;

  final TextEditingController searchController = TextEditingController();
  List<dynamic> searchResults = [];
  bool isSearching = false;
  // Bundles an Autocomplete typing sequence + its terminating Details call
  // into one billed Places session instead of billing every request alone.
  String? _sessionToken;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  // =============== INITIAL LOCATION =================== //
  Future<void> _initializeLocation() async {
    if (widget.initialLocation != null) {
      selectedLocation = widget.initialLocation;
      setState(() {
        isLoadingLocation = false;
        mapReady = true;
      });
      unawaited(getAddressFromLatLng(selectedLocation!));
      return;
    }

    if (widget.isDropLocation) {
      // No known drop point yet — centre on Indore and let the user drag or
      // search instead of guessing. Don't burn a geocode call on a guess
      // nobody asked for; it resolves lazily once they pan or hit Confirm.
      selectedLocation = const LatLng(_indoreLat, _indoreLng);
      setState(() {
        isLoadingLocation = false;
        mapReady = true;
        _needsGeocode = true;
      });
      return;
    }

    await _getCurrentLocation();
  }

  // ==================== CURRENT LOCATION ==================== //
  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return _setDefaultLocation();

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return _setDefaultLocation();
      }
      if (perm == LocationPermission.deniedForever) {
        return _setDefaultLocation();
      }

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      );

      selectedLocation = LatLng(pos.latitude, pos.longitude);
      unawaited(getAddressFromLatLng(selectedLocation!));
    } catch (e) {
      _setDefaultLocation();
    } finally {
      setState(() {
        isLoadingLocation = false;
        mapReady = true;
      });
    }
  }

  void _setDefaultLocation() {
    selectedLocation = const LatLng(_indoreLat, _indoreLng);
    selectedAddress = "Indore, Madhya Pradesh";
  }

  // =================== MAP CREATED =================== //
  void onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  // =================== CAMERA CALLBACKS =================== //
  // Only tracked in a plain field while moving — no setState per frame, so
  // panning/zooming never triggers a widget rebuild until it settles.
  void _onCameraMoveStarted() {
    if (!isMoving) setState(() => isMoving = true);
  }

  void _onCameraMove(CameraPosition pos) {
    _pendingTarget = pos.target;
  }

  void _onCameraIdle() {
    final target = _pendingTarget ?? selectedLocation;
    if (target == null) return;

    // Service-area check is a local haversine calc — free, so it can still
    // update live as the pin moves. The address itself is NOT re-fetched
    // here; it resolves lazily on Confirm (see _movedSignificantly).
    setState(() {
      isMoving = false;
      selectedLocation = target;
      isOutsideServiceArea = !_isWithinServiceArea(target);
      _needsGeocode = _movedSignificantly(target, _lastGeocodedLocation);
    });
  }

  // Treat the search/place-details flow's exact landing point as "already
  // resolved" (avoids a redundant confirm-time geocode right after we just
  // got the address from Place Details), while still catching a genuine
  // user pan away from that point.
  bool _movedSignificantly(LatLng a, LatLng? b) {
    if (b == null) return true;
    return _distanceInKm(a.latitude, a.longitude, b.latitude, b.longitude) >
        0.03; // 30 metres
  }

  // ======= GET ADDRESS FROM LAT LNG (Google Geocoding API) ======= //
  Future<void> getAddressFromLatLng(LatLng pos) async {
    final requestId = ++_geocodeRequestId;
    final withinArea = _isWithinServiceArea(pos);

    if (mounted) {
      setState(() {
        isLoading = true;
        isOutsideServiceArea = !withinArea;
      });
    }

    if (!withinArea) {
      if (mounted) {
        setState(() {
          selectedAddress = 'Outside service area';
          isLoading = false;
          _needsGeocode = false;
          _lastGeocodedLocation = pos;
        });
      }
      return;
    }

    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${pos.latitude},${pos.longitude}'
        '&key=${AppConstant.googleApiKey}'
        '&language=en',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (requestId != _geocodeRequestId || !mounted) return;

      String address = 'Unable to get address';
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List? ?? [];
        if (results.isNotEmpty) {
          final addr = bestAddressFromGeoResults(results);
          if (addr.isNotEmpty) address = addr;
        }
      }
      setState(() {
        selectedAddress = address;
        isLoading = false;
        _needsGeocode = false;
        _lastGeocodedLocation = pos;
      });
    } catch (e) {
      if (requestId != _geocodeRequestId || !mounted) return;
      // Leave _needsGeocode as-is so a retry (e.g. pressing Confirm again)
      // attempts the lookup again instead of silently giving up.
      setState(() {
        selectedAddress = 'Unable to get address';
        isLoading = false;
      });
    }
  }

  // ===================== INDORE SERVICE AREA HELPERS ======================== //

  /// Haversine distance in km between two LatLng points
  double _distanceInKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _toRad(double deg) => deg * pi / 180;

  bool _isWithinServiceArea(LatLng point) =>
      _distanceInKm(_indoreLat, _indoreLng, point.latitude, point.longitude) <=
      _serviceRadiusKm;

  // ===================== SEARCH LOCATIONS (INDORE-BIASED) ======================= //
  Future<void> searchLocation(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      return;
    }

    setState(() => isSearching = true);
    _sessionToken ??= PlacesSessionToken.generate();

    final url =
        "https://maps.googleapis.com/maps/api/place/autocomplete/json"
        "?input=${Uri.encodeComponent(query)}"
        "&location=$_indoreLat,$_indoreLng"
        "&radius=50000"
        "&strictbounds=true"
        "&sessiontoken=$_sessionToken"
        "&key=${AppConstant.googleApiKey}";

    final response = await http.get(Uri.parse(url));
    if (!mounted) return;

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      searchResults = data["status"] == "OK" ? data["predictions"] : [];
    }

    setState(() => isSearching = false);
  }

  // ===================== GET LAT LNG FROM PLACE ID ======================= //
  Future<void> getLatLngFromPlaceId(
      String placeId, String addressDescription) async {
    final url =
        "https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId"
        "&fields=geometry,formatted_address"
        "&sessiontoken=$_sessionToken"
        "&key=${AppConstant.googleApiKey}";
    // Details call ends the session — next search starts a fresh one.
    _sessionToken = null;

    final response = await http.get(Uri.parse(url));
    if (!mounted) return;

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final loc = data["result"]["geometry"]["location"];
      final newLoc = LatLng(loc["lat"], loc["lng"]);

      setState(() {
        selectedLocation = newLoc;
        selectedAddress = addressDescription;
        isOutsideServiceArea = !_isWithinServiceArea(newLoc);
        searchResults = [];
        searchController.clear();
        // We already have the exact address from the suggestion — mark it
        // resolved so Confirm doesn't fire a redundant geocode call.
        _needsGeocode = false;
        _lastGeocodedLocation = newLoc;
      });

      // Bump the request id so any in-flight geocode reply can't clobber
      // this exact result with a slower/looser one.
      _geocodeRequestId++;
      mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: newLoc, zoom: 16),
        ),
      );
    }
  }

  // ===================== CONFIRM ======================= //
  // The one and only place a geocode call is guaranteed to fire for a
  // deliberate placement — mirrors the old tap-to-select picker's trigger.
  Future<void> _onConfirmPressed() async {
    if (selectedLocation == null || isOutsideServiceArea) return;

    if (_needsGeocode) {
      await getAddressFromLatLng(selectedLocation!);
      if (!mounted || isOutsideServiceArea) return;
    }

    Navigator.pop(context, {
      "location": selectedLocation,
      "address": selectedAddress,
    });
  }

  // ===================== UI ======================= //
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColor.themeColor,
        title: Text(
          widget.isDropLocation ? "Select Drop Location" : "Select Pickup Location",
          style: TextStyle(
              fontFamily: AppFont.fontFamily,
              color: Colors.white,
              fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // ---------------- GOOGLE MAP ---------------- //
          isLoadingLocation
              ? Center(
                  child: CircularProgressIndicator(color: AppColor.themeColor))
              : GoogleMap(
                  onMapCreated: onMapCreated,
                  initialCameraPosition: CameraPosition(
                    target: selectedLocation ??
                        const LatLng(_indoreLat, _indoreLng),
                    zoom: 15,
                  ),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: false,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  buildingsEnabled: false,
                  indoorViewEnabled: false,
                  onCameraMoveStarted: _onCameraMoveStarted,
                  onCameraMove: _onCameraMove,
                  onCameraIdle: _onCameraIdle,
                ),

          // ---------------- FIXED CENTRE PIN ---------------- //
          if (!isLoadingLocation)
            IgnorePointer(
              child: Center(
                child: Padding(
                  // Shift up by half the pin's own height so the pin's tip
                  // (not its centre) lands on the actual map centre point.
                  padding: const EdgeInsets.only(bottom: 36),
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    offset: isMoving ? const Offset(0, -0.25) : Offset.zero,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 40,
                          color: isOutsideServiceArea
                              ? Colors.grey
                              : AppColor.themeColor,
                          shadows: const [
                            Shadow(color: Colors.black38, blurRadius: 4),
                          ],
                        ),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: isMoving ? 1 : 0,
                          child: Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: const BoxDecoration(
                              color: Colors.black26,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ---------------- SEARCH BAR ---------------- //
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(color: Colors.black26, blurRadius: 6)
                    ],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: "Search location...",
                      border: InputBorder.none,
                      prefixIcon:
                          Icon(Icons.search, color: AppColor.themeColor),
                    ),
                    onChanged: (val) {
                      if (_debounce?.isActive ?? false) {
                        _debounce?.cancel();
                      }

                      _debounce = Timer(
                        const Duration(milliseconds: 300),
                        () => searchLocation(val),
                      );
                    },
                  ),
                ),
                if (isSearching)
                  Container(
                    margin: EdgeInsets.only(top: 8),
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        CircularProgressIndicator(
                            strokeWidth: 2, color: AppColor.themeColor),
                        SizedBox(width: 12),
                        Text("Searching...",
                            style: TextStyle(
                                fontFamily: AppFont.fontFamily,
                                color: AppColor.greyLightColor)),
                      ],
                    ),
                  ),
                if (searchResults.isNotEmpty && !isSearching)
                  Container(
                    margin: EdgeInsets.only(top: 8),
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: BoxConstraints(maxHeight: 260),
                    child: ListView.separated(
                      itemCount: searchResults.length,
                      separatorBuilder: (_, __) => Divider(),
                      itemBuilder: (_, i) {
                        final item = searchResults[i];
                        return ListTile(
                          leading: Icon(Icons.location_on,
                              color: AppColor.themeColor),
                          title: Text(item["description"]),
                          onTap: () => getLatLngFromPlaceId(
                            item["place_id"],
                            item["description"],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // ---------------- CONFIRM PANEL ---------------- //
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.place_rounded,
                            size: 16,
                            color: isOutsideServiceArea
                                ? Colors.grey
                                : AppColor.themeColor),
                        const SizedBox(width: 6),
                        Text(
                          widget.isDropLocation
                              ? "Drop location"
                              : "Pickup location",
                          style: TextStyle(
                              fontFamily: AppFont.fontFamily,
                              color: AppColor.greyLightColor),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      selectedLocation == null || (_needsGeocode && !isLoading)
                          ? "Move the map to choose a location"
                          : isLoading
                              ? "Fetching address..."
                              : selectedAddress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFont.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isOutsideServiceArea
                            ? Colors.grey
                            : AppColor.blackColor,
                      ),
                    ),
                    if (isOutsideServiceArea) ...[
                      const SizedBox(height: 4),
                      const Text(
                        "We're not available in this area yet. Move the pin closer to Indore.",
                        style: TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontSize: 12,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColor.themeColor,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: (selectedLocation == null ||
                                isLoading ||
                                isOutsideServiceArea)
                            ? null
                            : _onConfirmPressed,
                        child: Text(
                          "Confirm Location",
                          style: TextStyle(
                            fontFamily: AppFont.fontFamily,
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
