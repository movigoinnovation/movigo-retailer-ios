import 'dart:io';

import 'package:flutter/gestures.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/contentService.dart';
import 'package:movigo/helper/contentScreen.dart';
import 'package:movigo/helper/policy_content_screen.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';

class SignupScreen extends StatefulWidget {
  final String? mobile;
  const SignupScreen({super.key, this.mobile});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
{
  // Retailer-only app: always Retailer (type selector removed)
  final int _userType = 1;

  // Customer fields
  final _customerNameCtrl    = TextEditingController();
  final _customerAddressCtrl = TextEditingController();

  // Retailer fields
  final _retailerNameCtrl  = TextEditingController();
  final _bizNameCtrl       = TextEditingController();
  final _altPhoneCtrl      = TextEditingController();
  final _bizAddressCtrl    = TextEditingController();
  final _gstCtrl           = TextEditingController();

  // Shared
  final _mobileCtrl = TextEditingController();

  bool _fetchingLoc = false;
  bool _isTermsAgreed = false;
  String _termsUrl  = '';
  String _privacyUrl = '';


  @override
  void initState() {
    super.initState();
    if (widget.mobile != null && widget.mobile!.isNotEmpty) {
      _mobileCtrl.text = widget.mobile!;
    }
    _loadContent();

  }

  void _loadContent() {
    fetchAllContent((List data) {
      for (final item in data) {
        if (item['content_type'] == 2) _termsUrl   = item['content_url'];
        if (item['content_type'] == 1) _privacyUrl = item['content_url'];
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in [
      _customerNameCtrl, _customerAddressCtrl,
      _retailerNameCtrl, _bizNameCtrl, _altPhoneCtrl,
      _bizAddressCtrl, _gstCtrl, _mobileCtrl,
    ]) { c.dispose(); }
    super.dispose();
  }

  // ── Location ──────────────────────────────────────────────────────────────
  Future<void> _fetchLocation() async {
    setState(() => _fetchingLoc = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _snack('Location permission denied'); return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final _gUri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${pos.latitude},${pos.longitude}'
        '&key=${AppConstant.googleApiKey}'
        '&language=en',
      );
      final _gResp = await http.get(_gUri).timeout(const Duration(seconds: 6));
      if (_gResp.statusCode == 200) {
        final _gData = jsonDecode(_gResp.body) as Map<String, dynamic>;
        final _gResults = _gData['results'] as List? ?? [];
        if (_gResults.isNotEmpty) {
          final addr = _gResults.first['formatted_address']?.toString() ?? '';
          if (addr.isNotEmpty) setState(() => _bizAddressCtrl.text = addr);
        }
      }
    } catch (_) {
      _snack('Could not fetch location');
    } finally {
      if (mounted) setState(() => _fetchingLoc = false);
    }
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submitRetailer() async {
    final name    = _retailerNameCtrl.text.trim();
    final biz     = _bizNameCtrl.text.trim();
    final mobile  = _mobileCtrl.text.trim();
    final address = _bizAddressCtrl.text.trim();

    if (name.isEmpty)    { _snack('Please enter your name'); return; }
    if (biz.isEmpty)     { _snack('Business name is required'); return; }
    if (mobile.length != 10) { _snack('Valid phone number required'); return; }
    if (address.isEmpty) { _snack('Business address is required'); return; }
    if (!_isTermsAgreed) { _snack('Please agree to Terms and Privacy Policy'); return; }

    final p = Provider.of<PostApiProvider>(context, listen: false);
    final ok = await p.retailerSignupApi(
      context,
      businessName: biz,
      retailerName: name,
      description:  '',
      email:        '',
      phoneNumber:  mobile,
      address:      address,
      landmark:     _gstCtrl.text.trim().isNotEmpty
                      ? 'GST: ${_gstCtrl.text.trim()}' : '',
      profileImage: null,
    );
    if (ok) Get.offAll(() => CustomBottomNav(userType: UserType.retailer));
  }

  void _snack(String msg) =>
      SnackBarToastMessage.showSnackBar(context, msg);

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));

    return PopScope(
      canPop: false,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.07),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: size.height * 0.03),

