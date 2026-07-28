import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movigo/utilities/phone_number_formatter.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/helper/contacts_permission_helper.dart';
import 'package:movigo/Controller/check_booking_status_controller.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movigo/view/customer_screen/create_booking_screen/booking_detail_screen.dart';
import 'package:movigo/view/customer_screen/create_booking_screen/cancel_ride_screen.dart';
import 'package:movigo/view/customer_screen/create_booking_screen/finding_driver_screen.dart';
import 'package:movigo/view/customer_screen/new_booking_flow/route_vehicle_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RetailerConfirmScreen  — Version 1
// Shown after RouteVehicleScreen for retailer users.
// Collects: receiver name/phone, goods type, schedule, payment method.
// ─────────────────────────────────────────────────────────────────────────────

class RetailerConfirmScreen extends StatefulWidget {
  final String vehicleTypeId;
  final String subVehicleTypeId;
  final Map<String, dynamic> vehicleData;
  final Map<String, dynamic> pickupData;
  final Map<String, dynamic> dropData;
  final double rawDistanceKm;
  final int estimatedFare;
  final List<dynamic> subVehicleTypeList;

  // Optional pre-fill values for Book Again flow
  final String? initialReceiverName;
  final String? initialReceiverPhone;
  final String? initialSenderName;
  final String? initialSenderPhone;
  final String? initialNote;
  final int? initialPaymentMode;
  final String? initialGoodsTypeId;

  const RetailerConfirmScreen({
    super.key,
    required this.vehicleTypeId,
    required this.subVehicleTypeId,
    required this.vehicleData,
    required this.pickupData,
    required this.dropData,
    required this.rawDistanceKm,
    required this.estimatedFare,
    required this.subVehicleTypeList,
    this.initialReceiverName,
    this.initialReceiverPhone,
    this.initialSenderName,
    this.initialSenderPhone,
    this.initialNote,
    this.initialPaymentMode,
    this.initialGoodsTypeId,
  });

  @override
  State<RetailerConfirmScreen> createState() => _RetailerConfirmScreenState();
}

class _RetailerConfirmScreenState extends State<RetailerConfirmScreen> {
  // ── Mutable vehicle state (can be changed via "Change Vehicle") ───────────
  String _vehicleTypeId    = '';
  String _subVehicleTypeId = '';
  Map<String, dynamic> _vehicleData = const {};
  double _rawDistanceKm    = 0;
  int    _estimatedFare    = 0;

  // ── Form controllers ───────────────────────────────────────────────────────
  final _receiverNameCtrl = TextEditingController();
  final _receiverPhoneCtrl = TextEditingController();
  // ── Sender details (the person placing the booking / origin contact) ──────
  final _senderNameCtrl  = TextEditingController();
  final _senderPhoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _useOwnPhone = false;

  // ── Contacts picker ────────────────────────────────────────────────────────
  /// Opens the native contacts picker and fills [nameCtrl] + [phoneCtrl].
  Future<void> _pickContact({
    required TextEditingController nameCtrl,
    required TextEditingController phoneCtrl,
  }) async {
    // Request contacts permission
    if (!await ContactsPermissionHelper.ensureContactsPermission(context)) {
      if (mounted) {
        SnackBarToastMessage.showSnackBar(
            context, 'Contacts permission denied. Please enable in Settings.');
      }
      return;
    }
    try {
      final Contact? contact = await FlutterContacts.openExternalPick();
      if (contact == null) return;
      // Re-fetch with properties to get phone numbers
      final full = await FlutterContacts.getContact(contact.id, withProperties: true);
      if (full == null) return;

      final String name = full.displayName.trim();
      String phone = '';
      if (full.phones.isNotEmpty) {
        phone = full.phones.first.normalizedNumber.replaceAll(RegExp(r'\D'), '');
        // Strip country code +91 for India
        if (phone.startsWith('91') && phone.length == 12) {
          phone = phone.substring(2);
        }
        // Keep last 10 digits
        if (phone.length > 10) phone = phone.substring(phone.length - 10);
      }
      if (mounted) {
        setState(() {
          nameCtrl.text  = name;
          phoneCtrl.text = phone;
        });
      }
    } catch (e) {
      if (mounted) {
        SnackBarToastMessage.showSnackBar(context, 'Could not open contacts.');
      }
    }
  }

