import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Controller/check_booking_status_controller.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/utilities/phone_number_formatter.dart';
import 'package:movigo/view/customer_screen/create_booking_screen/booking_detail_screen.dart';
import 'package:movigo/view/customer_screen/create_booking_screen/finding_driver_screen.dart';
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
  final String pickupHouse;
  final String pickupLandmark;
  final String pickupNote;
  final String dropContactName;
  final String dropContactPhone;
  final String dropHouse;
  final String dropLandmark;
  final String dropNote;
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
    this.pickupHouse = '',
    this.pickupLandmark = '',
    this.pickupNote = '',
    this.dropContactName = '',
    this.dropContactPhone = '',
    this.dropHouse = '',
    this.dropLandmark = '',
    this.dropNote = '',
    this.extraStops = const [],
  });

  @override
  State<NewConfirmScreen> createState() => _NewConfirmScreenState();
}

class _NewConfirmScreenState extends State<NewConfirmScreen> {
  // 0 = pay at pickup, 1 = pay at drop, 2 = online
  int _paymentMode = 0;

  final TextEditingController _receiverNameController = TextEditingController();
  final TextEditingController _receiverPhoneController = TextEditingController();

  late final TextEditingController _senderNameCtrl;
  late final TextEditingController _senderPhoneCtrl;
  late final TextEditingController _pickupLandmarkCtrl;
  late final TextEditingController _pickupNoteCtrl;
  late final TextEditingController _dropLandmarkCtrl;
  late final TextEditingController _dropNoteCtrl;

  bool _isFindingDriver = false;
  String? _createdBookingId;
  Timer? _countdownTimer;
  Timer? _statusTimer;
  bool _dialogShown = false;

  String _userType = "";

  bool get _isRetailer => _userType.toLowerCase() == 'retailer';