                    // ── Logo ─────────────────────────────────────────────────
                    Image.asset(
                      AppImage.applogo3,
                      height: size.width * 0.32,
                      width:  size.width * 0.48,
                      fit: BoxFit.contain,
                    ),

                    SizedBox(height: size.height * 0.01),

                    // ── Title ────────────────────────────────────────────────
                    Text(
                      'Create Account',
                      style: const TextStyle(
                        color: AppColor.blackColor,
                        fontFamily: AppFont.fontFamily,
                        fontWeight: FontWeight.w600,
                        fontSize: 24,
                      ),
                    ),

                    SizedBox(height: size.height * 0.010),

                    Text(
                      'Fill in your details to get started',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColor.textColorTwo,
                        fontFamily: AppFont.fontFamily,
                        fontWeight: FontWeight.w400,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),

                    SizedBox(height: size.height * 0.025),

                    // ── Fields (always Retailer) ─────────────────────────
                    _retailerFields(size),

                    SizedBox(height: size.height * 0.03),

                    // ── Policy Agreement ──────────────────────────────────────
                    PolicyAgreementWidget(
                      isAgreed: _isTermsAgreed,
                      onChanged: (value) {
                        setState(() {
                          _isTermsAgreed = value ?? false;
                        });
                      },
                    ),

                    SizedBox(height: size.height * 0.03),

                    // ── Submit button ─────────────────────────────────────────
                    Consumer<PostApiProvider>(
                      builder: (_, api, __) => api.loading
                        ? const CircularProgressIndicator(
                            color: AppColor.themeColor)
                        : AppButton(
                            text: 'Create Account',
                            onPress: _submitRetailer,
                          ),
                    ),

                    SizedBox(height: size.height * 0.025),