  // ── Goods type — fetched from backend (real ObjectIds) ─────────────────────
  List<Map<String, dynamic>> _goodsTypes = [];
  bool _loadingCategories = true;
  String? _selectedGoodsTypeId;   // stores the real MongoDB _id
  String? _selectedGoodsTypeName; // for display only

  // ── Schedule ───────────────────────────────────────────────────────────────
  // 0 = Book Now, 1 = Schedule Later
  int _scheduleMode = 0;
  DateTime _selectedDate = DateTime.now();
  String _selectedShift = 'Morning';
  String _selectedSlot = '09:00 AM - 11:00 AM';

  static const List<String> _shifts = ['Morning', 'Afternoon', 'Evening'];
  static const Map<String, List<String>> _slotsByShift = {
    'Morning':   ['07:00 AM - 09:00 AM', '09:00 AM - 11:00 AM', '11:00 AM - 01:00 PM'],
    'Afternoon': ['01:00 PM - 03:00 PM', '03:00 PM - 05:00 PM'],
    'Evening':   ['05:00 PM - 07:00 PM', '07:00 PM - 09:00 PM'],
  };

  // ── Payment ────────────────────────────────────────────────────────────────
  // 0 = Pay at Pickup, 1 = Pay at Drop, 2 = Online
  int _paymentMode = 0;

  // Prevents double-tap while booking is being submitted
  bool _isBooking = false;

  // ── Finding driver state ───────────────────────────────────────────────────
  bool _isFindingDriver = false;
  String? _createdBookingId;
  int _remainingSeconds = 300;
  Timer? _countdownTimer;
  Timer? _statusTimer;
  bool _dialogShown = false;

  int _currentVehicleIndex = 0;
  final List<String> _findingVehicles = [
    AppImage.twowheel,
    AppImage.eloader,
    AppImage.threewheeler,
    AppImage.minitruck,
    AppImage.largetruck,
  ];

