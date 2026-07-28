import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/utilities/phone_number_formatter.dart';
import 'package:movigo/helper/geocoding_utils.dart';
import 'package:movigo/helper/map_picker.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';

class LocationSelectionScreen extends StatefulWidget {
  final LatLng? initialPickupLatLng;
  final String initialPickupAddress;
  final LatLng? initialDropLatLng;
  final String? initialDropAddress;
  final String? initialDropContactName;
  final String? initialDropContactPhone;

  const LocationSelectionScreen({
    super.key,
    this.initialPickupLatLng,
    required this.initialPickupAddress,
    this.initialDropLatLng,
    this.initialDropAddress,
    this.initialDropContactName,
    this.initialDropContactPhone,
  });

  @override
  State<LocationSelectionScreen> createState() =>
      _LocationSelectionScreenState();
}

class _LocationSelectionScreenState extends State<LocationSelectionScreen> {
  final TextEditingController _pickupCtrl = TextEditingController();
  final TextEditingController _dropCtrl = TextEditingController();
  final FocusNode _pickupFocus = FocusNode();
  final FocusNode _dropFocus = FocusNode();

  String _activeField = "drop";
  List<Map<String, dynamic>> _suggestions = [];
  List<Map<String, dynamic>> _recentDrops = [];
  List<Map<String, dynamic>> _savedAddresses = [];
  Timer? _debounce;

  LatLng? _pickupLatLng;
  String _pickupAddress      = "";
  String _pickupContactName  = "";
  String _pickupContactPhone = "";
  LatLng? _dropLatLng;
  String _dropAddress        = "";
  String _dropContactName    = "";
  String _dropContactPhone   = "";
  bool _isLoadingSuggestions = false;
  bool _isFetchingCurrentLocation = false;

