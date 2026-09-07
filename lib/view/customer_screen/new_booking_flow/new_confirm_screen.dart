import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';
import 'package:movigo/Controller/check_booking_status_controller.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/helper/contacts_permission_helper.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/utilities/phone_number_formatter.dart';
import 'package:movigo/view/customer_screen/create_booking_screen/booking_detail_screen.dart';
import 'package:movigo/view/customer_screen/create_booking_screen/finding_driver_screen.dart';
import 'package:movigo/view/customer_screen/onboarding/login_screen.dart';
// Feature 3: Surge multiplier
import 'package:movigo/Controller/surge_controller.dart';

class NewConfirmScreen extends StatefulWidget {
  final String vehicleTypeId;
  final String subVehicleTypeId;
  final Map<String, dynamic> vehicleData;
  final Map<String, dynamic> pickupData;
  final Map<String, dynamic> dropData;
  final double rawDistanceKm;
  final int estimatedFare;
  final List<dynamic> subVehicleTypeList;
  final String bookingType; // 'Now' or 'Scheduled'
  final String pickupDate; // 'yyyy-MM-dd' or ''
  final String pickupSlot; // slot name or ''
  final String pickupContactName;
  final String pickupContactPhone;
  final String dropContactName;
  final String dropContactPhone;
  final List<Map<String, dynamic>> extraStops;

  const NewConfirmScreen({
    super.key,
    required this.vehicleTypeId,
    required this.subVehicleTypeId,
    required this.vehicleData,
    required this.pickupData,
    required this.dropData,
    required this.rawDistanceKm,
    required this.estimatedFare,
    required this.subVehicleTypeList,
    this.bookingType = 'Now',
    this.pickupDate = '',
    this.pickupSlot = '',
    this.pickupContactName = '',
    this.pickupContactPhone = '',
    this.dropContactName = '',
    this.dropContactPhone = '',
    this.extraStops = const [],
  });

  @override
  State<NewConfirmScreen> createState() => _NewConfirmScreenState();
}

class _NewConfirmScreenState extends State<NewConfirmScreen> {
  bool _isFindingDriver = false;
  String? _createdBookingId;
  Timer? _countdownTimer;
  Timer? _statusTimer;
  bool _dialogShown = false;

  String _userType = "";

  bool get _isRetailer => _userType.toLowerCase() == 'retailer';

  // ── Priority Pickup ──────────────────────────────────────────────────────
  // Hidden entirely (not just disabled) unless the backend says this
  // vehicle/zone combo is eligible — see priceEstimate's priority_pickup
  // preview, carried here via vehicleData['priorityPickup'].
  bool _isPriorityPickup = false;
  Map<String, dynamic>? get _priorityPreview {
    final pp = widget.vehicleData['priorityPickup'];
    return (pp is Map && pp['eligible'] == true) ? Map<String, dynamic>.from(pp) : null;
  }
  int get _priorityChargeAmount => (_priorityPreview?['charge_amount'] as num?)?.toInt() ?? 0;
  int get _displayedTotal => widget.estimatedFare + (_isPriorityPickup ? _priorityChargeAmount : 0);

  // ── First-Ride Discount ── widget.estimatedFare already has this baked in
  // (backend applies it before returning the estimate), so the "original"
  // pre-discount price shown struck-through is just the discounted total
  // plus the discount amount back — never recomputed client-side.
  Map<String, dynamic>? get _firstRideDiscount {
    final d = widget.vehicleData['firstRideDiscount'];
    return (d is Map && (d['amount'] as num? ?? 0) > 0) ? Map<String, dynamic>.from(d) : null;
  }
  int get _firstRideDiscountAmount => (_firstRideDiscount?['amount'] as num?)?.toInt() ?? 0;
  int get _firstRideDiscountPercent => (_firstRideDiscount?['percent'] as num?)?.toInt() ?? 0;
  int get _preDiscountTotal => _displayedTotal + _firstRideDiscountAmount;

  // Contact info editable directly on this screen (no separate wizard) —
  // seeded from what the booking flow carried forward, editable via the
  // "Edit" button beside the route card.
  late String _pickupContactName;
  late String _pickupContactPhone;
  late String _dropContactName;
  late String _dropContactPhone;

  // Backing controllers for the fillable name/phone fields — lets the
  // retailer type or paste details directly instead of only picking a
  // contact or defaulting to their own number.
  final _pickupNameCtrl = TextEditingController();
  final _dropNameCtrl = TextEditingController();
  final _pickupPhoneCtrl = TextEditingController();
  final _dropPhoneCtrl = TextEditingController();

  // Intermediate stops (multidrop) — same pattern as pickup/drop above, one
  // pair of controllers + contact strings per stop in widget.extraStops.
  final List<TextEditingController> _stopNameCtrls  = [];
  final List<TextEditingController> _stopPhoneCtrls = [];
  final List<String> _stopContactNames  = [];
  final List<String> _stopContactPhones = [];

