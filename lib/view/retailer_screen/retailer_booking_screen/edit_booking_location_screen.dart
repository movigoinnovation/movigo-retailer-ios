import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/helper/location_picker_field.dart';
import 'package:movigo/helper/map_picker.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';
import 'package:movigo/utilities/app_constant.dart';

/// One intermediate stop being edited — mirrors Booking.extra_drops shape
/// (minus the final drop, which stays tracked separately as "drop").
class _StopDraft {
  final TextEditingController controller;
  double? lat, lng;
  _StopDraft({String initialAddress = ''}) : controller = TextEditingController(text: initialAddress);
  void dispose() => controller.dispose();
}

/// Lets a retailer edit the pickup, drop, and intermediate stops of a booking
/// that has already been created — driver may or may not be assigned yet.
/// Pickup AND the stop list are locked once the driver has reached pickup
/// (pass [canEditPickup]: false once status is Arrived/Pickup/Ongoing) — the
/// backend enforces this rule too, so this is only for a clean UI, not the
/// actual guard. Only the final drop stays editable past that point.
class EditBookingLocationScreen extends StatefulWidget {
  final String bookingId;
  final bool canEditPickup;
  final String currentPickupAddress;
  final String currentDropAddress;
  final List<Map<String, dynamic>> currentStops;

  const EditBookingLocationScreen({
    super.key,
    required this.bookingId,
    required this.canEditPickup,
    required this.currentPickupAddress,
    required this.currentDropAddress,
    this.currentStops = const [],
  });

  @override
  State<EditBookingLocationScreen> createState() => _EditBookingLocationScreenState();
}

class _EditBookingLocationScreenState extends State<EditBookingLocationScreen> {
  late final TextEditingController _pickupCtrl;
  late final TextEditingController _dropCtrl;
  double? _pickupLat, _pickupLng;
  double? _dropLat, _dropLng;
  late List<_StopDraft> _stops;
  bool _stopsTouched = false;
  bool _submitting = false;
  bool _savingAddress = false;

  static const _navy = AppColor.themeColor;
  static const _navyDeep = AppColor.logobgcolor;

  @override
  void initState() {
    super.initState();
    _pickupCtrl = TextEditingController(text: widget.currentPickupAddress);
    _dropCtrl = TextEditingController(text: widget.currentDropAddress);
    _stops = widget.currentStops
        .map((s) => _StopDraft(initialAddress: (s['address'] ?? '').toString())
          ..lat = (s['lat'] ?? s['latitude']) == null ? null : double.tryParse((s['lat'] ?? s['latitude']).toString())
          ..lng = (s['lng'] ?? s['longitude']) == null ? null : double.tryParse((s['lng'] ?? s['longitude']).toString()))
        .toList();
  }

  @override
  void dispose() {
    _pickupCtrl.dispose();
    _dropCtrl.dispose();
    for (final s in _stops) {
      s.dispose();
    }
    super.dispose();
  }

  bool get _hasChanges =>
      (_pickupLat != null && _pickupLng != null) ||
      (_dropLat != null && _dropLng != null) ||
      _stopsTouched;

  Future<void> _pickOnMap({required bool isPickup, _StopDraft? stop}) async {
    final LatLng? initial = isPickup
        ? (_pickupLat != null ? LatLng(_pickupLat!, _pickupLng!) : null)
        : (stop != null
            ? (stop.lat != null ? LatLng(stop.lat!, stop.lng!) : null)
            : (_dropLat != null ? LatLng(_dropLat!, _dropLng!) : null));

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

    final LatLng location = result['location'] as LatLng;
    final String address = result['address']?.toString() ?? '';

    setState(() {
      if (isPickup) {
        _pickupCtrl.text = address;
        _pickupLat = location.latitude;
        _pickupLng = location.longitude;
      } else if (stop != null) {
        stop.controller.text = address;
        stop.lat = location.latitude;
        stop.lng = location.longitude;
        _stopsTouched = true;
      } else {
        _dropCtrl.text = address;
        _dropLat = location.latitude;
        _dropLng = location.longitude;
      }
    });
  }

  void _addStop() {
    setState(() {
      _stops.add(_StopDraft());
      _stopsTouched = true;
    });
  }

  void _removeStop(int index) {
    setState(() {
      _stops[index].dispose();
      _stops.removeAt(index);
      _stopsTouched = true;
    });
  }

  Future<void> _saveDropAsAddress() async {
    if (_dropLat == null || _dropLng == null || _dropCtrl.text.trim().isEmpty) return;
    final label = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SaveAddressLabelSheet(address: _dropCtrl.text.trim()),
    );
    if (label == null || !mounted) return;

