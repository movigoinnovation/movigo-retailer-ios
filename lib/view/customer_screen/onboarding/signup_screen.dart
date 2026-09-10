import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _gstCtrl           = TextEditingController();

  // Shared
  final _mobileCtrl = TextEditingController();

  bool _isTermsAgreed = false;
  String _termsUrl  = '';
  String _privacyUrl = '';

  // ── Field officer credit (optional, picked from the 3-line menu) ────────────
  List<Map<String, dynamic>> _officers = [];
  bool _officersLoading = false;
  String? _selectedOfficerId;
  String? _selectedOfficerName;


  @override
  void initState() {
    super.initState();
    if (widget.mobile != null && widget.mobile!.isNotEmpty) {
      _mobileCtrl.text = widget.mobile!;
    }
    _loadContent();
    _loadFieldOfficers();

  }

  Future<void> _loadFieldOfficers() async {
    setState(() => _officersLoading = true);
    final p = Provider.of<PostApiProvider>(context, listen: false);
    final list = await p.fetchFieldOfficersApi(context);
    if (!mounted) return;
    setState(() {
      _officers = list;
      _officersLoading = false;
    });
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
      _retailerNameCtrl, _bizNameCtrl,
      _gstCtrl, _mobileCtrl,
    ]) { c.dispose(); }
    super.dispose();
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submitRetailer() async {
    final name    = _retailerNameCtrl.text.trim();
    final biz     = _bizNameCtrl.text.trim();
    final mobile  = _mobileCtrl.text.trim();

    if (name.isEmpty)    { _snack('Please enter your name'); return; }
    if (biz.isEmpty)     { _snack('Business name is required'); return; }
    if (mobile.length != 10) { _snack('Valid phone number required'); return; }
    if (!_isTermsAgreed) { _snack('Please agree to Terms and Privacy Policy'); return; }

    final p = Provider.of<PostApiProvider>(context, listen: false);
    final ok = await p.retailerSignupApi(
      context,
      businessName: biz,
      retailerName: name,
      description:  '',
      email:        '',
      phoneNumber:  mobile,
      address:      '',
      landmark:     _gstCtrl.text.trim().isNotEmpty
                      ? 'GST: ${_gstCtrl.text.trim()}' : '',
      profileImage: null,
      onboardedByOfficerId: _selectedOfficerId,
    );
    if (ok) Get.offAll(() => CustomBottomNav(userType: UserType.retailer));
  }

  // ── 3-line menu → "who helped you download the app?" picker ────────────────
  void _openFieldOfficerPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.7;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    'Who helped you download the app?',
                    style: TextStyle(
                      color: AppColor.blackColor,
                      fontFamily: AppFont.fontFamily,
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Optional — pick the field officer who onboarded you. '
                      'This can only be set once.',
                      style: TextStyle(
                        color: AppColor.textColorTwo,
                        fontFamily: AppFont.fontFamily,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: _officersLoading
                      ? const Padding(
                          padding: EdgeInsets.all(28),
                          child: CircularProgressIndicator(
                              color: AppColor.themeColor),
                        )
                      : _officers.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  const Text(
                                    "Couldn't load the list.",
                                    style: TextStyle(
                                      color: AppColor.textColorTwo,
                                      fontFamily: AppFont.fontFamily,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _loadFieldOfficers().then((_) {
                                        if (mounted) _openFieldOfficerPicker();
                                      });
                                    },
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            )
                          : ListView(
                              shrinkWrap: true,
                              children: [
                                RadioListTile<String?>(
                                  value: null,
                                  groupValue: _selectedOfficerId,
                                  activeColor: AppColor.primaryColor,
                                  title: const Text(
                                    'None / I signed up on my own',
                                    style: TextStyle(
                                      fontFamily: AppFont.fontFamily,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  onChanged: (_) {
                                    setState(() {
                                      _selectedOfficerId = null;
                                      _selectedOfficerName = null;
                                    });
                                    Navigator.pop(ctx);
                                  },
                                ),
                                ..._officers.map((o) {
                                  final id = o['_id']?.toString();
                                  final name =
                                      (o['name'] ?? '').toString();
                                  return RadioListTile<String?>(
                                    value: id,
                                    groupValue: _selectedOfficerId,
                                    activeColor: AppColor.primaryColor,
                                    title: Text(
                                      name,
                                      style: const TextStyle(
                                        fontFamily: AppFont.fontFamily,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                    onChanged: (val) {
                                      setState(() {
                                        _selectedOfficerId = val;
                                        _selectedOfficerName = name;
                                      });
                                      Navigator.pop(ctx);
                                    },
                                  );
                                }),
                                const SizedBox(height: 8),
                              ],
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
            child: Stack(
              children: [
                SingleChildScrollView(
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

                    if (_selectedOfficerId != null) ...[
                      SizedBox(height: size.height * 0.015),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColor.primaryColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_pin_circle_outlined,
                                  size: 16, color: AppColor.primaryColor),
                              const SizedBox(width: 6),
                              Text(
                                'Field officer: ${_selectedOfficerName ?? ''}',
                                style: const TextStyle(
                                  color: AppColor.primaryColor,
                                  fontFamily: AppFont.fontFamily,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

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

                // ── 3-line menu (field officer credit) ────────────────────
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    tooltip: 'Field officer',
                    icon: const Icon(Icons.menu, color: AppColor.blackColor),
                    onPressed: _openFieldOfficerPicker,
                  ),
                ),
              ],
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

      _label('GST Number (optional)'),
      _field(ctrl: _gstCtrl, hint: 'Enter GST number if applicable',
          kbt: TextInputType.text),
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