  @override
  void initState() {
    super.initState();
    final uc = Provider.of<UserController>(context, listen: false);
    _userType = uc.getUserType;

    _pickupContactName  = widget.pickupContactName;
    _pickupContactPhone = widget.pickupContactPhone;
    _dropContactName    = widget.dropContactName;
    _dropContactPhone   = widget.dropContactPhone;

    // Safety net: default pickup contact to the retailer's own registered
    // number when a caller didn't already supply one — they're usually the
    // one at the pickup point. Drop contact is never defaulted: it's who the
    // driver hands the delivery to, so the retailer must fill it in
    // themselves (enforced in _confirmBooking below).
    if (_pickupContactName.isEmpty || _pickupContactPhone.isEmpty) {
      _pickupContactName  = uc.getUserName;
      _pickupContactPhone = _cleanPhone(uc.getUserMobile);
    }

    _pickupNameCtrl.text = _pickupContactName;
    _dropNameCtrl.text = _dropContactName;
    _pickupPhoneCtrl.text = _pickupContactPhone;
    _dropPhoneCtrl.text = _dropContactPhone;

    for (final s in widget.extraStops) {
      final name  = (s['contact_name']  ?? '').toString();
      final phone = (s['contact_phone'] ?? '').toString();
      _stopContactNames.add(name);
      _stopContactPhones.add(phone);
      _stopNameCtrls.add(TextEditingController(text: name));
      _stopPhoneCtrls.add(TextEditingController(text: phone));
    }

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _statusTimer?.cancel();
    _pickupNameCtrl.dispose();
    _dropNameCtrl.dispose();
    _pickupPhoneCtrl.dispose();
    _dropPhoneCtrl.dispose();
    for (final c in _stopNameCtrls)  c.dispose();
    for (final c in _stopPhoneCtrls) c.dispose();
    super.dispose();
  }

  // ── Payment — cash to driver only ───────────────────────────────────────

  bool _isValidPhone(String phone) =>
      phone.trim().length == 10 && double.tryParse(phone.trim()) != null;

  Future<void> _confirmBooking() async {
    // Guests can browse and price a booking without an account, but placing
    // one is an account action (billed to a business wallet). Send them to
    // log in first — App Store Guideline 5.1.1(v).
    if (AppConstant.token.isEmpty) {
      SnackBarToastMessage.showSnackBar(
          context, 'Please log in to place a booking');
      Get.to(() => const LoginScreen(userType: 'Retailer'));
      return;
    }
    if (_pickupContactName.trim().isEmpty || _dropContactName.trim().isEmpty) {
      SnackBarToastMessage.showSnackBar(
          context, 'Please add a contact name for both pickup and drop');
      return;
    }
    if (!_isValidPhone(_pickupContactPhone) || !_isValidPhone(_dropContactPhone)) {
      SnackBarToastMessage.showSnackBar(
          context, 'Please add a valid 10-digit contact number using the buttons above');
      return;
    }
    for (int i = 0; i < _stopContactNames.length; i++) {
      if (_stopContactNames[i].trim().isEmpty) {
        SnackBarToastMessage.showSnackBar(context, 'Please add a contact name for Drop ${i + 1}');
        return;
      }
      if (!_isValidPhone(_stopContactPhones[i])) {
        SnackBarToastMessage.showSnackBar(context, 'Please add a valid 10-digit contact number for Drop ${i + 1}');
        return;
      }
    }
    // Show loading immediately so the button disables on the same frame
    final api = Provider.of<PostApiProvider>(context, listen: false);
    api.setLoading(true);
    await _createBooking(paymentMode: "Cash", transactionId: "");
  }

  // ── Pickup/drop contact info — set directly via inline buttons, no wizard ──
  String _cleanPhone(String raw) {
    var phone = raw.replaceAll(RegExp(r'\D'), '');
    if (phone.length > 10) {
      if (phone.startsWith('91')) {
        phone = phone.substring(2);
      } else if (phone.startsWith('0')) {
        phone = phone.substring(1);
      }
    }
    if (phone.length > 10) phone = phone.substring(phone.length - 10);
    return phone;
  }

  // isPickup/isDrop/stopIndex identify which location's controllers+state to
  // update — exactly one of them applies. Generalized so pickup, drop, AND
  // every intermediate multidrop stop share the same "Use My Number" /
  // "Select Contact" behavior instead of only pickup/drop having it.
  void _setContactFor({bool isPickup = false, bool isDrop = false, int? stopIndex, required String name, required String phone}) {
    setState(() {
      if (isPickup) {
        _pickupContactName  = name;
        _pickupContactPhone = phone;
        _pickupNameCtrl.text = name;
        _pickupPhoneCtrl.text = phone;
      } else if (isDrop) {
        _dropContactName  = name;
        _dropContactPhone = phone;
        _dropNameCtrl.text = name;
        _dropPhoneCtrl.text = phone;
      } else if (stopIndex != null) {
        _stopContactNames[stopIndex]  = name;
        _stopContactPhones[stopIndex] = phone;
        _stopNameCtrls[stopIndex].text  = name;
        _stopPhoneCtrls[stopIndex].text = phone;
      }
    });
  }

  void _useMyNumberFor({bool isPickup = false, bool isDrop = false, int? stopIndex}) {
    final user = Provider.of<UserController>(context, listen: false);
    _setContactFor(
      isPickup: isPickup, isDrop: isDrop, stopIndex: stopIndex,
      name: user.getUserName, phone: _cleanPhone(user.getUserMobile),
    );
  }

