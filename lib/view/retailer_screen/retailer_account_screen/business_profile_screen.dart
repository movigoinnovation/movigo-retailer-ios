import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_config_provider.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/app_language.dart';

class BusinessProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const BusinessProfileScreen({super.key, required this.userData});

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  final _businessNameCtrl = TextEditingController();
  final _ownerNameCtrl    = TextEditingController();
  final _gstCtrl          = TextEditingController();
  final _addressCtrl      = TextEditingController();
  bool _fetchingLoc = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.userData;
    _businessNameCtrl.text = (d['business_name'] ?? '').toString();
    _ownerNameCtrl.text    = (d['full_name'] ?? '').toString();
    _addressCtrl.text      = (d['address'] ?? '').toString();
    final lm = (d['landmark'] ?? '').toString();
    _gstCtrl.text = lm.startsWith('GST:') ? lm.replaceFirst('GST:', '').trim() : '';
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose(); _ownerNameCtrl.dispose();
    _gstCtrl.dispose(); _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    setState(() => _fetchingLoc = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        SnackBarToastMessage.showSnackBar(context, 'Location permission denied'); return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final geoUri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${pos.latitude},${pos.longitude}'
        '&key=${AppConstant.googleApiKey}'
        '&language=en',
      );
      final geoResp = await http.get(geoUri).timeout(const Duration(seconds: 6));
      if (geoResp.statusCode == 200) {
        final geoData = jsonDecode(geoResp.body) as Map<String, dynamic>;
        final geoResults = geoData['results'] as List? ?? [];
        if (geoResults.isNotEmpty) {
          final addr = geoResults.first['formatted_address']?.toString() ?? '';
          if (addr.isNotEmpty) setState(() => _addressCtrl.text = addr);
        }
      }
      SnackBarToastMessage.showSnackBar(context, 'Could not fetch location');
    } finally {
      if (mounted) setState(() => _fetchingLoc = false);
    }
  }

  Future<void> _save() async {
    if (_businessNameCtrl.text.trim().isEmpty) {
      SnackBarToastMessage.showSnackBar(context, 'Business name is required'); return;
    }

    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final user = Provider.of<UserController>(context, listen: false);

    setState(() => _saving = true);
    final success = await provider.updateRetailerProfileApi(
      context,
      businessName: _businessNameCtrl.text.trim(),
      fullName:     _ownerNameCtrl.text.trim().isNotEmpty
          ? _ownerNameCtrl.text.trim() : (user.getUserName),
      email:        user.getUserEmail,
      phoneNumber:  user.getUserMobile,
      address:      _addressCtrl.text.trim(),
      landmark:     _gstCtrl.text.trim().isNotEmpty
          ? 'GST: ${_gstCtrl.text.trim()}' : '',
      description:  user.getDescription,
    );
    setState(() => _saving = false);

    if (success) {
      await user.getUserDetails();
      if (mounted) {
        SnackBarToastMessage.showSnackBar(context, 'Business profile updated!');
        Navigator.pop(context);
      }
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
          title: const Text('Business Profile',
            style: TextStyle(fontFamily: AppFont.fontFamily,
                fontWeight: FontWeight.w700, fontSize: 17,
                color: AppColor.blackColor)),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.07),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: size.height * 0.025),

              // Business header card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColor.themeColor.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColor.themeColor.withOpacity(0.15)),
                ),
                child: Row(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: AppColor.themeColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.storefront_rounded,
                        color: AppColor.themeColor, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Consumer<UserController>(
                        builder: (_, u, __) => Text(
                          u.getBusinessName.isNotEmpty ? u.getBusinessName : 'Your Business',
                          style: const TextStyle(fontFamily: AppFont.fontFamily,
                              fontWeight: FontWeight.w700, fontSize: 15,
                              color: AppColor.blackColor),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text('Business Account',
                        style: TextStyle(fontFamily: AppFont.fontFamily,
                            fontSize: 12, color: AppColor.textColorTwo)),
                    ],
                  )),
                ]),
              ),

              SizedBox(height: size.height * 0.03),

              _label('Business Name *'),
              _field(ctrl: _businessNameCtrl, hint: 'Enter business name'),
              _gap(size),

              _label('Owner Name'),
              _field(ctrl: _ownerNameCtrl, hint: 'Enter owner name'),
              _gap(size),

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

              _label('GST Number (optional)'),
              _field(ctrl: _gstCtrl, hint: 'Enter GST number if applicable'),

              SizedBox(height: size.height * 0.05),

              _saving
                ? const Center(child: CircularProgressIndicator(color: AppColor.themeColor))
                : AppButton(text: 'Save Business Profile', onPress: _save),

              SizedBox(height: size.height * 0.03),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(
        fontFamily: AppFont.fontFamily, fontSize: 13,
        fontWeight: FontWeight.w600, color: AppColor.blackColor)),
  );

  Widget _field({required TextEditingController ctrl, required String hint,
      bool readOnly = false}) =>
    TextField(
      controller: ctrl, readOnly: readOnly,
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