  late Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    _vehicleTypeId    = widget.vehicleTypeId;
    _subVehicleTypeId = widget.subVehicleTypeId;
    _vehicleData      = Map<String, dynamic>.from(widget.vehicleData);
    _rawDistanceKm    = widget.rawDistanceKm;
    _estimatedFare    = widget.estimatedFare;
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});

    // Apply Book Again pre-fills before the UI is first rendered.
    if (widget.initialReceiverName != null && widget.initialReceiverName!.isNotEmpty) {
      _receiverNameCtrl.text = widget.initialReceiverName!;
    }
    if (widget.initialReceiverPhone != null && widget.initialReceiverPhone!.isNotEmpty) {
      _receiverPhoneCtrl.text = widget.initialReceiverPhone!;
    }
    if (widget.initialSenderName != null && widget.initialSenderName!.isNotEmpty) {
      _senderNameCtrl.text = widget.initialSenderName!;
    }
    if (widget.initialSenderPhone != null && widget.initialSenderPhone!.isNotEmpty) {
      _senderPhoneCtrl.text = widget.initialSenderPhone!;
    }
    if (widget.initialNote != null && widget.initialNote!.isNotEmpty) {
      _noteCtrl.text = widget.initialNote!;
    }
    if (widget.initialPaymentMode != null) {
      _paymentMode = widget.initialPaymentMode!;
    }
    if (widget.initialGoodsTypeId != null && widget.initialGoodsTypeId!.isNotEmpty) {
      _selectedGoodsTypeId = widget.initialGoodsTypeId;
    }

    _fetchCategories();
    // Pre-fill sender fields with the retailer's own registered info so the
    // driver always has a visible, editable pickup contact (not a hidden default).
    // Only applies when no Book Again pre-fill was provided.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final uc = Provider.of<UserController>(context, listen: false);
      if (_senderPhoneCtrl.text.isEmpty) {
        _senderPhoneCtrl.text = uc.getUserMobile;
      }
      if (_senderNameCtrl.text.isEmpty) {
        _senderNameCtrl.text = uc.getUserName;
      }
    });
  }

  // Fetch real ItemCategory list from backend so we send a valid MongoDB ObjectId
  Future<void> _fetchCategories() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstant.apiBaseUrl}user/get_category_list'),
        headers: {
          'Authorization': 'Bearer ${AppConstant.token}',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data['data'] as List?) ?? [];
        if (mounted) {
          setState(() {
            _goodsTypes = list.map<Map<String, dynamic>>((c) => {
              'id': c['_id']?.toString() ?? '',
              'name': c['name']?.toString() ?? '',
            }).toList();
            _loadingCategories = false;
          });
        }
      } else {
        if (mounted) setState(() => _loadingCategories = false);
      }
    } catch (e) {
      debugPrint('❌ Category fetch error: $e');
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _statusTimer?.cancel();
    _receiverNameCtrl.dispose();
    _receiverPhoneCtrl.dispose();
    _senderNameCtrl.dispose();
    _senderPhoneCtrl.dispose();
    _noteCtrl.dispose();
    _razorpay.clear();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _formatTime(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  String _formattedDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _displayDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColor.themeColor,
              onPrimary: Colors.white,
              onSurface: AppColor.blackColor,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  IconData _iconForWheelCount(int wc) {
    if (wc == 2) return Icons.two_wheeler;
    if (wc == 3) return Icons.electric_rickshaw;
    return Icons.local_shipping;
  }

  String _capacityForWheelCount(int wc) {
    if (wc == 2) return 'Up to 20 kg';
    if (wc == 3) return 'Up to 500 kg';
    return 'Up to 1000 kg';
  }

  // ── Validation ─────────────────────────────────────────────────────────────

  bool _validate() {
    final receiverPhone = _receiverPhoneCtrl.text.trim();
    if (receiverPhone.isEmpty) {
      SnackBarToastMessage.showSnackBar(
          context, 'Receiver phone number is required.\nप्राप्तकर्ता का फ़ोन नंबर आवश्यक है।');
      return false;
    }
    if (receiverPhone.length != 10) {
      SnackBarToastMessage.showSnackBar(context, 'Please enter a valid 10-digit receiver phone.');
      return false;
    }
    if (_selectedGoodsTypeId == null || _selectedGoodsTypeId!.isEmpty) {
      SnackBarToastMessage.showSnackBar(context, 'Please select goods type.');
      return false;
    }
    return true;
  }

  // ── Same-number warning ────────────────────────────────────────────────────

  Future<bool> _showSameNumberWarning() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Same number for sender & receiver',
          style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 16),
        ),
        content: const Text(
          'Sender and receiver have the same phone number. Is that correct?\n\nभेजने वाले और प्राप्तकर्ता का नंबर एक ही है — क्या यह सही है?',
          style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go Back', style: TextStyle(fontFamily: AppFont.fontFamily, color: AppColor.hintTextColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Proceed', style: TextStyle(fontFamily: AppFont.fontFamily, color: AppColor.themeColor, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  // ── Payment ────────────────────────────────────────────────────────────────

  Future<void> _confirmBooking() async {
    if (_isBooking) return;
    if (!_validate()) return;
    setState(() => _isBooking = true);
    try {
      final sPhone = _senderPhoneCtrl.text.trim();
      final rPhone = _receiverPhoneCtrl.text.trim();
      if (sPhone.isNotEmpty && sPhone == rPhone) {
        final proceed = await _showSameNumberWarning();
        if (!mounted || !proceed) {
          setState(() => _isBooking = false);
          return;
        }
      }
      if (_paymentMode == 2) {
        _openRazorpay();
        // Razorpay opens its own UI; reset flag so user can re-tap if they close it
        if (mounted) setState(() => _isBooking = false);
      } else {
        await _createBooking(paymentMode: 'Cash', transactionId: '');
      }
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  Future<void> _openRazorpay() async {
    final uc = Provider.of<UserController>(context, listen: false);
    final api = Provider.of<PostApiProvider>(context, listen: false);
    try {
      final orderRes = await api.createBookingPaymentOrder(
        context,
        baseFare: _estimatedFare,
      );
      if (orderRes == null) return;
      if (!mounted) return;

      final razorpayKey = AppConstant.razorpayKeyFromOrder(orderRes);
      if (razorpayKey.isEmpty) {
        SnackBarToastMessage.showSnackBar(context, 'Payment key missing. Please try again later.');
        return;
      }

      _razorpay.open({
        'key': razorpayKey,
        'amount': orderRes['amount_paise'] ?? (_estimatedFare * 100),
        'order_id': orderRes['order_id'] ?? '',
        'name': 'Movigo',
        'description': 'Retailer Booking',
        'prefill': {
          'contact': uc.getUserMobile,
          'email': uc.getUserEmail.isNotEmpty ? uc.getUserEmail : 'user@movigo.com',
        },
        'theme': {'color': '#0A3D91'},
      });
    } catch (_) {
      SnackBarToastMessage.showSnackBar(context, 'Could not open payment. Try again.');
    }
  }

  void _onPaymentSuccess(PaymentSuccessResponse res) =>
      _createBooking(paymentMode: 'Online', transactionId: res.paymentId ?? '');

  void _onPaymentError(PaymentFailureResponse _) {
    if (mounted) SnackBarToastMessage.showSnackBar(context, 'Payment failed. Please try again.');
  }

  // ── Booking creation ───────────────────────────────────────────────────────

  Future<void> _createBooking({
    required String paymentMode,
    required String transactionId,
  }) async {
    if (!mounted) return;
    final api = Provider.of<PostApiProvider>(context, listen: false);

    final bookingDate = _scheduleMode == 0
        ? _formattedDate(DateTime.now())
        : _formattedDate(_selectedDate);

    final bookingType = _scheduleMode == 0 ? 'Now' : 'Later';
    final shift = _scheduleMode == 0 ? 'Anytime' : _selectedShift;
    final slot  = _scheduleMode == 0 ? 'Now' : _selectedSlot;

    final success = await api.createBookingRetailerApi(
      context,
      vehicleTypeId: _vehicleTypeId,
      subVehicleTypeId: _subVehicleTypeId,
      transactionId: transactionId,
      customerName: _senderNameCtrl.text.trim(),
      customerPhone: _senderPhoneCtrl.text.trim(),
      senderName: _senderNameCtrl.text.trim(),
      senderPhone: _senderPhoneCtrl.text.trim(),
      receiverName: _receiverNameCtrl.text.trim(),
      receiverPhone: _receiverPhoneCtrl.text.trim(),
      pickupAddress: widget.pickupData['address'] as String? ?? '',
      pickupLat: (widget.pickupData['lat'] as num).toDouble(),
      pickupLng: (widget.pickupData['lng'] as num).toDouble(),
      dropAddress: widget.dropData['address'] as String? ?? '',
      dropLat: (widget.dropData['lat'] as num).toDouble(),
      dropLng: (widget.dropData['lng'] as num).toDouble(),
      pickupDate: bookingDate,
      pickupShift: shift,
      pickupSlot: slot,
      itemCategoryId: _selectedGoodsTypeId ?? '',   // real MongoDB ObjectId from API
      paymentMode: paymentMode,
      bookingType: bookingType,
      note: _noteCtrl.text.trim(),
      requestedVehicleName: _vehicleData['name']?.toString() ?? '',
      vehicleCategory: _vehicleData['vehicleCategory']?.toString() ?? '',
      pricingModifier: _vehicleData['pricingModifier']?.toString() ?? '1.0',
      vehicleKey: _vehicleData['vehicleKey']?.toString() ?? '',
      requiredTag: _vehicleData['requiredTag']?.toString() ?? _vehicleData['required_tag']?.toString() ?? '',
      bookingFlow: _vehicleData['bookingFlow']?.toString() ?? _vehicleData['booking_flow']?.toString() ?? 'retailer',
      displayVehicleName: _vehicleData['displayVehicleName']?.toString() ?? _vehicleData['display_vehicle_name']?.toString() ?? '',
      rawDistanceKm: _rawDistanceKm,
    );

    if (!mounted) return;
    if (success && api.bookingId != null) {
      _startFindingDriver(api.bookingId!);
    }
  }

  // ── Finding driver ─────────────────────────────────────────────────────────

  void _startFindingDriver(String bookingId) {
    // Persist active booking so the app can resume here after OEM kill/restart.
    SharedPreferences.getInstance().then((p) {
      p.setString('retailer_active_booking_id', bookingId);
    });
    Get.off(() => FindingDriverScreen(
      bookingId: bookingId,
      pickupLat: (widget.pickupData['lat'] as num).toDouble(),
      pickupLng: (widget.pickupData['lng'] as num).toDouble(),
      pickupAddress: widget.pickupData['address'] as String? ?? 'Fetching current address...',
      dropAddress: widget.dropData['address'] as String? ?? 'Fetching destination address...',
      wheelCount: _vehicleData['wheelCount'] as int? ?? 2,
    ));
  }

  
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColor.themeColor, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Confirm Booking',
            style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 18, color: AppColor.blackColor),
          ),
          systemOverlayStyle: const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark),
        ),
        body: SafeArea(top: false, child: _buildForm(size)),
      ),
    );
  }

  void _changeVehicle() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RouteVehicleScreen(
          pickupLatLng:           LatLng(
            (widget.pickupData['lat'] as num).toDouble(),
            (widget.pickupData['lng'] as num).toDouble(),
          ),
          pickupAddress:          widget.pickupData['address']?.toString() ?? '',
          pickupContactName:      widget.pickupData['contact_name']?.toString() ?? '',
          pickupContactPhone:     widget.pickupData['contact_phone']?.toString() ?? '',
          dropLatLng:             LatLng(
            (widget.dropData['lat'] as num).toDouble(),
            (widget.dropData['lng'] as num).toDouble(),
          ),
          dropAddress:            widget.dropData['address']?.toString() ?? '',
          preSelectedVehicleName: _vehicleData['name']?.toString(),
          onVehicleSelected: (selection) {
            setState(() {
              _vehicleTypeId    = selection['vehicleTypeId']?.toString() ?? _vehicleTypeId;
              _subVehicleTypeId = selection['subVehicleTypeId']?.toString() ?? _subVehicleTypeId;
              _vehicleData      = Map<String, dynamic>.from(selection['vehicleData'] as Map);
              _rawDistanceKm    = (selection['rawDistanceKm'] as num?)?.toDouble() ?? _rawDistanceKm;
              _estimatedFare    = (selection['estimatedFare'] as num?)?.toInt() ?? _estimatedFare;
            });
          },
        ),
      ),
    );
  }

  Widget _buildForm(Size size) {
    final vehicleName = _vehicleData['name'] as String? ?? 'Vehicle';
    final wc = _vehicleData['wheelCount'] as int? ?? 4;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: size.width * 0.045, vertical: size.height * 0.02),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Route summary ─────────────────────────────────────────────
          _SectionCard(
            child: Column(
              children: [
                _LocationRow(dot: AppColor.greenColor, label: widget.pickupData['address'] as String? ?? 'Pickup'),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: SizedBox(height: 14, child: VerticalDivider(width: 10, thickness: 1.5, color: AppColor.greyLightColor)),
                ),
                _LocationRow(dot: AppColor.redColor, label: widget.dropData['address'] as String? ?? 'Drop'),
                const Divider(height: 20, thickness: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      const Icon(Icons.route_rounded, size: 15, color: AppColor.themeColor),
                      const SizedBox(width: 4),
                      Text('${_rawDistanceKm.toStringAsFixed(1)} km',
                        style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w500, fontSize: 13, color: AppColor.blackColor)),
                    ]),
                    Text('Est. ₹${_estimatedFare}',
                      style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 15, color: AppColor.themeColor)),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(height: size.height * 0.018),

          // ── Vehicle card ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColor.themeColor.withOpacity(0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColor.themeColor.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(color: AppColor.themeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(13)),
                  child: Icon(_iconForWheelCount(wc), color: AppColor.themeColor, size: 28),
                ),
                SizedBox(width: size.width * 0.035),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(vehicleName, style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 15, color: AppColor.blackColor)),
                      const SizedBox(height: 2),
                      Text(_capacityForWheelCount(wc), style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w400, fontSize: 12, color: AppColor.hintTextColor)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹$_estimatedFare',
                      style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 20, color: AppColor.themeColor)),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: _changeVehicle,
                      child: const Text('Change',
                        style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 12, color: AppColor.themeColor, decoration: TextDecoration.underline)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(height: size.height * 0.025),

          // ── Sender details (person placing the booking) ───────────────
          _buildSectionTitle('Sender Details'),
          SizedBox(height: size.height * 0.012),
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Who is sending this delivery?',
                  style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w400, fontSize: 12, color: AppColor.hintTextColor)),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _InputField(
                            controller: _senderNameCtrl,
                            label: 'Sender Name',
                            icon: Icons.person_outline_rounded,
                            inputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          _InputField(
                            controller: _senderPhoneCtrl,
                            label: 'Sender Phone',
                            icon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            maxLength: 10,
                            inputFormatters: [PhoneNumberFormatter()],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ── Contacts picker button ──────────────────────────
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: InkWell(
                        onTap: () => _pickContact(
                          nameCtrl: _senderNameCtrl,
                          phoneCtrl: _senderPhoneCtrl,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColor.themeColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColor.themeColor.withOpacity(0.4)),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.contacts_outlined, color: AppColor.themeColor, size: 22),
                              SizedBox(height: 2),
                              Text('Pick', style: TextStyle(fontSize: 10, color: AppColor.themeColor, fontFamily: AppFont.fontFamily)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(height: size.height * 0.025),

          // ── Receiver details ──────────────────────────────────────────
          _buildSectionTitle('Receiver Details'),
          SizedBox(height: size.height * 0.012),
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Who will receive this delivery?',
                  style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w400, fontSize: 12, color: AppColor.hintTextColor)),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _InputField(
                            controller: _receiverNameCtrl,
                            label: 'Receiver Name',
                            icon: Icons.person_outline_rounded,
                            inputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          _InputField(
                            controller: _receiverPhoneCtrl,
                            label: 'Receiver Phone',
                            icon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            maxLength: 10,
                            inputFormatters: [PhoneNumberFormatter()],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ── Contacts picker button ──────────────────────────
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: InkWell(
                        onTap: () => _pickContact(
                          nameCtrl: _receiverNameCtrl,
                          phoneCtrl: _receiverPhoneCtrl,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColor.themeColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColor.themeColor.withOpacity(0.4)),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.contacts_outlined, color: AppColor.themeColor, size: 22),
                              SizedBox(height: 2),
                              Text('Pick', style: TextStyle(fontSize: 10, color: AppColor.themeColor, fontFamily: AppFont.fontFamily)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    final uc = Provider.of<UserController>(context, listen: false);
                    setState(() {
                      _useOwnPhone = !_useOwnPhone;
                      _receiverPhoneCtrl.text = _useOwnPhone ? uc.getUserMobile : '';
                    });
                  },
                  child: Row(
                    children: [
                      Checkbox(
                        value: _useOwnPhone,
                        activeColor: AppColor.themeColor,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (v) {
                          final uc = Provider.of<UserController>(context, listen: false);
                          setState(() {
                            _useOwnPhone = v ?? false;
                            _receiverPhoneCtrl.text = _useOwnPhone ? uc.getUserMobile : '';
                          });
                        },
                      ),
                      const Expanded(
                        child: Text('I am also the receiver (self-pickup)',
                          style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w400, fontSize: 13, color: AppColor.blackColor)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: size.height * 0.025),

          // ── Goods type ────────────────────────────────────────────────
          _buildSectionTitle('Goods Type'),
          SizedBox(height: size.height * 0.012),
          _SectionCard(
            child: _loadingCategories
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColor.themeColor),
                    ),
                  )
                : _goodsTypes.isEmpty
                    ? const Text('No categories available. Please check your connection.',
                        style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, color: AppColor.hintTextColor))
                    : Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _goodsTypes.map((g) {
                          final isSelected = _selectedGoodsTypeId == g['id'];
                          return GestureDetector(
                            onTap: () => setState(() {
                              _selectedGoodsTypeId = g['id'] as String;
                              _selectedGoodsTypeName = g['name'] as String;
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColor.themeColor.withOpacity(0.08) : const Color(0xffF6F7FB),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? AppColor.themeColor : AppColor.borderColor,
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.inventory_2_outlined, size: 15,
                                    color: isSelected ? AppColor.themeColor : AppColor.hintTextColor),
                                  const SizedBox(width: 6),
                                  Text(g['name'] as String,
                                    style: TextStyle(
                                      fontFamily: AppFont.fontFamily,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                      color: isSelected ? AppColor.themeColor : AppColor.blackColor,
                                    )),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
          ),

          SizedBox(height: size.height * 0.025),

          // ── Schedule ──────────────────────────────────────────────────
          _buildSectionTitle('Schedule'),
          SizedBox(height: size.height * 0.012),
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _ScheduleToggle(label: 'Book Now', icon: Icons.bolt_rounded,
                      isSelected: _scheduleMode == 0, onTap: () => setState(() => _scheduleMode = 0))),
                    const SizedBox(width: 10),
                    Expanded(child: _ScheduleToggle(label: 'Schedule Later', icon: Icons.calendar_today_rounded,
                      isSelected: _scheduleMode == 1, onTap: () => setState(() => _scheduleMode = 1))),
                  ],
                ),
                if (_scheduleMode == 1) ...[
                  const SizedBox(height: 16),
                  // Date picker row
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xffF6F7FB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColor.borderColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_rounded, size: 18, color: AppColor.themeColor),
                          const SizedBox(width: 10),
                          Text(_displayDate(_selectedDate),
                            style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w500, fontSize: 14, color: AppColor.blackColor)),
                          const Spacer(),
                          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColor.hintTextColor),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Shift selector
                  Row(
                    children: _shifts.map((shift) {
                      final sel = _selectedShift == shift;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _selectedShift = shift;
                            _selectedSlot = _slotsByShift[shift]!.first;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: EdgeInsets.only(right: shift != _shifts.last ? 8 : 0),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: sel ? AppColor.themeColor : const Color(0xffF6F7FB),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(shift, textAlign: TextAlign.center,
                              style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w500, fontSize: 13,
                                color: sel ? Colors.white : AppColor.blackColor)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  // Slot dropdown
                  DropdownButtonFormField<String>(
                    value: _selectedSlot,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.access_time_rounded, color: AppColor.themeColor, size: 18),
                      filled: true,
                      fillColor: const Color(0xffF6F7FB),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColor.borderColor)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColor.borderColor)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColor.themeColor)),
                    ),
                    style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, color: AppColor.blackColor),
                    items: _slotsByShift[_selectedShift]!.map((s) =>
                      DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) => setState(() => _selectedSlot = v!),
                  ),
                ],
              ],
            ),
          ),

          SizedBox(height: size.height * 0.025),

          // ── Note (optional) ───────────────────────────────────────────
          _buildSectionTitle('Note (Optional)'),
          SizedBox(height: size.height * 0.012),
          _SectionCard(
            child: TextField(
              controller: _noteCtrl,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'Any special instructions for the driver...',
                hintStyle: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 13, color: AppColor.hintTextColor),
                border: InputBorder.none,
              ),
              style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 14, color: AppColor.blackColor),
            ),
          ),

          SizedBox(height: size.height * 0.025),

          // ── Payment method ────────────────────────────────────────────
          _buildSectionTitle('Payment Method'),
          SizedBox(height: size.height * 0.012),
          _PaymentOption(label: 'Pay at Pickup  (Cash / UPI)', subtitle: 'Pay when driver arrives',
            icon: Icons.location_on_rounded, value: 0, groupValue: _paymentMode,
            onChanged: (v) => setState(() => _paymentMode = v!)),
          _PaymentOption(label: 'Pay at Drop  (Cash / UPI)', subtitle: 'Pay after delivery',
            icon: Icons.flag_rounded, value: 1, groupValue: _paymentMode,
            onChanged: (v) => setState(() => _paymentMode = v!)),
          _PaymentOption(label: 'Pay Online Now  (Razorpay)', subtitle: 'Secure payment via Razorpay',
            icon: Icons.credit_card_rounded, value: 2, groupValue: _paymentMode,
            onChanged: (v) => setState(() => _paymentMode = v!)),

          SizedBox(height: size.height * 0.035),

          // ── Confirm button ────────────────────────────────────────────
          Consumer<PostApiProvider>(
            builder: (_, api, __) {
              final bool busy = _isBooking || api.loading;
              return SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: busy ? null : _confirmBooking,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColor.themeColor,
                    disabledBackgroundColor: AppColor.themeColor.withOpacity(0.5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: busy
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : Text('Confirm Booking  •  ₹${_estimatedFare}',
                          style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 16)),
                ),
              );
            },
          ),

          SizedBox(height: size.height * 0.04),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Text(
    title,
    style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 15, color: AppColor.blackColor),
  );

  // ── Finding driver phase ───────────────────────────────────────────────────

  Widget _buildFindingDriver(Size size) {
    return Column(
      children: [
        const Spacer(),
        Container(
          width: size.width * 0.35, height: size.width * 0.35,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColor.themeColor.withOpacity(0.08),
            border: Border.all(color: AppColor.themeColor.withOpacity(0.15), width: 1.5),
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Image.asset(
                _findingVehicles[_currentVehicleIndex],
                key: ValueKey<int>(_currentVehicleIndex),
                width: size.width * 0.22,
                height: size.width * 0.22,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        SizedBox(height: size.height * 0.03),
        const Text('Finding Your Driver',
          style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 22, color: AppColor.blackColor)),
        SizedBox(height: size.height * 0.01),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.1),
          child: const Text('Please wait while we connect you with a nearby driver',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w400, fontSize: 14, color: AppColor.hintTextColor, height: 1.5)),
        ),
        SizedBox(height: size.height * 0.04),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
          decoration: BoxDecoration(color: AppColor.themeColor.withOpacity(0.06), borderRadius: BorderRadius.circular(18)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer_outlined, color: AppColor.themeColor, size: 24),
              const SizedBox(width: 10),
              Text(_formatTime(_remainingSeconds),
                style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 30, color: AppColor.themeColor, letterSpacing: 2)),
            ],
          ),
        ),
        const Spacer(),
        Padding(
          padding: EdgeInsets.fromLTRB(size.width * 0.06, 0, size.width * 0.06, size.height * 0.04),
          child: OutlinedButton.icon(
            onPressed: () {
              if (_createdBookingId == null) return;
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => CancelRideScreen(bookingId: _createdBookingId!, userType: 'retailer')));
            },
            icon: const Icon(Icons.close_rounded, color: AppColor.redColor, size: 18),
            label: const Text('Cancel Booking',
              style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, fontSize: 15, color: AppColor.redColor)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColor.redColor, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              minimumSize: const Size(double.infinity, 52),
              foregroundColor: AppColor.redColor,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xffF6F7FB),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColor.borderColor),
    ),
    child: child,
  );
}