  // Lets the retailer save the pickup or drop point right from this screen —
  // opens a prompt for the label and contact details instead of silently
  // saving under the raw address text, so it shows up properly labeled
  // (Home/Work/Office/Other) in Saved Addresses afterwards.
  Future<void> _saveLocation({required bool isPickup}) async {
    final data    = isPickup ? widget.pickupData : widget.dropData;
    final address = (data['address'] ?? '').toString();
    final lat     = data['lat'];
    final lng     = data['lng'];
    if (address.isEmpty || lat == null || lng == null) return;

    final contactName  = (isPickup ? _pickupContactName  : _dropContactName).trim();
    final contactPhone = (isPickup ? _pickupContactPhone : _dropContactPhone).trim();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SaveLocationSheet(
        address: address,
        lat: (lat as num).toDouble(),
        lng: (lng as num).toDouble(),
        initialContactName: contactName,
        initialContactPhone: contactPhone,
      ),
    );
    if (saved == true && mounted) {
      SnackBarToastMessage.showSnackBar(context, 'Location saved');
    }
  }

  Future<void> _selectContactFor({bool isPickup = false, bool isDrop = false, int? stopIndex}) async {
    try {
      final permission = await ContactsPermissionHelper.ensureContactsPermission(context);
      if (!permission) {
        if (mounted) {
          SnackBarToastMessage.showSnackBar(context, "Contacts permission was denied. Please enable in settings.");
        }
        return;
      }
      final contact = await FlutterContacts.openExternalPick();
      if (contact == null) return;
      final fullContact = await FlutterContacts.getContact(contact.id, withProperties: true);
      if (fullContact == null) return;
      final name = fullContact.displayName;
      final phone = fullContact.phones.isNotEmpty ? _cleanPhone(fullContact.phones.first.number) : '';
      if (!mounted) return;
      _setContactFor(isPickup: isPickup, isDrop: isDrop, stopIndex: stopIndex, name: name, phone: phone);
    } catch (e) {
      if (mounted) SnackBarToastMessage.showSnackBar(context, "Error picking contact: ${e.toString()}");
    }
  }

  Widget _contactActionButtons(Color accentColor, {bool isPickup = false, bool isDrop = false, int? stopIndex}) {
    return Row(children: [
      Expanded(
        child: GestureDetector(
          onTap: () => _useMyNumberFor(isPickup: isPickup, isDrop: isDrop, stopIndex: stopIndex),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppColor.themeColor.withOpacity(0.07),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColor.themeColor.withOpacity(0.2)),
            ),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.person_rounded, size: 13, color: AppColor.themeColor),
              SizedBox(width: 4),
              Flexible(
                child: Text('Use My Number',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 10, fontWeight: FontWeight.w600, color: AppColor.themeColor)),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: GestureDetector(
          onTap: () => _selectContactFor(isPickup: isPickup, isDrop: isDrop, stopIndex: stopIndex),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.07),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: accentColor.withOpacity(0.2)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.contacts_rounded, size: 13, color: accentColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text('Select Contact',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 10, fontWeight: FontWeight.w600, color: accentColor)),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  // ── Booking creation ───────────────────────────────────────────────────────

  Future<void> _createBooking({
    required String paymentMode,
    required String transactionId,
  }) async {
    if (!mounted) return;
    final api = Provider.of<PostApiProvider>(context, listen: false);
    final now = DateTime.now();
    final dateStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    // ── Multi-drop path: JSON POST directly ──────────────────────────────────
    if (widget.extraStops.isNotEmpty) {
      await _createMultiDropBooking(paymentMode: paymentMode, transactionId: transactionId);
      return;
    }

    final bool success = await api.createBookingRetailerApi(
        context,
        vehicleTypeId: widget.vehicleTypeId,
        subVehicleTypeId: widget.subVehicleTypeId,
        transactionId: transactionId,
        customerName: _pickupContactName.trim(),
        customerPhone: _pickupContactPhone.trim(),
        pickupAddress: widget.pickupData['address'] as String? ?? "",
        pickupLat: (widget.pickupData['lat'] as num).toDouble(),
        pickupLng: (widget.pickupData['lng'] as num).toDouble(),
        dropAddress: widget.dropData['address'] as String? ?? "",
        dropLat: (widget.dropData['lat'] as num).toDouble(),
        dropLng: (widget.dropData['lng'] as num).toDouble(),
        pickupDate: widget.pickupDate.isNotEmpty ? widget.pickupDate : dateStr,
        pickupShift: "Anytime",
        pickupSlot: widget.pickupSlot,
        itemCategoryId: "",
        paymentMode: paymentMode,
        bookingType: widget.bookingType,
        needHelper: false,
        requestedVehicleName: widget.vehicleData['name']?.toString() ?? '',
        vehicleCategory:
            widget.vehicleData['vehicleCategory']?.toString() ?? '',
        pricingModifier:
            widget.vehicleData['pricingModifier']?.toString() ?? '1.0',
        vehicleKey: widget.vehicleData['vehicleKey']?.toString() ?? '',
        requiredTag: widget.vehicleData['requiredTag']?.toString() ?? '',
        displayVehicleName:
            widget.vehicleData['displayVehicleName']?.toString() ??
                widget.vehicleData['name']?.toString() ??
                '',
        bookingFlow: 'retailer',
        rawDistanceKm: widget.rawDistanceKm,
        senderName: _pickupContactName.trim(),
        senderPhone: _pickupContactPhone.trim(),
        receiverName: _dropContactName,
        receiverPhone: _dropContactPhone,
        isPriorityPickup: _isPriorityPickup,
      );

    if (!mounted) return;

    if (success && api.bookingId != null && api.bookingId!.isNotEmpty) {
      _startFindingDriver(api.bookingId!);
    } else if (success) {
      // Backend reported success but did not return a usable booking id.
      // The payment (if any) has already gone through, so do NOT show a
      // generic success message that implies a confirmed booking, and do
      // NOT imply the payment failed either — tell the customer plainly.
      SnackBarToastMessage.showSnackBar(
        context,
        "Payment was successful, but we couldn't confirm your booking. "
        "Please check your bookings list or contact support.",
      );
    }
  }

  // ── Multi-drop booking (JSON POST) ───────────────────────────────────────
  Future<void> _createMultiDropBooking({
    required String paymentMode,
    required String transactionId,
  }) async {
    if (!mounted) return;
    final api = Provider.of<PostApiProvider>(context, listen: false);
    api.setLoading(true);

    try {
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';

      final allDrops = [
        ...List.generate(widget.extraStops.length, (i) => {
          'address':       widget.extraStops[i]['address'] ?? '',
          'latitude':      widget.extraStops[i]['lat'],
          'longitude':     widget.extraStops[i]['lng'],
          'contact_name':  _stopContactNames[i],
          'contact_phone': _stopContactPhones[i],
        }),
        {
          'address':       widget.dropData['address'] ?? '',
          'latitude':      widget.dropData['lat'],
          'longitude':     widget.dropData['lng'],
          'contact_name':  _dropContactName,
          'contact_phone': _dropContactPhone,
        },
      ];

      final body = <String, dynamic>{
        'booking_type':           widget.bookingType,
        'vehicleType_id':         widget.vehicleTypeId,
        'subVehicleType_id':      widget.subVehicleTypeId,
        'transaction_id':         transactionId,
        'customer_name':          _pickupContactName.trim(),
        'customer_phone':         _pickupContactPhone.trim(),
        'sender_name':            _pickupContactName.trim(),
        'sender_phone':           _pickupContactPhone.trim(),
        'pickup_address':         widget.pickupData['address'] ?? '',
        'pickup_lat':             widget.pickupData['lat'],
        'pickup_lng':             widget.pickupData['lng'],
        'drop_address':           widget.dropData['address'] ?? '',
        'drop_lat':               widget.dropData['lat'],
        'drop_lng':               widget.dropData['lng'],
        'receiver_name':          _dropContactName,
        'receiver_phone':         _dropContactPhone,
        'pickup_date':            widget.pickupDate.isNotEmpty ? widget.pickupDate : dateStr,
        'pickup_shift':           'Anytime',
        'pickup_slot':            widget.pickupSlot,
        'payment_mode':           paymentMode,
        'requested_vehicle_name': widget.vehicleData['name']?.toString() ?? '',
        'vehicle_category':       widget.vehicleData['vehicleCategory']?.toString() ?? '',
        'vehicle_key':            widget.vehicleData['vehicleKey']?.toString() ?? '',
        'required_tag':           widget.vehicleData['requiredTag']?.toString() ?? '',
        'display_vehicle_name':   widget.vehicleData['displayVehicleName']?.toString() ?? widget.vehicleData['name']?.toString() ?? '',
        'booking_flow':           'retailer',
        'raw_distance_km':        widget.rawDistanceKm,
        'is_multidrop':           true,
        'extra_drops':            allDrops,
        if (_isPriorityPickup) 'is_priority_pickup': true,
      };

      final res = await http.post(
        Uri.parse('${AppConstant.apiBaseUrl}booking/create'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${AppConstant.token}'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 20));

      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        final bookingId = (data['data'] as Map?)?['_id']?.toString();
        api.bookingId = bookingId;
        if (bookingId != null) _startFindingDriver(bookingId);
      } else {
        final msg = (data['message'] is List ? (data['message'] as List).first?.toString() : data['message']?.toString()) ?? 'Booking failed.';
        SnackBarToastMessage.showSnackBar(context, msg);
      }
    } catch (_) {
      if (mounted) SnackBarToastMessage.showSnackBar(context, 'Booking failed. Check connection.');
    } finally {
      api.setLoading(false);
    }
  }

  // ── Finding driver timer ───────────────────────────────────────────────────

  void _startFindingDriver(String bookingId) {
    Get.off(() => FindingDriverScreen(
          bookingId: bookingId,
          pickupLat: (widget.pickupData['lat'] as num).toDouble(),
          pickupLng: (widget.pickupData['lng'] as num).toDouble(),
          pickupAddress: widget.pickupData['address'] as String? ??
              'Fetching current address...',
          dropAddress: widget.dropData['address'] as String? ??
              'Fetching destination address...',
          wheelCount: widget.vehicleData['wheelCount'] as int? ?? 2,
        ));
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _showNoDriverDialog() {
    if (_dialogShown) return;
    _dialogShown = true;
    _countdownTimer?.cancel();
    _statusTimer?.cancel();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final sz = MediaQuery.of(ctx).size;
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: sz.width * 0.84,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 64,
                    width: 64,
                    decoration: const BoxDecoration(
                        color: Color(0xffFFEEEE), shape: BoxShape.circle),
                    child: const Icon(Icons.no_transfer_rounded,
                        size: 36, color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "No Driver Available",
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppColor.blackColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "No driver is available right now. Please try again in a few minutes.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 13,
                      color: AppColor.hintTextColor,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Get.offAll(() => const CustomBottomNav(
                              userType: UserType.retailer,
                              initialIndex: 0,
                            ));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColor.themeColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text(
                        "OK",
                        style: TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDriverFoundDialog() {
    if (_dialogShown) return;
    _dialogShown = true;
    _countdownTimer?.cancel();
    _statusTimer?.cancel();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final sz = MediaQuery.of(ctx).size;
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: sz.width * 0.84,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 64,
                    width: 64,
                    decoration: const BoxDecoration(
                        color: AppColor.lightGreenBackground,
                        shape: BoxShape.circle),
                    child: const Icon(Icons.check_circle_outline_rounded,
                        size: 36, color: AppColor.greenColor),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Driver Found!",
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppColor.blackColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Your driver has accepted the ride and is on the way.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 13,
                      color: AppColor.hintTextColor,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Get.offAll(() => BookingDetailScreen(
                              bookingId: _createdBookingId!,
                            ));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColor.themeColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Track Ride",
                        style: TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // React to driver acceptance via REST polling controller.
    final statusProvider = Provider.of<CheckBookingStatusController>(context);
    if (statusProvider.isDriverAccepted == true &&
        !_dialogShown &&
        _isFindingDriver) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showDriverFoundDialog();
      });
    }

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColor.themeColor, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            "Confirm Booking",
            style: const TextStyle(
              fontFamily: AppFont.fontFamily,
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: AppColor.blackColor,
            ),
          ),
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
          ),
        ),
        body: SafeArea(top: false, child: _buildConfirmPhase(size)),
        // Fixed outside the scroll view so it never scrolls off-screen on
        // shorter devices — the content above scrolls, this stays put.
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                size.width * 0.045, 10, size.width * 0.045, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Reward promotion line ──
                if ((num.tryParse(widget.vehicleData['estimatedCoins']?.toString() ?? '0') ?? 0) > 0)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF9C4), // Soft yellow background
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFF176)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🎁 ', style: TextStyle(fontSize: 16)),
                      const Text(
                        'Book now and get up to ',
                        style: TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF5D4037),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD54F),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${(num.tryParse(widget.vehicleData['estimatedCoins']?.toString() ?? '0') ?? 0).round() + 4} Coins',
                          style: const TextStyle(
                            fontFamily: AppFont.fontFamily,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF5D4037),
                          ),
                        ),
                      ),
                      const Text(
                        ' cashback!',
                        style: TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF5D4037),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildConfirmButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Phase 1: Confirm ───────────────────────────────────────────────────────

  Widget _buildConfirmPhase(Size size) {
    final vehicleName = widget.vehicleData['name'] as String? ?? 'Vehicle';
    final wc = widget.vehicleData['wheelCount'] as int? ?? 2;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
          horizontal: size.width * 0.045, vertical: size.height * 0.02),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Route summary card ───────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xffF6F7FB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColor.borderColor),
            ),
            child: Column(
              children: [
                _LocationRow(
                  dot: AppColor.greenColor,
                  label: widget.pickupData['address'] as String? ?? "Pickup",
                  nameController: _pickupNameCtrl,
                  onNameChanged: (v) => _pickupContactName = v,
                  phoneController: _pickupPhoneCtrl,
                  onPhoneChanged: (v) => _pickupContactPhone = v,
                  onSave: () => _saveLocation(isPickup: true),
                ),
                const SizedBox(height: 8),
                _contactActionButtons(AppColor.greenColor, isPickup: true),

                // ── Intermediate stops (multidrop) ─────────────────────
                ...List.generate(widget.extraStops.length, (i) {
                  final stop = widget.extraStops[i];
                  return Column(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, thickness: 1, color: AppColor.greyLightColor),
                    ),
                    _LocationRow(
                      dot: const Color(0xFFFF9A3C),
                      label: (stop['address'] ?? 'Drop ${i + 1}').toString(),
                      nameController: _stopNameCtrls[i],
                      onNameChanged: (v) => _stopContactNames[i] = v,
                      phoneController: _stopPhoneCtrls[i],
                      onPhoneChanged: (v) => _stopContactPhones[i] = v,
                    ),
                    const SizedBox(height: 8),
                    _contactActionButtons(const Color(0xFFFF9A3C), stopIndex: i),
                  ]);
                }),

                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, thickness: 1, color: AppColor.greyLightColor),
                ),
                _LocationRow(
                  dot: AppColor.redColor,
                  label: widget.dropData['address'] as String? ?? "Drop",
                  nameController: _dropNameCtrl,
                  onNameChanged: (v) => _dropContactName = v,
                  phoneController: _dropPhoneCtrl,
                  onPhoneChanged: (v) => _dropContactPhone = v,
                  onSave: () => _saveLocation(isPickup: false),
                ),
                const SizedBox(height: 8),
                _contactActionButtons(AppColor.redColor, isDrop: true),
                const Divider(height: 20, thickness: 1),
                Row(
                  children: [
                    Image.asset(
                      _vehicleImagePath(widget.vehicleData, wc),
                      width: 34,
                      height: 34,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vehicleName,
                            style: const TextStyle(
                              fontFamily: AppFont.fontFamily,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: AppColor.blackColor,
                            ),
                          ),
                          Text(
                            _capacityForWheelCount(wc),
                            style: const TextStyle(
                              fontFamily: AppFont.fontFamily,
                              fontWeight: FontWeight.w400,
                              fontSize: 11,
                              color: AppColor.hintTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (_firstRideDiscount != null)
                          Text(
                            "₹$_preDiscountTotal",
                            style: const TextStyle(
                              fontFamily: AppFont.fontFamily,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: AppColor.hintTextColor,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        Text(
                          "₹$_displayedTotal",
                          style: const TextStyle(
                            fontFamily: AppFont.fontFamily,
                            fontWeight: FontWeight.w800,
                            fontSize: 24,
                            color: AppColor.themeColor,
                          ),
                        ),
                        if (_firstRideDiscount != null)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF16A34A).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "$_firstRideDiscountPercent% OFF",
                              style: const TextStyle(
                                fontFamily: AppFont.fontFamily,
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                                color: Color(0xFF16A34A),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (_firstRideDiscount != null) ...[
            SizedBox(height: size.height * 0.01),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF16A34A).withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.celebration_rounded, color: Color(0xFF16A34A), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "First ride offer applied — you saved ₹$_firstRideDiscountAmount!",
                      style: const TextStyle(
                        fontFamily: AppFont.fontFamily,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        color: Color(0xFF166534),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_priorityPreview != null) ...[
            SizedBox(height: size.height * 0.015),
            _buildPriorityPickupCard(),
          ],

          SizedBox(height: size.height * 0.025),
          // Feature 3: Surge banner — shown when surge is active
          Consumer<SurgeController>(
            builder: (context, surgeCtrl, _) {
              if (!surgeCtrl.isSurgeActive) return const SizedBox.shrink();
              return Container(
                margin: EdgeInsets.only(bottom: size.height * 0.015),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bolt, color: Color(0xFFD97706), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '⚡ Surge Pricing Active: ${surgeCtrl.multiplier.toStringAsFixed(1)}×  —  Fare includes ${((surgeCtrl.multiplier - 1) * 100).toStringAsFixed(0)}% surge',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF92400E),
                          fontFamily: AppFont.fontFamily,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // ── Payment method — cash to driver only ──────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColor.themeColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColor.themeColor.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.payments_rounded, color: AppColor.themeColor, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "Pay Cash to Driver",
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColor.blackColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: size.height * 0.02),
        ],
      ),
    );
  }

  // ── Priority Pickup toggle + live fare breakdown ────────────────────────
  static const Color _priorityAmber = Color(0xFFF59E0B);
  static const Color _priorityGreen = Color(0xFF16A34A);
  static const Color _priorityGreenBg = Color(0xFFF0FDF4);
  static const Color _priorityGreenBorder = Color(0xFFBBF7D0);

  Widget _buildPriorityPickupCard() {
    final preview = _priorityPreview!;
    final chargeAmount = _priorityChargeAmount;
    final arrivalLimitMin = (((preview['arrival_time_limit_seconds'] as num?) ?? 600) / 60).round();
    final on = _isPriorityPickup;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: on ? _priorityGreenBg : AppColor.whiteColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: on ? _priorityGreenBorder : AppColor.greyLightColor, width: on ? 1.4 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: _priorityAmber.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text('⚡', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Get a driver within $arrivalLimitMin min',
                      style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 14, color: AppColor.blackColor),
                    ),
                    const SizedBox(height: 2),
                    if (on)
                      Row(
                        children: [
                          const Icon(Icons.access_time_filled_rounded, size: 12, color: _priorityGreen),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Driver will reach in $arrivalLimitMin min',
                              style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 11, color: _priorityGreen),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'Turn on for ₹$chargeAmount extra',
                        style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w400, fontSize: 11, color: AppColor.hintTextColor),
                      ),
                  ],
                ),
              ),
              Switch(
                value: on,
                activeColor: _priorityGreen,
                onChanged: (v) => setState(() => _isPriorityPickup = v),
              ),
            ],
          ),
          if (on) ...[
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColor.whiteColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColor.greyLightColor.withOpacity(0.5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Extra Charge', style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 11, color: AppColor.blackColor)),
                            const SizedBox(height: 4),
                            Text('+ ₹$chargeAmount', style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w800, fontSize: 16, color: AppColor.blackColor)),
                          ],
                        ),
                      ),
                    ),
                    VerticalDivider(width: 1, thickness: 1, color: AppColor.greyLightColor.withOpacity(0.5)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text('$arrivalLimitMin Min Promise', style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 11, color: AppColor.blackColor)),
                                ),
                                const Icon(Icons.shield_rounded, size: 14, color: _priorityGreen),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'No extra charge if driver takes longer than $arrivalLimitMin min',
                              style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 10, color: AppColor.hintTextColor, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_rounded, size: 16, color: _priorityGreen),
                const SizedBox(width: 6),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11.5, color: AppColor.hintTextColor, height: 1.4),
                      children: [
                        TextSpan(text: 'You pay ₹$chargeAmount extra only if the driver reaches in $arrivalLimitMin min. If late, '),
                        const TextSpan(text: 'you pay the normal fare only.', style: TextStyle(fontWeight: FontWeight.w800, color: _priorityGreen)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _fareBreakdownRow('Base Fare', widget.estimatedFare),
            const SizedBox(height: 4),
            const Divider(height: 1, thickness: 1),
            const SizedBox(height: 8),
            _fareBreakdownRow('Possible Total', _displayedTotal, bold: true),
          ],
        ],
      ),
    );
  }

  Widget _fareBreakdownRow(String label, int amount, {bool bold = false, String? sub}) {
    final labelStyle = TextStyle(
      fontFamily: AppFont.fontFamily,
      fontSize: bold ? 14 : 12.5,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: bold ? AppColor.blackColor : AppColor.fontColor,
    );
    final amountStyle = TextStyle(
      fontFamily: AppFont.fontFamily,
      fontSize: bold ? 15 : 12.5,
      fontWeight: FontWeight.w800,
      color: bold ? _priorityGreen : AppColor.blackColor,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: labelStyle),
              if (sub != null)
                Text(sub, style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 10, color: AppColor.hintTextColor)),
            ],
          ),
        ),
        Text('₹$amount', style: amountStyle),
      ],
    );
  }

  // ── Confirm button — pinned via bottomNavigationBar, not part of the
  // scrollable content, so it stays visible on shorter screens ───────────────
  Widget _buildConfirmButton() {
    return Consumer<PostApiProvider>(
      builder: (_, api, __) => SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: api.loading ? null : _confirmBooking,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColor.themeColor,
            disabledBackgroundColor: AppColor.themeColor.withOpacity(0.5),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: api.loading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
              : Text(
                  'Confirm Booking  •  ₹$_displayedTotal',
                  style: const TextStyle(
                    fontFamily: AppFont.fontFamily,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
        ),
      ),
    );
  }

  // ── Phase 2: Finding driver ────────────────────────────────────────────────

  // Prefer the exact vehicle image keyed off route_vehicle_screen.dart's
  // vehicleKey; fall back to a name match, then wheel count, so any booking
  // path that omits vehicleKey (e.g. multi-drop) still shows a real photo.
  String _vehicleImagePath(Map<String, dynamic> vehicleData, int wc) {
    const keyToImage = {
      'R_2W': AppImage.bike,
      'R_SCOOTER': AppImage.twowheel,
      'R_MINI_3W': AppImage.mini3w,
      'R_E_LOADER': AppImage.eloader,
      'R_3W': AppImage.threewheeler,
      'R_TATA_ACE': AppImage.minitruck,
    };
    final key = vehicleData['vehicleKey']?.toString() ?? '';
    if (keyToImage.containsKey(key)) return keyToImage[key]!;

    final name = (vehicleData['name']?.toString() ?? '').toLowerCase();
    if (name.contains('loader')) return AppImage.eloader;
    if (name.contains('3 wheeler') || name.contains('3w')) return AppImage.threewheeler;
    if (name.contains('tata') || name.contains('truck')) return AppImage.minitruck;
    if (name.contains('bike') || name.contains('scooter') || name.contains('2w')) {
      return AppImage.twowheel;
    }

    if (wc == 2) return AppImage.twowheel;
    if (wc == 3) return AppImage.threewheeler;
    return AppImage.minitruck;
  }

  String _capacityForWheelCount(int wc) {
    if (wc == 2) return 'Up to 20 kg';
    if (wc == 3) return 'Up to 500 kg';
    return 'Up to 1000 kg';
  }

}

