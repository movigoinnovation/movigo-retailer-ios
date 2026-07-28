import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/helper/contacts_permission_helper.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/utilities/phone_number_formatter.dart';
import 'multi_drop_vehicle_screen.dart';

// ── Data model ────────────────────────────────────────────────────────────────
class MultiDropEntry {
  String address;
  LatLng? latLng;
  String contactName;
  String contactPhone;

  MultiDropEntry({
    this.address = '',
    this.latLng,
    this.contactName = '',
    this.contactPhone = '',
  });
}

class MultiDropLocationScreen extends StatefulWidget {
  const MultiDropLocationScreen({super.key});

  @override
  State<MultiDropLocationScreen> createState() => _MultiDropLocationScreenState();
}

class _MultiDropLocationScreenState extends State<MultiDropLocationScreen> {
  // ── Pickup ──────────────────────────────────────────────────────────────────
  final _pickupCtrl  = TextEditingController();
  final _pickupFocus = FocusNode();
  LatLng? _pickupLatLng;
  String  _pickupAddress = '';

  // ── Drops ───────────────────────────────────────────────────────────────────
  final List<MultiDropEntry>             _drops       = [MultiDropEntry(), MultiDropEntry()];
  final List<TextEditingController>      _dropAddrCtrls  = [TextEditingController(), TextEditingController()];
  final List<TextEditingController>      _dropNameCtrls  = [TextEditingController(), TextEditingController()];
  final List<TextEditingController>      _dropPhoneCtrls = [TextEditingController(), TextEditingController()];
  final List<FocusNode>                  _dropFocuses    = [FocusNode(), FocusNode()];

  // ── Autocomplete ─────────────────────────────────────────────────────────
  String _activeSearch = '';   // 'pickup' | 'drop_N'
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoadingSuggestions  = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Prefill pickup from user's current location
    final user = Provider.of<UserController>(context, listen: false);
    if (user.getlatitude != 0.0 && user.getAddress.isNotEmpty) {
      _pickupLatLng    = LatLng(user.getlatitude, user.getlongitude);
      _pickupAddress   = user.getAddress;
      _pickupCtrl.text = user.getAddress;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pickupCtrl.dispose(); _pickupFocus.dispose();
    for (final c in _dropAddrCtrls)  c.dispose();
    for (final c in _dropNameCtrls)  c.dispose();
    for (final c in _dropPhoneCtrls) c.dispose();
    for (final f in _dropFocuses)    f.dispose();
    super.dispose();
  }

  // ── Autocomplete ────────────────────────────────────────────────────────────
  void _onSearchChanged(String query, String field) {
    _debounce?.cancel();
    setState(() {
      _activeSearch = field;
      if (field == 'pickup') { _pickupLatLng = null; _pickupAddress = ''; }
      else {
        final i = int.parse(field.split('_')[1]);
        _drops[i].latLng  = null; _drops[i].address = '';
      }
    });
    if (query.trim().isEmpty) { setState(() => _suggestions = []); return; }
    _debounce = Timer(const Duration(milliseconds: 300), () => _fetchSuggestions(query.trim()));
  }