class _LocationRow extends StatelessWidget {
  final Color dot;
  final String label;
  const _LocationRow({required this.dot, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      Expanded(
        child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w400, fontSize: 13, color: AppColor.blackColor)),
      ),
    ],
  );
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputAction inputAction;
  final TextInputType keyboardType;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;

  const _InputField({
    required this.controller,
    required this.label,
    required this.icon,
    this.inputAction = TextInputAction.done,
    this.keyboardType = TextInputType.text,
    this.maxLength,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    textInputAction: inputAction,
    keyboardType: keyboardType,
    maxLength: maxLength,
    inputFormatters: inputFormatters,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColor.themeColor, size: 20),
      counterText: '',
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColor.borderColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColor.themeColor, width: 1.4)),
    ),
  );
}

class _ScheduleToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ScheduleToggle({required this.label, required this.icon, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: isSelected ? AppColor.themeColor : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSelected ? AppColor.themeColor : AppColor.borderColor),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: isSelected ? Colors.white : AppColor.hintTextColor),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w500, fontSize: 12,
            color: isSelected ? Colors.white : AppColor.blackColor)),
        ],
      ),
    ),
  );
}

class _PaymentOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final int value;
  final int groupValue;
  final ValueChanged<int?> onChanged;

  const _PaymentOption({required this.label, required this.subtitle, required this.icon,
    required this.value, required this.groupValue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final bool isSelected = groupValue == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColor.themeColor.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: isSelected ? AppColor.themeColor : AppColor.borderColor, width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Container(width: 38, height: 38,
              decoration: BoxDecoration(
                color: isSelected ? AppColor.themeColor.withOpacity(0.1) : const Color(0xffF6F7FB),
                borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 20, color: isSelected ? AppColor.themeColor : AppColor.hintTextColor)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w500, fontSize: 13,
                    color: isSelected ? AppColor.themeColor : AppColor.blackColor)),
                  Text(subtitle, style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w400, fontSize: 11, color: AppColor.hintTextColor)),
                ],
              ),
            ),
            Radio<int>(value: value, groupValue: groupValue, onChanged: onChanged, activeColor: AppColor.themeColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ],
        ),
      ),
    );
  }
}