class _LocationRow extends StatelessWidget {
  final Color dot;
  final String label;
  final TextEditingController nameController;
  final ValueChanged<String> onNameChanged;
  final TextEditingController phoneController;
  final ValueChanged<String> onPhoneChanged;
  final VoidCallback? onSave;

  const _LocationRow({
    required this.dot,
    required this.label,
    required this.nameController,
    required this.onNameChanged,
    required this.phoneController,
    required this.onPhoneChanged,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 16, right: 12),
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: AppColor.blackColor,
                        ),
                      ),
                    ),
                    if (onSave != null)
                      GestureDetector(
                        onTap: onSave,
                        child: Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColor.themeColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bookmark_add_outlined, size: 13, color: AppColor.themeColor),
                              SizedBox(width: 3),
                              Text('Save',
                                  style: TextStyle(
                                    fontFamily: AppFont.fontFamily,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColor.themeColor,
                                  )),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // Name and phone are editable rectangle fields — the retailer
                // can type directly or fill via "Use My Number" / "Select
                // Contact" below, which just update these controllers.
                TextField(
                  controller: nameController,
                  onChanged: onNameChanged,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(
                    fontFamily: AppFont.fontFamily,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: AppColor.blackColor,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.person_outline_rounded, size: 18, color: AppColor.hintTextColor),
                    hintText: 'Contact name',
                    hintStyle: const TextStyle(fontSize: 13, color: AppColor.hintTextColor),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColor.borderColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColor.themeColor, width: 1.4)),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneController,
                  onChanged: onPhoneChanged,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [PhoneNumberFormatter()],
                  style: const TextStyle(
                    fontFamily: AppFont.fontFamily,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: AppColor.blackColor,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    prefixIcon: const Icon(Icons.phone_outlined, size: 18, color: AppColor.hintTextColor),
                    prefixText: '+91 ',
                    prefixStyle: const TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: AppColor.blackColor,
                    ),
                    hintText: 'Contact number',
                    hintStyle: const TextStyle(fontSize: 13, color: AppColor.hintTextColor),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColor.borderColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColor.themeColor, width: 1.4)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Prompts for a label (Home/Work/Office/Other) and confirms the contact
