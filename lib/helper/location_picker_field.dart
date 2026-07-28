import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/helper/geocoding_utils.dart';

class LocationPickerField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final bool isPickupLocation;
  final Function(double lat, double lng)? onLocationSelected;

  const LocationPickerField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.isPickupLocation,
    this.onLocationSelected,
  });

  @override
  State<LocationPickerField> createState() => _LocationPickerFieldState();
}

class _LocationPickerFieldState extends State<LocationPickerField> {
  final FocusNode _focusNode = FocusNode();
  List<Map<String, dynamic>> _suggestions = [];
  List<Map<String, dynamic>> _recentLocations = [];
  List<Map<String, dynamic>> _serverLocations = [];
  Timer? _debounce;
  bool _showSuggestions = false;
  bool _isLoadingSuggestions = false;

  @override
  void initState() {
    super.initState();
    _loadRecentLocations();
    if (!widget.isPickupLocation) {
      _loadServerLocations();
    }
    
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && mounted) {
        setState(() => _showSuggestions = true);
      } else {
        setState(() => _showSuggestions = false);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  // ─── Location History Management ─────────────────────────────────────────────
  Future<void> _loadRecentLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String key = widget.isPickupLocation ? 'recent_pickups' : 'recent_drops';
      final String? historyJson = prefs.getString(key);
      
      if (historyJson != null) {
        final List<dynamic> history = jsonDecode(historyJson);
        setState(() {
          _recentLocations = List<Map<String, dynamic>>.from(history);
        });
      }
    } catch (e) {
      debugPrint('Error loading recent locations: $e');
    }
  }

  Future<void> _saveToHistory(String address, double lat, double lng) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String key = widget.isPickupLocation ? 'recent_pickups' : 'recent_drops';
      
      final Map<String, dynamic> newLocation = {
        'address': address,
        'lat': lat,
        'lng': lng,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      List<Map<String, dynamic>> history = [];
      final String? existingJson = prefs.getString(key);
      if (existingJson != null) {
        history = List<Map<String, dynamic>>.from(jsonDecode(existingJson));
      }

      // Remove duplicate
      history.removeWhere((item) => 
          item['address'] == address || 
          ((item['lat'] as double) - lat).abs() < 0.001 && ((item['lng'] as double) - lng).abs() < 0.001
      );

      history.insert(0, newLocation);
      if (history.length > 10) {
        history = history.take(10).toList();
      }

      await prefs.setString(key, jsonEncode(history));
      setState(() {
        _recentLocations = history;
      });
    } catch (e) {
      debugPrint('Error saving to history: $e');
    }
  }

  // ─── Server Data (for drop locations) ───────────────────────────────────────
  Future<void> _loadServerLocations() async {
    try {
      final url = Uri.parse('${AppConstant.apiBaseUrl}user/recent_drops');
      final response = await http.get(url, headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
      });
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _serverLocations = List<Map<String, dynamic>>.from(data['data'] ?? []);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading server locations: $e');
    }
  }

  // ─── Places API Search ───────────────────────────────────────────────────────
  Future<void> _searchPlaces(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
      });
      return;
    }

    setState(() => _isLoadingSuggestions = true);

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(query)}'
        '&location=22.7196,75.8577'
        '&radius=50000'
        '&strictbounds=true'
        '&components=country:IN'
        '&key=${AppConstant.googleApiKey}',
      );

      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['status'] == 'OK' && mounted) {
          final predictions = data['predictions'] as List<dynamic>;
          
          setState(() {
            _suggestions = predictions.map((p) => {
              'place_id': p['place_id'],
              'description': p['description'],
              'main_text': p['structured_formatting']?['main_text'] ?? '',
              'secondary_text': p['structured_formatting']?['secondary_text'] ?? '',
            }).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Places search error: $e');
    }

    setState(() => _isLoadingSuggestions = false);
  }

  // ─── Place Selection ─────────────────────────────────────────────────────────
  Future<void> _selectPlace(Map<String, dynamic> place) async {
    try {
      if (place['place_id'] != null) {
        // Get place details from place_id
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/details/json'
          '?place_id=${place['place_id']}'
          '&fields=geometry,formatted_address'
          '&key=${AppConstant.googleApiKey}',
        );

        final response = await http.get(url);
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          if (data['status'] == 'OK') {
            final geometry = data['result']['geometry'];
            final location = geometry['location'];
            final address = data['result']['formatted_address'];
            
            _finishSelection(address, location['lat'], location['lng']);
          }
        }
      } else {
        // From history or server data
        final address = place['address'] ?? place['drop_address'] ?? '';
        final lat = place['lat'] ?? place['drop_lat'] ?? 0.0;
        final lng = place['lng'] ?? place['drop_lng'] ?? 0.0;
        
        _finishSelection(address, lat, lng);
      }
    } catch (e) {
      debugPrint('Place selection error: $e');
    }
  }

  void _finishSelection(String address, double lat, double lng) {
    widget.controller.text = address;
    _saveToHistory(address, lat, lng);
    
    if (widget.onLocationSelected != null) {
      widget.onLocationSelected!(lat, lng);
    }
    
    setState(() {
      _suggestions = [];
      _showSuggestions = false;
    });
    
    _focusNode.unfocus();
  }

  // ─── Current Location (for pickup) ───────────────────────────────────────────
  Future<void> _useCurrentLocation() async {
    try {
      // Always take a fresh GPS fix — AppConstant.currentLat/Lng is only
      // pre-fetched once at splash-screen launch, so trusting it here served
      // up a stale "current location" from whenever the app was opened.
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await Geolocator.requestPermission();
      }

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);
      final double lat = pos.latitude;
      final double lng = pos.longitude;

      // Get address from coordinates
      final address = await _addressFromLatLng(lat, lng);
      _finishSelection(address, lat, lng);
    } catch (e) {
      debugPrint('Error getting current location: $e');
    }
  }

  Future<String> _addressFromLatLng(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=$lat,$lng'
        '&key=${AppConstant.googleApiKey}'
        '&language=en',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List? ?? [];
        if (data['status'] == 'OK' && results.isNotEmpty) {
          final addr = bestAddressFromGeoResults(results);
          if (addr.isNotEmpty) return addr;
        }
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
    }
    return '$lat, $lng';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(14),
            border: _showSuggestions
                ? Border.all(color: AppColor.themeColor, width: 1)
                : null,
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 500), () {
                _searchPlaces(value);
              });
            },
            style: const TextStyle(
              fontFamily: AppFont.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Colors.black,
            ),
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: const TextStyle(
                fontFamily: AppFont.fontFamily,
                fontSize: 14,
                color: Color(0xFF9E9E9E),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.controller.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey, size: 20),
                      onPressed: () {
                        widget.controller.clear();
                        setState(() {
                          _suggestions = [];
                        });
                      },
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.location_on_outlined, color: Colors.grey, size: 20),
                    ),
                  if (widget.isPickupLocation)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        icon: const Icon(Icons.my_location, color: AppColor.themeColor, size: 20),
                        onPressed: _useCurrentLocation,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        
        // Inline Suggestions
        if (_showSuggestions) _buildInlineSuggestions(),
      ],
    );
  }

  Widget _buildInlineSuggestions() {
    final allSuggestions = <Map<String, dynamic>>[
      if (_isLoadingSuggestions) 
        {'type': 'loading'},
      ..._suggestions.map((s) => {...s, 'type': 'search'}),
      if (_suggestions.isEmpty && widget.controller.text.isEmpty) ...[
        if (widget.isPickupLocation)
          {'type': 'current_location'},
        ..._recentLocations.take(3).map((s) => {...s, 'type': 'recent'}),
        if (!widget.isPickupLocation)
          ..._serverLocations.take(3).map((s) => {...s, 'type': 'server'}),
      ],
    ];

    if (allSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: allSuggestions.length,
        itemBuilder: (context, index) {
          final suggestion = allSuggestions[index];

          if (suggestion['type'] == 'loading') {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          if (suggestion['type'] == 'current_location') {
            return ListTile(
              dense: true,
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColor.themeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.my_location,
                  color: AppColor.themeColor,
                  size: 16,
                ),
              ),
              title: const Text(
                'Use current location',
                style: TextStyle(
                  fontFamily: AppFont.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColor.themeColor,
                ),
              ),
              onTap: () => _useCurrentLocation(),
            );
          }

          IconData iconData = Icons.location_on_outlined;
          Color iconColor = AppColor.themeColor;
          String title = '';
          String? subtitle;

          switch (suggestion['type']) {
            case 'search':
              title = suggestion['main_text'] ?? suggestion['description'];
              subtitle = suggestion['secondary_text'];
              break;
            case 'recent':
              title = suggestion['address'] ?? '';
              iconData = Icons.history;
              iconColor = Colors.grey;
              break;
            case 'server':
              title = suggestion['drop_address'] ?? suggestion['address'] ?? '';
              iconData = Icons.bookmark_outlined;
              iconColor = Colors.blue;
              break;
          }

          return ListTile(
            dense: true,
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(iconData, color: iconColor, size: 16),
            ),
            title: Text(
              title,
              style: const TextStyle(
                fontFamily: AppFont.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: subtitle != null
                ? Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            onTap: () => _selectPlace(suggestion),
          );
        },
      ),
    );
  }
}