  Future<void> _fetchSuggestions(String input) async {
    setState(() => _isLoadingSuggestions = true);
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(input)}&location=22.7196,75.8577&radius=50000&components=country:in&key=${AppConstant.googleApiKey}',
      );
      final res  = await http.get(url);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final preds = data['predictions'] as List? ?? [];
      setState(() {
        _suggestions = preds.map<Map<String, dynamic>>((p) => {
          'place_id':       p['place_id'],
          'main_text':      (p['structured_formatting']?['main_text'])      ?? '',
          'secondary_text': (p['structured_formatting']?['secondary_text']) ?? '',
          'description':    p['description'],
        }).toList();
      });
    } catch (_) {
      if (mounted) setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _isLoadingSuggestions = false);
    }
  }

  Future<void> _selectSuggestion(Map<String, dynamic> s) async {
    FocusScope.of(context).unfocus();
    final text = s['description'] ?? s['main_text'] ?? '';
    setState(() {
      _suggestions = [];
      if (_activeSearch == 'pickup') _pickupCtrl.text = text;
      else {
        final i = int.parse(_activeSearch.split('_')[1]);
        _dropAddrCtrls[i].text = text;
      }
    });
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=${s['place_id']}&fields=geometry,formatted_address&key=${AppConstant.googleApiKey}',
      );
      final res  = await http.get(url);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final loc  = data['result']?['geometry']?['location'];
      final fmt  = data['result']?['formatted_address']?.toString() ?? text;
      if (loc != null && mounted) {
        final ll = LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
        setState(() {
          if (_activeSearch == 'pickup') {
            _pickupLatLng = ll; _pickupAddress = fmt; _pickupCtrl.text = fmt;
          } else {
            final i = int.parse(_activeSearch.split('_')[1]);
            _drops[i].latLng = ll; _drops[i].address = fmt; _dropAddrCtrls[i].text = fmt;
          }
        });
      }
    } catch (_) {}
  }

  // ── Contact picker ──────────────────────────────────────────────────────────
  Future<void> _pickContact(int dropIndex) async {
    try {
      final granted = await ContactsPermissionHelper.ensureContactsPermission(context);
      if (!granted) return;
      final contact = await FlutterContacts.openExternalPick();
      if (contact == null) return;
      final full = await FlutterContacts.getContact(contact.id, withProperties: true);
      if (full == null || !mounted) return;
      String phone = '';
      if (full.phones.isNotEmpty) {
        phone = full.phones.first.number.replaceAll(RegExp(r'\D'), '');
        if (phone.length > 10) {
          if (phone.startsWith('91')) phone = phone.substring(2);
          else if (phone.startsWith('0')) phone = phone.substring(1);
        }
        if (phone.length > 10) phone = phone.substring(phone.length - 10);
      }
      setState(() {
        _dropNameCtrls[dropIndex].text  = full.displayName;
        _dropPhoneCtrls[dropIndex].text = phone;
        _drops[dropIndex].contactName  = full.displayName;
        _drops[dropIndex].contactPhone = phone;
      });
    } catch (_) {}
  }

  // ── Add / remove drop ───────────────────────────────────────────────────────
  void _addDrop() {
    if (_drops.length >= 5) {
      SnackBarToastMessage.showSnackBar(context, 'Maximum 5 drop locations allowed.');
      return;
    }
    setState(() {
      _drops.add(MultiDropEntry());
      _dropAddrCtrls.add(TextEditingController());
      _dropNameCtrls.add(TextEditingController());
      _dropPhoneCtrls.add(TextEditingController());
      _dropFocuses.add(FocusNode());
    });
  }

  void _removeDrop(int i) {
    if (_drops.length <= 2) return;
    setState(() {
      _drops.removeAt(i);
      _dropAddrCtrls[i].dispose(); _dropAddrCtrls.removeAt(i);
      _dropNameCtrls[i].dispose(); _dropNameCtrls.removeAt(i);
      _dropPhoneCtrls[i].dispose(); _dropPhoneCtrls.removeAt(i);
      _dropFocuses[i].dispose();   _dropFocuses.removeAt(i);
      // Reset active search if it was for this drop
      if (_activeSearch == 'drop_$i') {
        _activeSearch = ''; _suggestions = [];
      }
    });
  }

  // ── Proceed ─────────────────────────────────────────────────────────────────
  void _proceed() {
    if (_pickupLatLng == null) {
      SnackBarToastMessage.showSnackBar(context, 'Please select a pickup address from suggestions.');
      return;
    }
    for (int i = 0; i < _drops.length; i++) {
      if (_drops[i].latLng == null) {
        SnackBarToastMessage.showSnackBar(context, 'Please select Drop ${i + 1} address from suggestions.');
        return;
      }
    }
    // Sync contact fields
    for (int i = 0; i < _drops.length; i++) {
      _drops[i].contactName  = _dropNameCtrls[i].text.trim();
      _drops[i].contactPhone = _dropPhoneCtrls[i].text.trim();
    }

    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MultiDropVehicleScreen(
        pickupLatLng:   _pickupLatLng!,
        pickupAddress:  _pickupAddress.isNotEmpty ? _pickupAddress : _pickupCtrl.text.trim(),
        drops:          List.from(_drops),
      ),
    ));
  }

  // ── BUILD ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    const navy   = Color(0xFF1A3A6B);
    const navyDk = Color(0xFF0D2137);
    const bg     = Color(0xFFF4F6FA);
    const muted  = Color(0xFF8A94A6);
    const border = Color(0xFFE8ECF2);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        shadowColor: Colors.black.withOpacity(0.08),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A3A6B), size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Multi-Drop Booking',
              style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 15, fontWeight: FontWeight.w800, color: navyDk)),
          Text('1 Pickup · ${_drops.length} Drops',
              style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11, color: muted)),
        ]),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Pickup ──────────────────────────────────────────────────
                  _sectionHeader(Icons.my_location_rounded, 'PICKUP', const Color(0xFF1A3A6B)),
                  const SizedBox(height: 8),
                  _addrField(
                    ctrl: _pickupCtrl, focus: _pickupFocus, field: 'pickup',
                    hint: 'Search pickup address...', icon: Icons.my_location_rounded,
                    color: const Color(0xFF1A3A6B), confirmed: _pickupLatLng != null,
                  ),
                  if (_suggestions.isNotEmpty && _activeSearch == 'pickup') ...[
                    const SizedBox(height: 6), _suggestionsBox(),
                  ],
                  const SizedBox(height: 20),

                  // Route line visual
                  _routeDivider(),
                  const SizedBox(height: 20),

                  // ── Drops ───────────────────────────────────────────────────
                  ...List.generate(_drops.length, (i) => _dropSection(i)),

                  // ── Add drop button ─────────────────────────────────────────
                  if (_drops.length < 5) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: _addDrop,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFF1A3A6B).withOpacity(0.25),
                            width: 1.5,
                          ),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Container(padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: const Color(0xFF1A3A6B).withOpacity(0.10), shape: BoxShape.circle),
                            child: const Icon(Icons.add_rounded, color: Color(0xFF1A3A6B), size: 14)),
                          const SizedBox(width: 8),
                          const Text('Add Another Drop', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13,
                              fontWeight: FontWeight.w700, color: Color(0xFF1A3A6B))),
                        ]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // ── Proceed button ──────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: const Color(0xFF1A3A6B).withOpacity(0.10), blurRadius: 12, offset: const Offset(0, -4))],
            ),
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
            child: SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _proceed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A3A6B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.route_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Choose Vehicle  ›', style: TextStyle(
                      fontFamily: AppFont.fontFamily, fontSize: 15,
                      fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String label, Color color) => Row(children: [
    Container(padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(7)),
      child: Icon(icon, color: color, size: 13)),
    const SizedBox(width: 8),
    Text(label, style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 10, fontWeight: FontWeight.w800,
        color: color, letterSpacing: 1)),
  ]);

  Widget _routeDivider() => Row(children: [
    const SizedBox(width: 14),
    Column(children: List.generate(5, (_) => Container(
      width: 2, height: 5, margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(color: const Color(0xFF1A3A6B).withOpacity(0.25), borderRadius: BorderRadius.circular(1)),
    ))),
    const SizedBox(width: 10),
    Text('Route: Pickup → ${_drops.length} Drop${_drops.length > 1 ? 's' : ''}',
        style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11, color: Color(0xFF8A94A6))),
  ]);

  Widget _dropSection(int i) {
    final dropColor   = _dropColors[i % _dropColors.length];
    final confirmed   = _drops[i].latLng != null;
    final field       = 'drop_$i';
    final isLastDrop  = i == _drops.length - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: _sectionHeader(Icons.location_on_rounded, 'DROP ${i + 1}', dropColor)),
          if (_drops.length > 2)
            GestureDetector(
              onTap: () => _removeDrop(i),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFE53935).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6)),
                child: const Icon(Icons.close_rounded, color: Color(0xFFE53935), size: 14)),
            ),
        ]),
        const SizedBox(height: 8),
        _addrField(ctrl: _dropAddrCtrls[i], focus: _dropFocuses[i], field: field,
            hint: 'Search drop ${i + 1} address...', icon: Icons.location_on_rounded,
            color: dropColor, confirmed: confirmed),
        if (_suggestions.isNotEmpty && _activeSearch == field) ...[
          const SizedBox(height: 6), _suggestionsBox(),
        ],
        const SizedBox(height: 10),
        // Contact row
        Row(children: [
          Expanded(child: _inputBox(ctrl: _dropNameCtrls[i], hint: 'Contact name')),
          const SizedBox(width: 8),
          Expanded(child: _inputBox(ctrl: _dropPhoneCtrls[i], hint: 'Phone', keyboard: TextInputType.phone, maxLen: 10)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _pickContact(i),
            child: Container(padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(color: dropColor.withOpacity(0.15), borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: dropColor.withOpacity(0.3))),
              child: Icon(Icons.contacts_rounded, color: dropColor.withOpacity(0.85), size: 18)),
          ),
        ]),
        SizedBox(height: isLastDrop ? 8 : 18),
        if (!isLastDrop)
          Padding(padding: const EdgeInsets.only(left: 14),
            child: Row(children: [
              Column(children: List.generate(4, (_) => Container(
                width: 2, height: 4, margin: const EdgeInsets.only(bottom: 3),
                decoration: BoxDecoration(color: const Color(0xFFE8ECF2), borderRadius: BorderRadius.circular(1)),
              ))),
            ]),
          ),
      ],
    );
  }

  static const _dropColors = [
    Color(0xFFFF6B6B), Color(0xFFFF9A3C), Color(0xFF43E97B),
    Color(0xFF00BFA5), Color(0xFFFFD93D),
  ];

  Widget _addrField({
    required TextEditingController ctrl, required FocusNode focus,
    required String field, required String hint, required IconData icon,
    required Color color, required bool confirmed,
  }) {
    final isActive = _activeSearch == field && _suggestions.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: confirmed ? const Color(0xFF0891B2)
              : (isActive ? color.withOpacity(0.6) : const Color(0xFFE8ECF2)),
          width: confirmed || isActive ? 1.5 : 1,
        ),
      ),
      child: TextField(
        controller: ctrl, focusNode: focus,
        style: const TextStyle(color: Color(0xFF0D2137), fontSize: 13, fontFamily: AppFont.fontFamily),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF8A94A6), fontFamily: AppFont.fontFamily, fontSize: 13),
          prefixIcon: Icon(icon, color: confirmed ? const Color(0xFF0891B2) : color, size: 17),
          suffixIcon: confirmed
              ? const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.check_circle_rounded, color: Color(0xFF0891B2), size: 16))
              : (_isLoadingSuggestions && _activeSearch == field
                  ? Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: color.withOpacity(0.6))))
                  : (ctrl.text.isNotEmpty ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Color(0xFF8A94A6), size: 15),
                      onPressed: () { ctrl.clear(); setState(() {
                        _suggestions = [];
                        if (field == 'pickup') { _pickupLatLng = null; _pickupAddress = ''; }
                        else { final i = int.parse(field.split('_')[1]); _drops[i].latLng = null; _drops[i].address = ''; }
                      }); }) : null)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        ),
        onTap: () => setState(() => _activeSearch = field),
        onChanged: (q) => _onSearchChanged(q, field),
      ),
    );
  }

  Widget _inputBox({required TextEditingController ctrl, required String hint,
      TextInputType? keyboard, int? maxLen}) =>
    Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8ECF2))),
      child: TextField(
        controller: ctrl, keyboardType: keyboard, maxLength: maxLen,
        inputFormatters: keyboard == TextInputType.phone ? [PhoneNumberFormatter()] : null,
        style: const TextStyle(color: Color(0xFF0D2137), fontSize: 12, fontFamily: AppFont.fontFamily),
        decoration: InputDecoration(
          hintText: hint, counterText: '',
          hintStyle: const TextStyle(color: Color(0xFF8A94A6), fontFamily: AppFont.fontFamily, fontSize: 12),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );

  Widget _suggestionsBox() => Container(
    constraints: const BoxConstraints(maxHeight: 160),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE8ECF2)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 4))],
    ),
    child: ListView.builder(
      shrinkWrap: true, padding: EdgeInsets.zero, itemCount: _suggestions.length,
      itemBuilder: (_, i) {
        final s = _suggestions[i];
        return InkWell(
          onTap: () => _selectSuggestion(s),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              const Icon(Icons.location_on_outlined, color: Color(0xFF1A3A6B), size: 14),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s['main_text'] ?? '', style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0D2137)), overflow: TextOverflow.ellipsis),
                if ((s['secondary_text'] ?? '').toString().isNotEmpty)
                  Text(s['secondary_text'], style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 10.5, color: Color(0xFF8A94A6)), overflow: TextOverflow.ellipsis),
              ])),
            ]),
          ),
        );
      },
    ),
  );
}