/// name/phone before saving a pickup/drop point from the confirm-booking
/// screen — the address and coordinates are already fixed (this is the point
/// the driver will actually be sent to), so only the label and contact need
/// asking for.
class _SaveLocationSheet extends StatefulWidget {
  final String address;
  final double lat;
  final double lng;
  final String initialContactName;
  final String initialContactPhone;

  const _SaveLocationSheet({
    required this.address,
    required this.lat,
    required this.lng,
    required this.initialContactName,
    required this.initialContactPhone,
  });

  @override
  State<_SaveLocationSheet> createState() => _SaveLocationSheetState();
}

class _SaveLocationSheetState extends State<_SaveLocationSheet> {
  static const _labels = ['Home', 'Work', 'Office', 'Other'];
  static const _labelIcons = <String, IconData>{
    'Home':   Icons.home_outlined,
    'Work':   Icons.work_outline_rounded,
    'Office': Icons.corporate_fare_rounded,
    'Other':  Icons.place_outlined,
  };

  String _label = 'Other';
  late final TextEditingController _customLabelCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _customLabelCtrl = TextEditingController();
    _nameCtrl  = TextEditingController(text: widget.initialContactName);
    _phoneCtrl = TextEditingController(text: widget.initialContactPhone);
  }

  @override
  void dispose() {
    _customLabelCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String effectiveLabel =
        _label == 'Other' ? _customLabelCtrl.text.trim() : _label;
    if (effectiveLabel.isEmpty) {
      SnackBarToastMessage.showSnackBar(context, 'Please enter a label for this location');
      return;
    }

    setState(() => _saving = true);
    try {
      final res = await postJsonData(
        'user/save_address',
        {
          'label':         effectiveLabel,
          'address':       widget.address,
          'lat':           widget.lat,
          'lng':           widget.lng,
          'contact_name':  _nameCtrl.text.trim(),
          'contact_phone': _phoneCtrl.text.trim(),
        },
        context,
        headers: {'Authorization': 'Bearer ${AppConstant.token}'},
      );
      if (!mounted) return;
      if (res != null && res['success'] == true) {
        Navigator.pop(context, true);
      } else {
        setState(() => _saving = false);
        SnackBarToastMessage.showSnackBar(context, 'Could not save address');
      }
    } catch (e) {
      debugPrint('saveLocation error: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      SnackBarToastMessage.showSnackBar(context, 'Could not save address');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const Text('Save This Location',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, fontFamily: AppFont.fontFamily, color: AppColor.blackColor)),
              const SizedBox(height: 4),
              Text(widget.address,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontFamily: AppFont.fontFamily, color: AppColor.greyColor)),
              const SizedBox(height: 18),

              Text('Save as', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily, color: AppColor.blackColor)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _labels.map((l) {
                  final selected = _label == l;
                  return GestureDetector(
                    onTap: () => setState(() => _label = l),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? AppColor.themeColor.withOpacity(0.1) : Colors.white,
                        border: Border.all(color: selected ? AppColor.themeColor : const Color(0xffDEE2E6), width: selected ? 1.5 : 1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_labelIcons[l], size: 16, color: selected ? AppColor.themeColor : AppColor.greyColor),
                          const SizedBox(width: 6),
                          Text(l, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily, color: selected ? AppColor.themeColor : AppColor.blackColor)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              if (_label == 'Other') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _customLabelCtrl,
                  style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13.5, color: AppColor.blackColor),
                  decoration: InputDecoration(
                    hintText: 'Label (e.g. Warehouse, Client Office)',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],

              const SizedBox(height: 18),
              Text('Contact for this location', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily, color: AppColor.blackColor)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13.5, color: AppColor.blackColor),
                decoration: InputDecoration(
                  hintText: 'Contact name',
                  prefixIcon: const Icon(Icons.person_outline_rounded, size: 18, color: AppColor.hintTextColor),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13.5, color: AppColor.blackColor),
                decoration: InputDecoration(
                  hintText: 'Contact phone',
                  prefixIcon: const Icon(Icons.phone_outlined, size: 18, color: AppColor.hintTextColor),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),

              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColor.themeColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Save Location', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: AppFont.fontFamily, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