  late Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    final uc = Provider.of<UserController>(context, listen: false);
    _userType = uc.getUserType;

    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);

    _senderNameCtrl     = TextEditingController(text: widget.pickupContactName);
    _senderPhoneCtrl    = TextEditingController(text: widget.pickupContactPhone);
    _pickupLandmarkCtrl = TextEditingController(text: widget.pickupLandmark);
    _pickupNoteCtrl     = TextEditingController(text: widget.pickupNote);
    _dropLandmarkCtrl   = TextEditingController(text: widget.dropLandmark);
    _dropNoteCtrl       = TextEditingController(text: widget.dropNote);

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _statusTimer?.cancel();
    _receiverNameController.dispose();
    _receiverPhoneController.dispose();
    _senderNameCtrl.dispose();
    _senderPhoneCtrl.dispose();
    _pickupLandmarkCtrl.dispose();
    _pickupNoteCtrl.dispose();
    _dropLandmarkCtrl.dispose();
    _dropNoteCtrl.dispose();
    _razorpay.clear();
    super.dispose();
  }

  void _useMyNumberForSender() {
    final uc = Provider.of<UserController>(context, listen: false);
    String name = uc.getUserName;
    String phone = uc.getUserMobile;
    phone = phone.replaceAll(RegExp(r'\D'), '');
    if (phone.length > 10) {
      if (phone.startsWith('91')) {
        phone = phone.substring(2);
      } else if (phone.startsWith('0')) {
        phone = phone.substring(1);
      }
    }
    if (phone.length > 10) phone = phone.substring(phone.length - 10);
    setState(() {
      _senderNameCtrl.text  = name;
      _senderPhoneCtrl.text = phone;
    });
  }

  // ── Payment ────────────────────────────────────────────────────────────────

  Future<void> _confirmBooking() async {
    // Show loading immediately so the button disables on the same frame
    final api = Provider.of<PostApiProvider>(context, listen: false);
    api.setLoading(true);
    if (_paymentMode == 2) {
      api.setLoading(false); // Razorpay manages its own loading state
      _openRazorpay();
    } else {
      await _createBooking(paymentMode: "Cash", transactionId: "");
    }
  }

  Future<void> _openRazorpay() async {
    final uc = Provider.of<UserController>(context, listen: false);
    final api = Provider.of<PostApiProvider>(context, listen: false);
    // Capture context-dependent values before the async gap
    final capturedContext = context;
    try {
      // Create server-side order with 1% operational fee
      final orderRes = await api.createBookingPaymentOrder(
        capturedContext,
        baseFare: widget.estimatedFare,
      );
      if (orderRes == null) return;
      if (!mounted) return;

      final orderId = orderRes['order_id']?.toString() ?? '';
      final razorpayKey = AppConstant.razorpayKeyFromOrder(orderRes);
      if (razorpayKey.isEmpty) {
        if (!mounted) return;
        SnackBarToastMessage.showSnackBar(
            context, 'Payment key missing. Please try again later.');
        return;
      }
      final amountPaise = (orderRes['amount_paise'] as num?)?.toInt() ??
          (widget.estimatedFare * 100);
      final processingFee =
          (orderRes['processing_fee'] as num?)?.toInt() ?? 0;

      _razorpay.open({
        'key': razorpayKey,
        'amount': amountPaise,
        'order_id': orderId,
        'name': 'Movigo',
        'description': 'Ride Booking (incl. ₹$processingFee processing fee)',
        'prefill': {
          'contact': uc.getUserMobile,
          'email':
              uc.getUserEmail.isNotEmpty ? uc.getUserEmail : 'user@movigo.com',
        },
        'theme': {'color': '#0A3D91'},
      });
    } catch (_) {
      if (!mounted) return;
      SnackBarToastMessage.showSnackBar(
          context, 'Could not open payment. Try again.');
    }
  }

  void _onPaymentSuccess(PaymentSuccessResponse res) {
    _createBooking(paymentMode: "Online", transactionId: res.paymentId ?? "");
  }

  void _onPaymentError(PaymentFailureResponse _) {
    if (mounted) {
      SnackBarToastMessage.showSnackBar(
          context, "Payment failed. Please try again.");
    }
  }

  void _onExternalWallet(ExternalWalletResponse _) {}

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
        customerName: _senderNameCtrl.text.trim(),
        customerPhone: _senderPhoneCtrl.text.trim(),
        pickupAddress: _formatAddress(widget.pickupHouse, _pickupLandmarkCtrl.text.trim(),
            widget.pickupData['address'] as String? ?? ""),
        pickupLat: (widget.pickupData['lat'] as num).toDouble(),
        pickupLng: (widget.pickupData['lng'] as num).toDouble(),
        dropAddress: _formatAddress(widget.dropHouse, _dropLandmarkCtrl.text.trim(),
            widget.dropData['address'] as String? ?? ""),
        dropLat: (widget.dropData['lat'] as num).toDouble(),
        dropLng: (widget.dropData['lng'] as num).toDouble(),
        pickupDate: widget.pickupDate.isNotEmpty ? widget.pickupDate : dateStr,
        pickupShift: "Anytime",
        pickupSlot: widget.pickupSlot,
        itemCategoryId: "",
        paymentMode: paymentMode,
        bookingType: widget.bookingType,
        note: _combineNotes(_pickupNoteCtrl.text.trim(), _dropNoteCtrl.text.trim()),
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
        senderName: _senderNameCtrl.text.trim(),
        senderPhone: _senderPhoneCtrl.text.trim(),
        receiverName: widget.dropContactName,
        receiverPhone: widget.dropContactPhone,
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
        ...widget.extraStops.map((s) => {
          'address':       s['address'] ?? '',
          'latitude':      s['lat'],
          'longitude':     s['lng'],
          'contact_name':  s['contact_name'] ?? '',
          'contact_phone': s['contact_phone'] ?? '',
        }),
        {
          'address':       widget.dropData['address'] ?? '',
          'latitude':      widget.dropData['lat'],
          'longitude':     widget.dropData['lng'],
          'contact_name':  widget.dropContactName,
          'contact_phone': widget.dropContactPhone,
        },
      ];

      final body = <String, dynamic>{
        'booking_type':           widget.bookingType,
        'vehicleType_id':         widget.vehicleTypeId,
        'subVehicleType_id':      widget.subVehicleTypeId,
        'transaction_id':         transactionId,
        'customer_name':          _senderNameCtrl.text.trim(),
        'customer_phone':         _senderPhoneCtrl.text.trim(),
        'sender_name':            _senderNameCtrl.text.trim(),
        'sender_phone':           _senderPhoneCtrl.text.trim(),
        'pickup_address':         widget.pickupData['address'] ?? '',
        'pickup_lat':             widget.pickupData['lat'],
        'pickup_lng':             widget.pickupData['lng'],
        'drop_address':           widget.dropData['address'] ?? '',
        'drop_lat':               widget.dropData['lat'],
        'drop_lng':               widget.dropData['lng'],
        'receiver_name':          widget.dropContactName,
        'receiver_phone':         widget.dropContactPhone,
        'pickup_date':            widget.pickupDate.isNotEmpty ? widget.pickupDate : dateStr,
        'pickup_shift':           'Anytime',
        'pickup_slot':            widget.pickupSlot,
        'payment_mode':           paymentMode,
        'note':                   widget.pickupNote.isNotEmpty ? widget.pickupNote : widget.dropNote,
        'requested_vehicle_name': widget.vehicleData['name']?.toString() ?? '',
        'vehicle_category':       widget.vehicleData['vehicleCategory']?.toString() ?? '',
        'vehicle_key':            widget.vehicleData['vehicleKey']?.toString() ?? '',
        'required_tag':           widget.vehicleData['requiredTag']?.toString() ?? '',
        'display_vehicle_name':   widget.vehicleData['displayVehicleName']?.toString() ?? widget.vehicleData['name']?.toString() ?? '',
        'booking_flow':           'retailer',
        'raw_distance_km':        widget.rawDistanceKm,
        'is_multidrop':           true,
        'extra_drops':            allDrops,
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
                  label: _formatAddress(
                      widget.pickupHouse,
                      widget.pickupLandmark,
                      widget.pickupData['address'] as String? ?? "Pickup"),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: SizedBox(
                    height: 16,
                    child: VerticalDivider(
                        width: 10,
                        thickness: 1.5,
                        color: AppColor.greyLightColor),
                  ),
                ),
                _LocationRow(
                  dot: AppColor.redColor,
                  label: _formatAddress(widget.dropHouse, widget.dropLandmark,
                      widget.dropData['address'] as String? ?? "Drop"),
                ),
                const Divider(height: 20, thickness: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      const Icon(Icons.route_rounded,
                          size: 15, color: AppColor.themeColor),
                      const SizedBox(width: 4),
                      Text(
                        "${widget.rawDistanceKm.toStringAsFixed(1)} km",
                        style: const TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          color: AppColor.blackColor,
                        ),
                      ),
                    ]),
                    Text(
                      "₹${widget.estimatedFare}",
                      style: const TextStyle(
                        fontFamily: AppFont.fontFamily,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColor.themeColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(height: size.height * 0.02),

          // ── Vehicle card ─────────────────────────────────────────
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
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColor.themeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(_iconForWheelCount(wc),
                      color: AppColor.themeColor, size: 28),
                ),
                SizedBox(width: size.width * 0.035),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicleName,
                        style: const TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: AppColor.blackColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _capacityForWheelCount(wc),
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
                Text(
                  "₹${widget.estimatedFare}",
                  style: const TextStyle(
                    fontFamily: AppFont.fontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: AppColor.themeColor,
                  ),
                ),
              ],
            ),
          ),

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
          // ── Fare Breakdown ────────────────────────────────────
          // Uses estimatedFare from backend (single source of truth).
          // This matches exactly what vehicle selection screen showed.
          _FareBreakdownCard(
            requiredTag: widget.vehicleData['requiredTag']?.toString() ?? '',
            wheelCount: widget.vehicleData['wheelCount'] as int? ?? 2,
            rawDistanceKm: widget.rawDistanceKm,
            modifier:
                (widget.vehicleData['pricingModifier'] as num?)?.toDouble() ??
                    1.0,
            backendFare: widget.estimatedFare,
          ),
          SizedBox(height: size.height * 0.02),

          _buildContactsSummaryCard(size),
          SizedBox(height: size.height * 0.025),

          // ── Payment method ───────────────────────────────────────
          const Text(
            "Payment Method",
            style: TextStyle(
              fontFamily: AppFont.fontFamily,
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: AppColor.blackColor,
            ),
          ),
          SizedBox(height: size.height * 0.012),
          _PaymentOption(
            label: "Pay at Pickup  (Cash / UPI)",
            subtitle: "Pay when driver arrives",
            icon: Icons.location_on_rounded,
            value: 0,
            groupValue: _paymentMode,
            onChanged: (v) => setState(() => _paymentMode = v!),
          ),
          _PaymentOption(
            label: "Pay at Drop  (Cash / UPI)",
            subtitle: "Pay after delivery",
            icon: Icons.flag_rounded,
            value: 1,
            groupValue: _paymentMode,
            onChanged: (v) => setState(() => _paymentMode = v!),
          ),
          _PaymentOption(
            label: "Pay Online Now  (Razorpay)",
            subtitle: "Secure payment via Razorpay",
            icon: Icons.credit_card_rounded,
            value: 2,
            groupValue: _paymentMode,
            onChanged: (v) => setState(() => _paymentMode = v!),
          ),

          SizedBox(height: size.height * 0.035),

          // ── Confirm button ───────────────────────────────────────
          Consumer<PostApiProvider>(
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
                        _paymentMode == 2
                            ? 'Pay Online  •  ₹${widget.estimatedFare} + 1% operational fee'
                            : 'Confirm Booking  •  ₹${widget.estimatedFare}',
                        style: const TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ),
          SizedBox(height: size.height * 0.03),
        ],
      ),
    );
  }

  Widget _buildContactsSummaryCard(Size size) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Contact & Address Details",
          style: TextStyle(
            fontFamily: AppFont.fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: AppColor.blackColor,
          ),
        ),
        const SizedBox(height: 12),

        // ── Sender (Pickup) Card ────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColor.borderColor),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 4, height: 18, decoration: BoxDecoration(color: AppColor.successCOlor, borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 10),
                  const Text("Pickup (Sender)", style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 15, color: AppColor.blackColor)),
                ],
              ),
              const SizedBox(height: 12),

              // Use My Registered Number button
              GestureDetector(
                onTap: _useMyNumberForSender,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColor.themeColor.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColor.themeColor.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.person_rounded, size: 15, color: AppColor.themeColor),
                      SizedBox(width: 7),
                      Text("Use My Registered Number",
                          style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, fontWeight: FontWeight.w600, color: AppColor.themeColor)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              _buildMiniField("Sender Name (Optional)", _senderNameCtrl, Icons.person_outline_rounded, TextInputType.name),
              const SizedBox(height: 10),
              _buildMiniField("Sender Phone", _senderPhoneCtrl, Icons.phone_iphone_rounded, TextInputType.phone, maxLength: 10),
              const SizedBox(height: 10),
              _buildMiniField("Pickup Landmark (Optional)", _pickupLandmarkCtrl, Icons.pin_drop_rounded, TextInputType.text),
              const SizedBox(height: 10),
              _buildMiniField("Note for Driver (Optional)", _pickupNoteCtrl, Icons.note_alt_rounded, TextInputType.text, maxLines: 2),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Receiver (Dropoff) Card ─────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColor.borderColor),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 4, height: 18, decoration: BoxDecoration(color: AppColor.redColor, borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 10),
                  const Text("Dropoff (Receiver)", style: TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 15, color: AppColor.blackColor)),
                ],
              ),
              const SizedBox(height: 12),

              if (widget.dropContactName.isNotEmpty || widget.dropContactPhone.isNotEmpty) ...[
                _contactSummaryRow(
                  icon: Icons.import_contacts_rounded,
                  iconColor: AppColor.redColor,
                  title: "Receiver",
                  name: widget.dropContactName,
                  phone: widget.dropContactPhone,
                  note: '',
                ),
                const SizedBox(height: 10),
              ],

              _buildMiniField("Dropoff Landmark (Optional)", _dropLandmarkCtrl, Icons.pin_drop_rounded, TextInputType.text),
              const SizedBox(height: 10),
              _buildMiniField("Note for Driver (Optional)", _dropNoteCtrl, Icons.note_alt_rounded, TextInputType.text, maxLines: 2),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniField(
    String label,
    TextEditingController ctrl,
    IconData icon,
    TextInputType keyboardType, {
    int maxLines = 1,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppFont.fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 11,
            color: AppColor.fontColor,
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
          maxLines: maxLines,
          maxLength: maxLength,
          inputFormatters: keyboardType == TextInputType.phone ? [PhoneNumberFormatter()] : null,
          buildCounter: maxLength != null
              ? (_, {required currentLength, required isFocused, maxLength}) => null
              : null,
          style: const TextStyle(
            fontFamily: AppFont.fontFamily,
            fontSize: 13,
            color: AppColor.blackColor,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 16, color: AppColor.hintTextColor),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            fillColor: const Color(0xffF8FAFC),
            filled: true,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xffE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColor.themeColor, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _contactSummaryRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String name,
    required String phone,
    String note = '',
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: AppFont.fontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  color: AppColor.bluishGrayColor,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                name.isNotEmpty ? name : "Not Provided",
                style: const TextStyle(
                  fontFamily: AppFont.fontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColor.blackColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "+91 $phone",
                style: const TextStyle(
                  fontFamily: AppFont.fontFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: AppColor.themeColor,
                ),
              ),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.edit_note_rounded,
                          size: 14, color: Color(0xFFD97706)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          "Note: $note",
                          style: const TextStyle(
                            fontFamily: AppFont.fontFamily,
                            fontWeight: FontWeight.w500,
                            fontSize: 10,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Phase 2: Finding driver ────────────────────────────────────────────────

  String _formatAddress(String house, String landmark, String address) {
    final List<String> parts = [];
    if (house.isNotEmpty) parts.add(house);
    if (landmark.isNotEmpty) parts.add(landmark);
    if (address.isNotEmpty) parts.add(address);
    return parts.join(', ');
  }

  String _combineNotes(String text1, String text2) {
    if (text1.isEmpty) return text2;
    if (text2.isEmpty) return text1;
    return '$text1, $text2';
  }

  String _combineCustomerNotes(
      String name, String phone, String pNote, String dNote) {
    List<String> p = [];
    if (name.isNotEmpty) p.add('Pickup: ');
    if (phone.isNotEmpty) p.add(phone);
    if (pNote.isNotEmpty) p.add(pNote);
    if (dNote.isNotEmpty) p.add('Drop Note: ');
    return p.join(', ');
  }

  IconData _iconForWheelCount(int wc) {
    if (wc == 2) return Icons.two_wheeler;
    if (wc == 3) return Icons.local_shipping;
    return Icons.local_shipping;
  }

  String _capacityForWheelCount(int wc) {
    if (wc == 2) return 'Up to 20 kg';
    if (wc == 3) return 'Up to 500 kg';
    return 'Up to 1000 kg';
  }

}

class _FareBreakdownCard extends StatelessWidget {
  final String requiredTag;
  final int wheelCount;
  final double rawDistanceKm;
  final double modifier;
  final int backendFare;

  const _FareBreakdownCard({
    required this.requiredTag,
    required this.wheelCount,
    required this.rawDistanceKm,
    required this.modifier,
    required this.backendFare,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColor.themeColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColor.themeColor.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Total Fare', style: TextStyle(fontSize: 14)),
          Text('₹$backendFare',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final int value;
  final int groupValue;
  final ValueChanged<int?> onChanged;

  const _PaymentOption({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSelected = groupValue == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              isSelected ? AppColor.themeColor.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? AppColor.themeColor : AppColor.borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? AppColor.themeColor : Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color:
                              isSelected ? AppColor.themeColor : Colors.black)),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppColor.themeColor),
          ],
        ),
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  final Color dot;
  final String label;

  const _LocationRow({required this.dot, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4, right: 12),
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
          ),
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
        ],
      ),
    );
  }
}