    setState(() => _savingAddress = true);
    try {
      final res = await postJsonData(
        'user/save_address',
        {
          'label': label,
          'address': _dropCtrl.text.trim(),
          'lat': _dropLat,
          'lng': _dropLng,
        },
        context,
        headers: {'Authorization': 'Bearer ${AppConstant.token}'},
      );
      if (!mounted) return;
      if (res != null && res['success'] == true) {
        SnackBarToastMessage.showSnackBar(context, 'Address saved');
      } else {
        SnackBarToastMessage.showSnackBar(context, 'Could not save address. Try again.');
      }
    } catch (_) {
      if (mounted) SnackBarToastMessage.showSnackBar(context, 'Could not save address. Try again.');
    } finally {
      if (mounted) setState(() => _savingAddress = false);
    }
  }

  Future<void> _submit() async {
    if (!_hasChanges) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a new pickup, drop, or stop first')),
      );
      return;
    }
    if (_stopsTouched) {
      final incomplete = _stops.any((s) => s.lat == null || s.lng == null || s.controller.text.trim().isEmpty);
      if (incomplete) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Finish setting a location for every stop, or remove the empty one')),
        );
        return;
      }
    }

    setState(() => _submitting = true);
    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final res = await provider.editBookingLocationApi(
      context,
      bookingId: widget.bookingId,
      pickupAddress: _pickupLat != null ? _pickupCtrl.text : null,
      pickupLat: _pickupLat,
      pickupLng: _pickupLng,
      dropAddress: _dropLat != null ? _dropCtrl.text : null,
      dropLat: _dropLat,
      dropLng: _dropLng,
      stops: _stopsTouched
          ? _stops.map((s) => {'address': s.controller.text.trim(), 'lat': s.lat, 'lng': s.lng}).toList()
          : null,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    final bool success = res?['success'] == true;
    if (!success) {
      final msg = ((res?['message'] as List?)?.isNotEmpty == true)
          ? res!['message'][0].toString()
          : 'Could not update location right now.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    final newPrice = res?['data']?['booking_price']?.toString();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56, height: 56,
                decoration: const BoxDecoration(color: Color(0xFFE7F9EF), shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: AppColor.successCOlor, size: 30),
              ),
              const SizedBox(height: 16),
              const Text('Location Updated', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              const SizedBox(height: 8),
              Text(
                newPrice != null ? 'New fare: ₹$newPrice' : 'The route has been updated.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 14, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Done', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  // ── Shared building blocks ────────────────────────────────────────────

  Widget _sectionCard({required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFECEFF3)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.035), blurRadius: 14, offset: const Offset(0, 6)),
          ],
        ),
        child: child,
      );

  Widget _sectionLabel({required IconData icon, required Color color, required String title, String? subtitle}) => Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFamily: AppFont.fontFamily, color: Color(0xFF0F172A))),
                if (subtitle != null)
                  Text(subtitle, style: const TextStyle(fontSize: 11.5, fontFamily: AppFont.fontFamily, color: Color(0xFF94A3B8))),
              ],
            ),
          ),
        ],
      );

  Widget _mapButton({required VoidCallback? onTap}) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
        decoration: BoxDecoration(
          color: enabled ? _navy.withOpacity(0.06) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: enabled ? _navy.withOpacity(0.18) : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Icon(Icons.map_rounded, color: enabled ? _navy : AppColor.greyColor, size: 17),
            const SizedBox(width: 9),
            Text(
              'Select on map',
              style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, fontWeight: FontWeight.w700, color: enabled ? _navy : AppColor.greyColor),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: Column(
        children: [
          // ── Brand hero header ───────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(8, topInset + 8, 20, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_navy, _navyDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(width: 4),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Edit Trip Route', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white)),
                      SizedBox(height: 2),
                      Text('Change pickup, drop or add a stop', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.route_rounded, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),

          // ── Scrollable body ─────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!widget.canEditPickup)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: Colors.amber.shade700, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Driver has already reached pickup — only the drop location can be changed now.',
                              style: TextStyle(fontSize: 12.5, fontFamily: AppFont.fontFamily, color: Color(0xFF6B4C00)),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── Pickup ──────────────────────────────────────────
                  _sectionCard(
                    child: AbsorbPointer(
                      absorbing: !widget.canEditPickup,
                      child: Opacity(
                        opacity: widget.canEditPickup ? 1 : 0.45,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionLabel(icon: Icons.trip_origin, color: AppColor.successCOlor, title: 'Pickup Location'),
                            const SizedBox(height: 12),
                            LocationPickerField(
                              controller: _pickupCtrl,
                              hintText: 'Search new pickup location',
                              isPickupLocation: true,
                              onLocationSelected: (lat, lng) {
                                setState(() {
                                  _pickupLat = lat;
                                  _pickupLng = lng;
                                });
                              },
                            ),
                            _mapButton(onTap: widget.canEditPickup ? () => _pickOnMap(isPickup: true) : null),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Stops ───────────────────────────────────────────
                  if (widget.canEditPickup) ...[
                    _sectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel(
                            icon: Icons.alt_route_rounded,
                            color: const Color(0xFFB45309),
                            title: 'Stops',
                            subtitle: _stops.isEmpty ? 'Direct trip — no stops added' : '${_stops.length} stop${_stops.length > 1 ? 's' : ''} on the way',
                          ),
                          for (int i = 0; i < _stops.length; i++) ...[
                            const SizedBox(height: 14),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 12),
                                  width: 22, height: 22,
                                  decoration: BoxDecoration(color: const Color(0xFFFEF3E2), shape: BoxShape.circle, border: Border.all(color: const Color(0xFFFCD9A8))),
                                  child: Center(
                                    child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFB45309), fontFamily: AppFont.fontFamily)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      LocationPickerField(
                                        controller: _stops[i].controller,
                                        hintText: 'Search stop ${i + 1} location',
                                        isPickupLocation: false,
                                        onLocationSelected: (lat, lng) {
                                          setState(() {
                                            _stops[i].lat = lat;
                                            _stops[i].lng = lng;
                                            _stopsTouched = true;
                                          });
                                        },
                                      ),
                                      _mapButton(onTap: () => _pickOnMap(isPickup: false, stop: _stops[i])),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _removeStop(i),
                                  icon: const Icon(Icons.close_rounded, size: 19, color: Color(0xFF94A3B8)),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),
                          GestureDetector(
                            onTap: _addStop,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _navy.withOpacity(0.25), style: BorderStyle.solid),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.add_rounded, size: 18, color: _navy),
                                  const SizedBox(width: 6),
                                  Text('Add Stop', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13.5, fontWeight: FontWeight.w700, color: _navy)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── Drop ────────────────────────────────────────────
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel(icon: Icons.location_on_rounded, color: const Color(0xFFDC2626), title: 'Drop Location'),
                        const SizedBox(height: 12),
                        LocationPickerField(
                          controller: _dropCtrl,
                          hintText: 'Search new drop location',
                          isPickupLocation: false,
                          onLocationSelected: (lat, lng) {
                            setState(() {
                              _dropLat = lat;
                              _dropLng = lng;
                            });
                          },
                        ),
                        _mapButton(onTap: () => _pickOnMap(isPickup: false)),
                        if (_dropLat != null) ...[
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: _savingAddress ? null : _saveDropAsAddress,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _savingAddress
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _navy))
                                    : const Icon(Icons.bookmark_add_outlined, size: 16, color: _navy),
                                const SizedBox(width: 6),
                                const Text('Save this address', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, fontFamily: AppFont.fontFamily, color: _navy)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: _navy.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 16, color: _navy),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Fare will be recalculated automatically based on the new route distance.',
                            style: TextStyle(fontSize: 11.5, fontFamily: AppFont.fontFamily, color: Color(0xFF475569)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: bottomInset),
                ],
              ),
            ),
          ),

          // ── Sticky action bar ───────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, -3))],
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_hasChanges && !_submitting) ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  disabledBackgroundColor: const Color(0xFFCBD5E1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Update Route', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: AppFont.fontFamily, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Save-as-address label picker ──────────────────────────────────────────
class _SaveAddressLabelSheet extends StatefulWidget {
  final String address;
  const _SaveAddressLabelSheet({required this.address});

  @override
  State<_SaveAddressLabelSheet> createState() => _SaveAddressLabelSheetState();
}

class _SaveAddressLabelSheetState extends State<_SaveAddressLabelSheet> {
  static const _labels = ['Home', 'Work', 'Office', 'Godown', 'Other'];
  String _selected = 'Other';
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2))),
          const Text('Save Address', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, fontFamily: AppFont.fontFamily, color: Color(0xFF0F172A))),
          const SizedBox(height: 6),
          Text(widget.address, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontFamily: AppFont.fontFamily, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _labels.map((l) {
              final selected = l == _selected;
              return ChoiceChip(
                label: Text(l, style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, color: selected ? Colors.white : const Color(0xFF0F172A))),
                selected: selected,
                selectedColor: AppColor.themeColor,
                backgroundColor: const Color(0xFFF1F5F9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide.none),
                onSelected: (_) => setState(() => _selected = l),
              );
            }).toList(),
          ),
          if (_selected == 'Other') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customCtrl,
              style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Label (e.g. Warehouse 2)',
                hintStyle: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final label = _selected == 'Other' && _customCtrl.text.trim().isNotEmpty
                    ? _customCtrl.text.trim()
                    : _selected;
                Navigator.pop(context, label);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColor.themeColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              child: const Text('Save', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: AppFont.fontFamily, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