  @override
  void initState() {
    super.initState();
    _pickupLatLng = widget.initialPickupLatLng;
    _pickupAddress = widget.initialPickupAddress;
    _pickupCtrl.text = widget.initialPickupAddress;

    // Pre-fill drop if provided (e.g. from shared location intent or saved address)
    if (widget.initialDropLatLng != null) {
      _dropLatLng = widget.initialDropLatLng;
      _dropAddress = widget.initialDropAddress ?? '';
      _dropCtrl.text = widget.initialDropAddress ?? '';
      _dropContactName = widget.initialDropContactName ?? '';
      _dropContactPhone = widget.initialDropContactPhone ?? '';
    }

    _pickupFocus.addListener(() {
      if (_pickupFocus.hasFocus && mounted) {
        setState(() => _activeField = "pickup");
      }
    });
    _dropFocus.addListener(() {
      if (_dropFocus.hasFocus && mounted) {
        setState(() => _activeField = "drop");
        _fetchRecentDrops();
      }
    });

    final bool dropPreFilled = widget.initialDropLatLng != null;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final bool isFallback = _pickupAddress == "Indore, Madhya Pradesh" ||
                              _pickupAddress == "Fetching location..." ||
                              _pickupAddress.trim().isEmpty;
      if (_pickupLatLng == null || isFallback) {
        await _useCurrentLocation();
      } else if (_looksLikeLatLngText(_pickupAddress)) {
        final address = await _addressFromLatLng(_pickupLatLng!);
        if (mounted) {
          setState(() {
            _pickupAddress = address;
            _pickupCtrl.text = address;
          });
        }
      }
      // Focus pickup when drop is already filled, otherwise focus drop.
      // Focusing drop already triggers _fetchRecentDrops via the focus
      // listener above, so only fetch it explicitly here in the pickup case.
      if (dropPreFilled) {
        _pickupFocus.requestFocus();
        _fetchRecentDrops();
      } else {
        _dropFocus.requestFocus();
      }
      _fetchSavedAddresses();
    });
  }

  Future<void> _fetchRecentDrops() async {
    try {
      final data = await getData('user/recent_drops', context, headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
      });
      if (!mounted) return;
      if (data != null && data['success'] == true) {
        setState(() => _recentDrops =
            List<Map<String, dynamic>>.from(data['data'] ?? []));
      }
    } catch (e) {
      debugPrint('fetchRecentDrops error: $e');
    }
  }

  Future<void> _fetchSavedAddresses() async {
    try {
      final data = await getData('user/saved_addresses', context, headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
      });
      if (!mounted) return;
      if (data != null && data['success'] == true) {
        setState(() => _savedAddresses =
            List<Map<String, dynamic>>.from(data['data'] ?? []));
      }
    } catch (e) {
      debugPrint('fetchSavedAddresses error: $e');
    }
  }

  Future<void> _openMapForActiveField() async {
    final isPickup = _activeField == 'pickup';
    final initial = isPickup ? _pickupLatLng : _dropLatLng;
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLocation: initial,
          isDropLocation: !isPickup,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final ll   = result['location'] as LatLng?;
    final addr = result['address']?.toString() ?? '';
    if (ll == null || addr.isEmpty) return;
    setState(() {
      if (isPickup) {
        _pickupLatLng  = ll;
        _pickupAddress = addr;
        _pickupCtrl.text = addr;
      } else {
        _dropLatLng  = ll;
        _dropAddress = addr;
        _dropCtrl.text = addr;
      }
      _suggestions = [];
    });
  }

  void _showSavedAddressSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        if (_savedAddresses.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.bookmark_border_outlined, size: 52, color: Colors.grey),
                SizedBox(height: 14),
                Text('No saved addresses yet',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey)),
                SizedBox(height: 8),
                Text(
                  'After confirming a drop location, tap "Save address" to store it here for quick access.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.88,
          builder: (_, scrollCtrl) => Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: const [
                    Icon(Icons.bookmark_outlined,
                        color: AppColor.themeColor, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Saved Addresses',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFamily: AppFont.fontFamily,
                        color: AppColor.fontColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  controller: scrollCtrl,
                  itemCount: _savedAddresses.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 68),
                  itemBuilder: (_, i) {
                    final sa = _savedAddresses[i];
                    final label       = sa['label']?.toString() ?? 'Saved';
                    final address     = sa['address']?.toString() ?? '';
                    final contactName = sa['contact_name']?.toString() ?? '';
                    final contactPhone= sa['contact_phone']?.toString() ?? '';
                    final hasContact  = contactName.isNotEmpty || contactPhone.isNotEmpty;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColor.themeColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _savedAddressIcon(label),
                          color: AppColor.themeColor,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          fontFamily: AppFont.fontFamily,
                          color: AppColor.fontColor,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            address,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          if (hasContact)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                [contactName, contactPhone]
                                    .where((s) => s.isNotEmpty)
                                    .join(' · '),
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                            ),
                        ],
                      ),
                      isThreeLine: hasContact,
                      onTap: () async {
                        Navigator.pop(context);
                        final lat = sa['lat'];
                        final lng = sa['lng'];
                        if (lat == null || lng == null) return;
                        final latLng = LatLng(
                          (lat as num).toDouble(),
                          (lng as num).toDouble(),
                        );
                        var addr = address;
                        if (addr.isEmpty || _looksLikeLatLngText(addr)) {
                          addr = await _addressFromLatLng(latLng);
                        }
                        if (!mounted) return;
                        setState(() {
                          if (_activeField == 'pickup') {
                            _pickupLatLng      = latLng;
                            _pickupAddress     = addr;
                            _pickupCtrl.text   = addr;
                            _pickupContactName  = contactName;
                            _pickupContactPhone = contactPhone;
                          } else {
                            _dropLatLng        = latLng;
                            _dropAddress       = addr;
                            _dropCtrl.text     = addr;
                            _dropContactName   = contactName;
                            _dropContactPhone  = contactPhone;
                          }
                          _suggestions = [];
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Feature 1: Swap Pickup/Drop ──────────────────────────────────────────────
  void _swapLocations() {
    setState(() {
      final tmpText    = _pickupCtrl.text;
      final tmpAddress = _pickupAddress;
      final tmpLatLng  = _pickupLatLng;

      _pickupCtrl.text = _dropCtrl.text;
      _pickupAddress   = _dropAddress;
      _pickupLatLng    = _dropLatLng;

      _dropCtrl.text = tmpText;
      _dropAddress   = tmpAddress;
      _dropLatLng    = tmpLatLng;

      _suggestions = [];
    });
  }

  // ── Feature 2: Distance + Duration ───────────────────────────────────────────
  double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = (b.latitude  - a.latitude)  * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(s), math.sqrt(1 - s));
  }

  String get _distanceDurationText {
    if (_pickupLatLng == null || _dropLatLng == null) return '';
    final km   = _haversineKm(_pickupLatLng!, _dropLatLng!);
    final mins = (km / 30 * 60).round().clamp(1, 9999);
    return '~${km.toStringAsFixed(1)} km  ·  ~$mins min';
  }

  // ── Feature 3: Save Drop Address ─────────────────────────────────────────────
  Future<void> _saveDropAddress(
      String label, String contactName, String contactPhone) async {
    if (_dropLatLng == null || _dropAddress.isEmpty) return;
    try {
      final data = await postJsonData(
        'user/save_address',
        {
          'label':         label,
          'address':       _dropAddress,
          'lat':           _dropLatLng!.latitude,
          'lng':           _dropLatLng!.longitude,
          'contact_name':  contactName.trim(),
          'contact_phone': contactPhone.trim(),
        },
        context,
        headers: {
          'Authorization': 'Bearer ${AppConstant.token}',
        },
      );
      if (!mounted) return;
      if (data != null && data['success'] == true) {
        SnackBarToastMessage.showSnackBar(context, 'Saved as "$label"');
        _fetchSavedAddresses();
      } else {
        SnackBarToastMessage.showSnackBar(context, 'Could not save address');
      }
    } catch (e) {
      debugPrint('saveDropAddress error: $e');
      if (mounted) SnackBarToastMessage.showSnackBar(context, 'Could not save address');
    }
  }

  void _showSaveAddressSheet() {
    final nameCtrl  = TextEditingController();
    final phoneCtrl = TextEditingController();
    String? selectedLabel;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final labels = ['Home', 'Work', 'Other'];
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Save address',
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _dropAddress,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Label selector
                  Row(
                    children: labels.map((label) {
                      final icon = label == 'Home'
                          ? Icons.home_outlined
                          : label == 'Work'
                              ? Icons.work_outline
                              : Icons.place_outlined;
                      final isSelected = selectedLabel == label;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: GestureDetector(
                            onTap: () => setSheetState(() => selectedLabel = label),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColor.themeColor
                                    : AppColor.themeColor.withOpacity(0.07),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppColor.themeColor.withOpacity(0.4)),
                              ),
                              child: Column(
                                children: [
                                  Icon(icon,
                                      color: isSelected
                                          ? Colors.white
                                          : AppColor.themeColor,
                                      size: 22),
                                  const SizedBox(height: 5),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontFamily: AppFont.fontFamily,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? Colors.white
                                          : AppColor.themeColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),

                  // Contact name
                  const Text(
                    'Contact Name (optional)',
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColor.fontColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(
                        fontFamily: AppFont.fontFamily, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'e.g. Rahul Sharma',
                      hintStyle: const TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontSize: 13,
                          color: AppColor.hintTextColor),
                      prefixIcon: const Icon(Icons.person_outline,
                          color: AppColor.hintTextColor, size: 18),
                      filled: true,
                      fillColor: const Color(0xffF6F7FB),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: AppColor.themeColor, width: 1.5)),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Contact phone
                  const Text(
                    'Contact Phone (optional)',
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColor.fontColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    inputFormatters: [PhoneNumberFormatter()],
                    style: const TextStyle(
                        fontFamily: AppFont.fontFamily,
                        fontSize: 14,
                        letterSpacing: 1.5),
                    buildCounter: (_, {required currentLength,
                            required isFocused,
                            maxLength}) =>
                        null,
                    decoration: InputDecoration(
                      hintText: '10-digit mobile number',
                      hintStyle: const TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontSize: 13,
                          color: AppColor.hintTextColor,
                          letterSpacing: 0),
                      prefixIcon: const Icon(Icons.phone_iphone_rounded,
                          color: AppColor.hintTextColor, size: 18),
                      filled: true,
                      fillColor: const Color(0xffF6F7FB),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: AppColor.themeColor, width: 1.5)),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: selectedLabel == null
                          ? null
                          : () {
                              Navigator.pop(sheetCtx);
                              _saveDropAddress(
                                  selectedLabel!, nameCtrl.text, phoneCtrl.text);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColor.themeColor,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Feature 4: Open in Google Maps ───────────────────────────────────────────
  Future<void> _openInGoogleMaps(LatLng location) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // Small "use current location" icon shown inside a field's trailing slot
  // while both pickup and drop are still empty — null hides it entirely.
  Widget? _currentLocationTrailingButton(String target) {
    if (_pickupCtrl.text.isNotEmpty || _dropCtrl.text.isNotEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _useCurrentLocationFor(target),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColor.themeColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _isFetchingCurrentLocation
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColor.themeColor),
                )
              : const Icon(Icons.my_location_rounded,
                  color: AppColor.themeColor, size: 18),
        ),
      ),
    );
  }

  // Default "use current location" — fills pickup, matches the historical
  // behaviour still relied on by the splash-fill flow and the pickup row.
  Future<void> _useCurrentLocation() => _useCurrentLocationFor("pickup");

  Future<void> _useCurrentLocationFor(String target) async {
    if (_isFetchingCurrentLocation) return;
    setState(() => _isFetchingCurrentLocation = true);
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
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 8));
      final latLng = LatLng(pos.latitude, pos.longitude);
      final address = await _addressFromLatLng(latLng);

      if (mounted) {
        setState(() {
          if (target == "pickup") {
            _pickupLatLng = latLng;
            _pickupAddress = address;
            _pickupCtrl.text = address;
            _activeField = "drop";
          } else {
            _dropLatLng = latLng;
            _dropAddress = address;
            _dropCtrl.text = address;
            _activeField = "pickup";
          }
          _isFetchingCurrentLocation = false;
        });
        if (target == "pickup") {
          _dropFocus.requestFocus();
        } else {
          _pickupFocus.requestFocus();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isFetchingCurrentLocation = false);
    }
  }


  // Feature 12: label-specific icon for saved addresses
  IconData _savedAddressIcon(String label) {
    final l = label.toLowerCase();
    if (l == 'home') return Icons.home_outlined;
    if (l == 'work') return Icons.work_outline;
    return Icons.place_outlined; // Other
  }

  bool _looksLikeLatLngText(String value) {
    return RegExp(r'^-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?$')
        .hasMatch(value.trim());
  }

  String _buildAddressFromPlacemark(Placemark p, LatLng fallback) {
    final parts = <String?>[
      p.name,
      p.street,
      p.subLocality,
      p.locality,
      p.subAdministrativeArea,
      p.administrativeArea,
      p.postalCode,
    ]
        .where((part) => part != null && part.trim().isNotEmpty)
        .map((part) => part!.trim())
        .toList();

    // Remove duplicates like "Vijay Nagar, Vijay Nagar".
    final uniqueParts = <String>[];
    for (final part in parts) {
      if (!uniqueParts.any((saved) => saved.toLowerCase() == part.toLowerCase())) {
        uniqueParts.add(part);
      }
    }

    final address = uniqueParts.join(', ').trim();
    if (address.isNotEmpty) return address;
    return '${fallback.latitude.toStringAsFixed(6)}, ${fallback.longitude.toStringAsFixed(6)}';
  }

  Future<String> _addressFromLatLng(LatLng latLng) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${latLng.latitude},${latLng.longitude}'
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
    } catch (_) {}

    return '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pickupCtrl.dispose();
    _dropCtrl.dispose();
    _pickupFocus.dispose();
    _dropFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      if (mounted) setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _fetchSuggestions(query.trim());
    });
  }

  Future<void> _fetchSuggestions(String input) async {
    if (mounted) setState(() => _isLoadingSuggestions = true);
    try {
      // Bias results around the retailer's current location (50 km).
      // Falls back to Indore centre if GPS not yet resolved.
      final double lat = _pickupLatLng?.latitude  ?? 22.7196;
      final double lng = _pickupLatLng?.longitude ?? 75.8577;
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(input)}'
        '&location=$lat,$lng'
        '&radius=50000'
        '&components=country:in'
        '&region=in'
        '&key=${AppConstant.googleApiKey}',
      );
      final response = await http.get(url);
      if (!mounted) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final predictions = data['predictions'] as List? ?? [];
      setState(() {
        _suggestions = predictions
            .map<Map<String, dynamic>>((p) => {
                  'place_id': p['place_id'],
                  'description': p['description'],
                  'main_text': (p['structured_formatting']?['main_text']) ?? '',
                  'secondary_text':
                      (p['structured_formatting']?['secondary_text']) ?? '',
                })
            .toList();
      });
    } catch (_) {
      if (mounted) setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _isLoadingSuggestions = false);
    }
  }

  Future<Map<String, dynamic>?> _getDetailsFromPlaceId(String placeId, {String? fallbackAddress}) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$placeId'
        '&fields=geometry,formatted_address,name'
        '&key=${AppConstant.googleApiKey}',
      );
      final res = await http.get(url);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final result = data['result'];
      final loc = result?['geometry']?['location'];
      final formattedAddress = result?['formatted_address']?.toString() ?? '';
      if (loc != null) {
        return {
          'latLng': LatLng(
            (loc['lat'] as num).toDouble(),
            (loc['lng'] as num).toDouble(),
          ),
          'formatted_address': formattedAddress,
        };
      }
    } catch (_) {}

    // Fallback: if Google Place Details fails, still try normal geocoding so
    // retailer drop search does not get stuck without coordinates.
    try {
      if (fallbackAddress != null && fallbackAddress.trim().isNotEmpty) {
        final locations = await locationFromAddress(fallbackAddress);
        if (locations.isNotEmpty) {
          return {
            'latLng': LatLng(locations.first.latitude, locations.first.longitude),
            'formatted_address': fallbackAddress,
          };
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _onSuggestionTap(Map<String, dynamic> suggestion) async {
    final desc = suggestion['description'] as String;
    final placeId = suggestion['place_id'] as String;

    FocusManager.instance.primaryFocus?.unfocus();
    if (mounted) setState(() => _suggestions = []);

    final details = await _getDetailsFromPlaceId(placeId, fallbackAddress: desc);
    final latLng = details?['latLng'] as LatLng?;
    final formattedAddress = details?['formatted_address'] as String? ?? desc;

    if (!mounted) return;

    if (_activeField == "pickup") {
      _pickupCtrl.text = formattedAddress;
      _pickupAddress = formattedAddress;
      _pickupLatLng = latLng;
    } else {
      _dropCtrl.text = formattedAddress;
      _dropAddress = formattedAddress;
      _dropLatLng = latLng;
    }

    setState(() {});
  }

  bool get _canConfirm =>
      _pickupLatLng != null &&
      _dropLatLng != null &&
      _pickupAddress.isNotEmpty &&
      _dropAddress.isNotEmpty;

  void _confirm() {
    if (!_canConfirm) return;
    Navigator.pop(context, {
      'pickup': {
        'lat':           _pickupLatLng!.latitude,
        'lng':           _pickupLatLng!.longitude,
        'address':       _pickupAddress,
        'contact_name':  _pickupContactName,
        'contact_phone': _pickupContactPhone,
      },
      'drop': {
        'lat':           _dropLatLng!.latitude,
        'lng':           _dropLatLng!.longitude,
        'address':       _dropAddress,
        'contact_name':  _dropContactName,
        'contact_phone': _dropContactPhone,
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
          children: [
            // ── AppBar row ───────────────────────────────────────────
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: size.width * 0.04, vertical: 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 40,
                      width: 40,
                      decoration: BoxDecoration(
                        color: AppColor.themeColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: AppColor.themeColor, size: 18),
                    ),
                  ),
                  SizedBox(width: size.width * 0.03),
                  const Text(
                    "Choose Location",
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                      color: AppColor.blackColor,
                    ),
                  ),
                ],
              ),
            ),

            // ── Location input fields ─────────────────────────────────
            Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: size.width * 0.04),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xffF6F7FB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColor.borderColor),
                ),
                child: Column(
                  children: [
                    _LocationField(
                      controller: _pickupCtrl,
                      focusNode: _pickupFocus,
                      hint: "Pickup location",
                      dotColor: AppColor.greenColor,
                      isActive: _activeField == "pickup",
                      onChanged: (v) {
                        setState(() {
                          _pickupAddress = v;
                          _pickupLatLng = null;
                        });
                        _onSearchChanged(v);
                      },
                      onClear: () {
                        _pickupCtrl.clear();
                        _pickupAddress = "";
                        _pickupLatLng = null;
                        if (mounted) setState(() => _suggestions = []);
                      },
                      // Quick shortcut shown only while both fields are
                      // untouched — once the retailer starts typing/picking
                      // either one, this makes way for the clear (x) button.
                      trailing: _currentLocationTrailingButton("pickup"),
                    ),
                    // ── Feature 1: Swap divider row ──────────────────────────
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Divider(height: 1, thickness: 1, color: AppColor.borderColor),
                        GestureDetector(
                          onTap: _swapLocations,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColor.themeColor.withOpacity(0.5), width: 1.5),
                            ),
                            child: const Icon(Icons.swap_vert_rounded,
                                color: AppColor.themeColor, size: 18),
                          ),
                        ),
                      ],
                    ),
                    _LocationField(
                      controller: _dropCtrl,
                      focusNode: _dropFocus,
                      hint: "Drop location",
                      dotColor: AppColor.redColor,
                      isActive: _activeField == "drop",
                      onChanged: (v) {
                        setState(() {
                          _dropAddress = v;
                          _dropLatLng = null;
                        });
                        _onSearchChanged(v);
                      },
                      onClear: () {
                        _dropCtrl.clear();
                        _dropAddress = "";
                        _dropLatLng = null;
                        if (mounted) setState(() => _suggestions = []);
                      },
                      trailing: _currentLocationTrailingButton("drop"),
                    ),
                  ],
                ),
              ),
            ),

            // ── Use Current Location (always shown for pickup field) ──
            if (_activeField == "pickup")
              InkWell(
                onTap: _useCurrentLocation,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: size.width * 0.04, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        height: 36, width: 36,
                        decoration: BoxDecoration(
                          color: AppColor.themeColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _isFetchingCurrentLocation
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColor.themeColor),
                              )
                            : const Icon(Icons.my_location_rounded,
                                color: AppColor.themeColor, size: 20),
                      ),
                      SizedBox(width: size.width * 0.03),
                      const Text('Use current location',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColor.themeColor,
                          )),
                    ],
                  ),
                ),
              ),

            // ── Select on map / Saved addresses ────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                  size.width * 0.04, 10, size.width * 0.04, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _PillActionButton(
                      icon: Icons.map_outlined,
                      label: 'Select on map',
                      onTap: _openMapForActiveField,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PillActionButton(
                      icon: Icons.bookmark_outlined,
                      label: 'Saved addresses',
                      onTap: _showSavedAddressSheet,
                    ),
                  ),
                ],
              ),
            ),

            // ── Feature 2: Distance + Duration Preview ───────────────
            if (_pickupLatLng != null && _dropLatLng != null)
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: size.width * 0.04, vertical: 6),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColor.themeColor.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.straighten_rounded,
                          color: AppColor.themeColor, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        _distanceDurationText,
                        style: const TextStyle(
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

            SizedBox(height: size.height * 0.008),

            // ── Feature 3: Save Drop Address chip ────────────────────
            if (_dropLatLng != null && _dropAddress.isNotEmpty && _suggestions.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: size.width * 0.04, vertical: 4),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _showSaveAddressSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColor.themeColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColor.themeColor.withOpacity(0.35)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bookmark_add_outlined,
                                size: 14, color: AppColor.themeColor),
                            SizedBox(width: 4),
                            Text(
                              'Save address',
                              style: TextStyle(
                                fontFamily: AppFont.fontFamily,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColor.themeColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ── Feature 4: Open in Google Maps ──────────────────
                    GestureDetector(
                      onTap: () => _openInGoogleMaps(_dropLatLng!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.green.withOpacity(0.35)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.map_outlined,
                                size: 14, color: Colors.green),
                            SizedBox(width: 4),
                            Text(
                              'Open in Maps',
                              style: TextStyle(
                                fontFamily: AppFont.fontFamily,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Recent Drop Locations (shown when drop field focused & no typing) ──
            if (_activeField == "drop" &&
                _suggestions.isEmpty &&
                _dropCtrl.text.isEmpty &&
                _recentDrops.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.only(
                    left: size.width * 0.04, top: 8, bottom: 4),
                child: const Text('Recent locations',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey)),
              ),
              ..._recentDrops.map((drop) => InkWell(
                    onTap: () async {
                      final lat = drop['lat'];
                      final lng = drop['lng'];
                      if (lat != null && lng != null) {
                        final latLng = LatLng((lat as num).toDouble(), (lng as num).toDouble());
                        var address = (drop['address'] ?? '').toString();
                        if (address.isEmpty || _looksLikeLatLngText(address)) {
                          address = await _addressFromLatLng(latLng);
                        }
                        if (!mounted) return;
                        setState(() {
                          _dropLatLng = latLng;
                          _dropAddress = address;
                          _dropCtrl.text = address;
                          _suggestions = [];
                        });
                      }
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: size.width * 0.04, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            height: 34, width: 34,
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.history_rounded,
                                color: Colors.grey, size: 18),
                          ),
                          SizedBox(width: size.width * 0.03),
                          Expanded(
                            child: Text(
                              drop['address'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: AppColor.blackColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
            ],


            // ── Suggestions list ──────────────────────────────────────
            if (_isLoadingSuggestions)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColor.themeColor),
                  ),
                ),
              )
            else if (_suggestions.isNotEmpty)
              ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: size.height * 0.3),
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: _suggestions.length,
                    itemBuilder: (_, i) {
                      final s = _suggestions[i];
                      final mainText = s['main_text'] as String;
                      final secondaryText = s['secondary_text'] as String;
                      return InkWell(
                        onTap: () => _onSuggestionTap(s),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: size.width * 0.04,
                              vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                height: 34,
                                width: 34,
                                decoration: BoxDecoration(
                                  color: AppColor.themeColor
                                      .withOpacity(0.07),
                                  borderRadius:
                                      BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                    Icons.location_on_outlined,
                                    color: AppColor.themeColor,
                                    size: 18),
                              ),
                              SizedBox(width: size.width * 0.03),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      mainText.isNotEmpty
                                          ? mainText
                                          : (s['description'] as String),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: AppFont.fontFamily,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13,
                                        color: AppColor.blackColor,
                                      ),
                                    ),
                                    if (secondaryText.isNotEmpty)
                                      Text(
                                        secondaryText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: AppFont.fontFamily,
                                          fontWeight: FontWeight.w400,
                                          fontSize: 12,
                                          color: AppColor.hintTextColor,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                )
            else
              const SizedBox.shrink(),

            // ── Confirm button ────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(size.width * 0.045,
                  size.height * 0.01, size.width * 0.045, size.height * 0.02),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _canConfirm ? _confirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColor.themeColor,
                    disabledBackgroundColor: AppColor.greyLightColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text(
                    "Confirm Locations",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppFont.fontFamily,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

// ── Private widget: "Select on map" / "Saved addresses" pill button ────────

class _PillActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PillActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColor.borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: AppColor.themeColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFont.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColor.themeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Private widget: single location input row ──────────────────────────────

class _LocationField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final Color dotColor;
  final bool isActive;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final Widget? trailing;

  const _LocationField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.dotColor,
    required this.isActive,
    required this.onChanged,
    required this.onClear,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 14),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(
              fontFamily: AppFont.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColor.blackColor,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                fontFamily: AppFont.fontFamily,
                fontSize: 14,
                color: AppColor.hintTextColor,
              ),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          ),
        ),
        if (controller.text.isNotEmpty)
          GestureDetector(
            onTap: onClear,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Container(
                height: 20,
                width: 20,
                decoration: BoxDecoration(
                  color: AppColor.greyLightColor.withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    size: 13, color: AppColor.hintTextColor),
              ),
            ),
          ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
