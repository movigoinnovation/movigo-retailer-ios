import 'dart:io';

import 'package:dotted_border/dotted_border.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_config_provider.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';

class RProfileScreen extends StatefulWidget {
  final String? mobile;
  const RProfileScreen({super.key, this.mobile});

  @override
  State<RProfileScreen> createState() => _RProfileScreenState();
}

class _RProfileScreenState extends State<RProfileScreen> {
  final _businessNameCtrl  = TextEditingController();
  final _ownerNameCtrl     = TextEditingController();
  final _emailCtrl         = TextEditingController();
  final _mobileCtrl        = TextEditingController();
  final _addressCtrl       = TextEditingController();
  final _gstCtrl           = TextEditingController();
  final _descCtrl          = TextEditingController();

  File? _profileImage;
  bool _fetchingLoc = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = Provider.of<UserController>(context, listen: false);
      await user.getUserDetails();
      _businessNameCtrl.text = user.getBusinessName;
      _ownerNameCtrl.text    = user.getUserName;
      _emailCtrl.text        = user.getUserEmail;
      _addressCtrl.text      = user.getAddress;
      _gstCtrl.text          = user.getLandmark.startsWith('GST:')
          ? user.getLandmark.replaceFirst('GST:', '').trim()
          : '';
      _descCtrl.text         = user.getDescription;
      if (user.getUserMobile.isNotEmpty) {
        _mobileCtrl.text = '+91 ${user.getUserMobile}';
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose(); _ownerNameCtrl.dispose();
    _emailCtrl.dispose(); _mobileCtrl.dispose();
    _addressCtrl.dispose(); _gstCtrl.dispose(); _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    setState(() => _fetchingLoc = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        SnackBarToastMessage.showSnackBar(context, 'Location permission denied');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${pos.latitude},${pos.longitude}'
        '&key=${AppConstant.googleApiKey}'
        '&language=en',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final results = data['results'] as List? ?? [];
        if (results.isNotEmpty) {
          final addr = results.first['formatted_address']?.toString() ?? '';
          if (addr.isNotEmpty) setState(() => _addressCtrl.text = addr);
        }
      }
    } catch (_) {
      SnackBarToastMessage.showSnackBar(context, 'Could not fetch location');
    } finally {
      if (mounted) setState(() => _fetchingLoc = false);
    }
  }

  void _pickImage() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(
              color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          ListTile(
            enabled: false,
            leading: Icon(Icons.camera_alt_rounded, color: AppColor.themeColor.withOpacity(0.4)),
            title: Text('Camera',
                style: TextStyle(fontFamily: AppFont.fontFamily, color: Colors.grey.shade400)),
            subtitle: const Text('Adding soon', style: TextStyle(fontFamily: AppFont.fontFamily)),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: AppColor.themeColor),
            title: const Text('Gallery', style: TextStyle(fontFamily: AppFont.fontFamily)),
            onTap: () async {
              Navigator.pop(context);
              final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 60);
              if (x != null && mounted) setState(() => _profileImage = File(x.path));
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _submit() async {
    if (_businessNameCtrl.text.trim().isEmpty) {
      SnackBarToastMessage.showSnackBar(context, 'Business name is required'); return;
    }
    if (_ownerNameCtrl.text.trim().isEmpty) {
      SnackBarToastMessage.showSnackBar(context, 'Your name is required'); return;
    }

    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final mobile = _mobileCtrl.text.replaceAll('+91', '').replaceAll(' ', '').trim();

    final success = await provider.updateRetailerProfileApi(
      context,
      businessName: _businessNameCtrl.text.trim(),
      fullName:     _ownerNameCtrl.text.trim(),
      email:        _emailCtrl.text.trim(),
      phoneNumber:  mobile,
      address:      _addressCtrl.text.trim(),
      landmark:     _gstCtrl.text.trim().isNotEmpty ? 'GST: ${_gstCtrl.text.trim()}' : '',
      description:  _descCtrl.text.trim(),
      profileImage: _profileImage != null ? XFile(_profileImage!.path) : null,
    );

    if (success) {
      await Provider.of<UserController>(context, listen: false).getUserDetails();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColor.themeColor, size: 20),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: const Text('Edit Profile',
            style: TextStyle(fontFamily: AppFont.fontFamily,
                fontWeight: FontWeight.w700, fontSize: 17,
                color: AppColor.blackColor)),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.07),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: size.height * 0.03),

              // ── Profile Photo ─────────────────────────────────────────
              GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  children: [
                    DottedBorder(
                      borderType: BorderType.Circle,
                      dashPattern: const [5, 4],
                      color: AppColor.themeColor.withOpacity(0.4),
                      strokeWidth: 1.5,
                      child: Container(
                        width: 96, height: 96,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Color(0xffF2F2F2)),
                        child: ClipOval(
                          child: _profileImage != null
                            ? Image.file(_profileImage!, fit: BoxFit.cover, cacheWidth: 200)
                            : Consumer<UserController>(
                                builder: (_, user, __) {
                                  final img = user.getUserImage;
                                  return img.isNotEmpty
                                    ? Image.network(
                                        '${AppConfigProvider.imgUrl}$img',
                                        fit: BoxFit.cover,
                                        cacheWidth: 200,
                                        errorBuilder: (_, __, ___) =>
                                            Image.asset(AppImage.dummyimage))
                                    : Image.asset(AppImage.dummyimage);
                                }),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 2, right: 2,
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: AppColor.themeColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.edit, color: Colors.white, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: size.height * 0.008),
              GestureDetector(
                onTap: _pickImage,
                child: const Text('Change Photo',
                  style: TextStyle(fontFamily: AppFont.fontFamily,
                      fontSize: 12, color: AppColor.themeColor,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColor.themeColor)),
              ),

              SizedBox(height: size.height * 0.035),

              // ── Business Name ─────────────────────────────────────────
              _label('Business Name *'),
              _field(ctrl: _businessNameCtrl, hint: 'Enter business name'),
              _gap(size),

              // ── Owner Name ────────────────────────────────────────────
              _label('Your Name (Owner) *'),
              _field(ctrl: _ownerNameCtrl, hint: 'Enter your full name'),
              _gap(size),

              // ── Phone ─────────────────────────────────────────────────
              _label('Phone Number'),
              _field(ctrl: _mobileCtrl, hint: '+91 XXXXXXXXXX', readOnly: true),
              _gap(size),

              // ── Email ─────────────────────────────────────────────────
              _label('Email (optional)'),
              _field(ctrl: _emailCtrl, hint: 'Enter email address',
                  kbt: TextInputType.emailAddress),
              _gap(size),

              // ── Business Address ──────────────────────────────────────
              _label('Business Address'),
              _addressField(size),
              SizedBox(height: size.height * 0.005),
              Row(children: [
                const Icon(Icons.info_outline, size: 12, color: AppColor.textColorTwo),
                const SizedBox(width: 4),
                Text('Tap 📍 to auto-fill from GPS',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500,
                        fontFamily: AppFont.fontFamily)),
              ]),
              _gap(size),

              // ── GST ───────────────────────────────────────────────────
              _label('GST Number (optional)'),
              _field(ctrl: _gstCtrl, hint: 'Enter GST number if applicable'),
              _gap(size),

              // ── Description ───────────────────────────────────────────
              _label('About Business (optional)'),
              _multiField(ctrl: _descCtrl, hint: 'Briefly describe your business'),

              SizedBox(height: size.height * 0.05),

              Consumer<PostApiProvider>(
                builder: (_, api, __) => api.loading
                  ? const CircularProgressIndicator(color: AppColor.themeColor)
                  : AppButton(text: 'Save Changes', onPress: _submit),
              ),
              SizedBox(height: size.height * 0.03),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: const TextStyle(
          fontFamily: AppFont.fontFamily, fontSize: 13,
          fontWeight: FontWeight.w600, color: AppColor.blackColor)),
    ),
  );

  Widget _field({
    required TextEditingController ctrl,
    required String hint,
    TextInputType kbt = TextInputType.text,
    bool readOnly = false,
  }) => TextField(
    controller: ctrl, keyboardType: kbt, readOnly: readOnly,
    style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 15),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColor.hintTextColor,
          fontSize: 14, fontFamily: AppFont.fontFamily),
      filled: true, fillColor: AppColor.textFiledColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: AppColor.themeColor, width: 1.5)),
    ),
  );

  Widget _multiField({required TextEditingController ctrl, required String hint}) =>
    TextField(
      controller: ctrl, maxLines: 3, minLines: 2,
      style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColor.hintTextColor,
            fontSize: 14, fontFamily: AppFont.fontFamily),
        filled: true, fillColor: AppColor.textFiledColor,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: AppColor.themeColor, width: 1.5)),
      ),
    );

  Widget _addressField(Size size) => Stack(
    children: [
      TextField(
        controller: _addressCtrl, maxLines: 3, minLines: 2,
        style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Enter address or tap 📍 for GPS',
          hintStyle: const TextStyle(color: AppColor.hintTextColor,
              fontSize: 14, fontFamily: AppFont.fontFamily),
          filled: true, fillColor: AppColor.textFiledColor,
          contentPadding: const EdgeInsets.fromLTRB(16, 14, 52, 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: AppColor.themeColor, width: 1.5)),
        ),
      ),
      Positioned(
        right: 10, top: 10,
        child: GestureDetector(
          onTap: _fetchLocation,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColor.themeColor,
                borderRadius: BorderRadius.circular(8)),
            child: _fetchingLoc
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.my_location, color: Colors.white, size: 16),
          ),
        ),
      ),
    ],
  );

  Widget _gap(Size size) => SizedBox(height: size.height * 0.022);
}