                    // ── Updated Terms Section ────────────────────────────────
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: const TextStyle(
                          color: AppColor.textColorTwo,
                          fontSize: 12,
                          fontFamily: AppFont.fontFamily,
                        ),
                        children: [
                          const TextSpan(text: 'By signing up, you agree to our '),
                          TextSpan(
                            text: 'Terms and Conditions',
                            style: const TextStyle(
                              color: AppColor.primaryColor,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const PolicyContentScreen(
                                      policyType: 'terms_conditions',
                                      title: 'Terms and Conditions',
                                    ),
                                  ),
                                );
                              },
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: const TextStyle(
                              color: AppColor.primaryColor,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const PolicyContentScreen(
                                      policyType: 'privacy_policy',
                                      title: 'Privacy Policy',
                                    ),
                                  ),
                                );
                              },
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: size.height * 0.03),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Customer fields ────────────────────────────────────────────────────────
  Widget _customerFields(Size size) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label('Full Name *'),
      _field(ctrl: _customerNameCtrl, hint: 'Enter your full name'),
      _gap(size),

      _label('Phone Number *'),
      _phoneField(_mobileCtrl, readOnly: true),
      _gap(size),

      _label('Home Address (optional)'),
      _multiField(ctrl: _customerAddressCtrl,
          hint: 'Enter your home address (optional)'),
    ],
  );

  // ── Retailer fields ────────────────────────────────────────────────────────
  Widget _retailerFields(Size size) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label('Your Name *'),
      _field(ctrl: _retailerNameCtrl, hint: 'Enter your full name'),
      _gap(size),

      _label('Business Name *'),
      _field(ctrl: _bizNameCtrl, hint: 'Enter your business name'),
      _gap(size),

      _label('Phone Number *'),
      _phoneField(_mobileCtrl, readOnly: true),
      _gap(size),

      _label('Alternate Phone (optional)'),
      _phoneField(_altPhoneCtrl, readOnly: false),
      _gap(size),

      _label('Business Address *'),
      _addressField(size),
      SizedBox(height: size.height * 0.005),
      Row(children: [
        const Icon(Icons.info_outline, size: 12,
            color: AppColor.textColorTwo),
        const SizedBox(width: 4),
        Text('Tap 📍 to auto-fill current location',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500,
              fontFamily: AppFont.fontFamily)),
      ]),
      _gap(size),

      _label('GST Number (optional)'),
      _field(ctrl: _gstCtrl, hint: 'Enter GST number if applicable',
          kbt: TextInputType.text),
    ],
  );

  // ── Address field with GPS button ──────────────────────────────────────────
  Widget _addressField(Size size) => Stack(
    children: [
      TextField(
        controller: _bizAddressCtrl,
        maxLines: 3,
        minLines: 2,
        style: const TextStyle(
            fontFamily: AppFont.fontFamily, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Enter address or tap 📍 for GPS',
          hintStyle: TextStyle(
              color: AppColor.hintTextColor,
              fontSize: 14,
              fontFamily: AppFont.fontFamily,
              fontWeight: FontWeight.w400),
          filled: true,
          fillColor: AppColor.textFiledColor,
          contentPadding:
              const EdgeInsets.fromLTRB(16, 14, 52, 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(
                  color: AppColor.themeColor, width: 1.5)),
        ),
      ),
      Positioned(
        right: 10,
        top: 10,
        child: GestureDetector(
          onTap: _fetchLocation,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColor.themeColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _fetchingLoc
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.my_location,
                  color: Colors.white, size: 16),
          ),
        ),
      ),
    ],
  );

  // ── Reusable field widgets ────────────────────────────────────────────────
  Widget _field({
    required TextEditingController ctrl,
    required String hint,
    TextInputType kbt = TextInputType.text,
  }) =>
      TextField(
        controller: ctrl,
        keyboardType: kbt,
        style: const TextStyle(
            fontFamily: AppFont.fontFamily, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: AppColor.hintTextColor,
              fontSize: 14,
              fontFamily: AppFont.fontFamily,
              fontWeight: FontWeight.w400),
          filled: true,
          fillColor: AppColor.textFiledColor,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(
                  color: AppColor.themeColor, width: 1.5)),
        ),
      );

  Widget _phoneField(TextEditingController ctrl,
      {required bool readOnly}) =>
      TextField(
        controller: ctrl,
        readOnly: readOnly,
        keyboardType: TextInputType.phone,
        maxLength: 10,
        style: const TextStyle(
            fontFamily: AppFont.fontFamily, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Enter 10-digit number',
          hintStyle: TextStyle(
              color: AppColor.hintTextColor,
              fontSize: 14,
              fontFamily: AppFont.fontFamily,
              fontWeight: FontWeight.w400),
          prefixText: '+91  ',
          prefixStyle: const TextStyle(
              fontFamily: AppFont.fontFamily,
              fontSize: 15,
              color: AppColor.blackColor,
              fontWeight: FontWeight.w500),
          filled: true,
          fillColor: AppColor.textFiledColor,
          counterText: '',
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(
                  color: AppColor.themeColor, width: 1.5)),
        ),
      );

  Widget _multiField({
    required TextEditingController ctrl,
    required String hint,
  }) =>
      TextField(
        controller: ctrl,
        maxLines: 3,
        minLines: 2,
        style: const TextStyle(
            fontFamily: AppFont.fontFamily, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: AppColor.hintTextColor,
              fontSize: 14,
              fontFamily: AppFont.fontFamily,
              fontWeight: FontWeight.w400),
          filled: true,
          fillColor: AppColor.textFiledColor,
          contentPadding: const EdgeInsets.all(16),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(
                  color: AppColor.themeColor, width: 1.5)),
        ),
      );

  // ── Tab widget ─────────────────────────────────────────────────────────────

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: AppFont.fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColor.blackColor,
      ),
    ),
  );

  Widget _gap(Size size) => SizedBox(height: size.height * 0.022);
}
