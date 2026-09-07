import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';

// Owner-facing entry point for Business Mode (Stage 2a) — lets a retailer
// register their own company as a business account. This only creates a
// pending_approval request; it has zero effect on the requester's normal
// app experience until an internal admin approves it
// (adminBusinessController.approveBusinessAccount).
class RegisterBusinessScreen extends StatefulWidget {
  const RegisterBusinessScreen({super.key});

  @override
  State<RegisterBusinessScreen> createState() => _RegisterBusinessScreenState();
}

class _RegisterBusinessScreenState extends State<RegisterBusinessScreen> {
  final _businessNameCtrl = TextEditingController();
  final _gstCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _gstCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final businessName = _businessNameCtrl.text.trim();
    final gstNumber = _gstCtrl.text.trim().toUpperCase();

    if (businessName.isEmpty) {
      SnackBarToastMessage.showSnackBar(context, 'Enter your business name');
      return;
    }
    if (gstNumber.isEmpty) {
      SnackBarToastMessage.showSnackBar(context, 'Enter your GST number');
      return;
    }

    final provider = Provider.of<PostApiProvider>(context, listen: false);
    setState(() => _submitting = true);
    final res = await provider.registerBusinessAccountApi(
      context,
      businessName: businessName,
      gstNumber: gstNumber,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (res != null && res['success'] == true) {
      SnackBarToastMessage.showSnackBar(context, 'Request submitted — awaiting approval');
      Navigator.pop(context, true);
    }
    // On failure (invalid GST format, already-linked, already-requested),
    // the shared error handler already showed the exact backend message.
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
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColor.themeColor, size: 20),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: const Text(
            'Register My Business',
            style: TextStyle(
              fontFamily: AppFont.fontFamily,
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: AppColor.blackColor,
            ),
          ),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.07),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: size.height * 0.03),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColor.themeColor.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColor.themeColor.withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColor.themeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.domain_add_rounded, color: AppColor.themeColor, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Get one shared account for your whole team — our team verifies your GST details before it goes live.',
                        style: TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontSize: 13,
                          color: AppColor.blackColor.withOpacity(0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: size.height * 0.035),
              _label('Business Name'),
              _field(ctrl: _businessNameCtrl, hint: 'Enter your business name'),
              SizedBox(height: size.height * 0.022),
              _label('GST Number'),
              _field(ctrl: _gstCtrl, hint: 'e.g. 22AAAAA0000A1Z5'),
              SizedBox(height: size.height * 0.05),
              _submitting
                  ? const Center(child: CircularProgressIndicator(color: AppColor.themeColor))
                  : AppButton(text: 'Submit for Approval', onPress: _submit),
              SizedBox(height: size.height * 0.03),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
              fontFamily: AppFont.fontFamily, fontSize: 13, fontWeight: FontWeight.w600, color: AppColor.blackColor),
        ),
      );

  Widget _field({required TextEditingController ctrl, required String hint}) => TextField(
        controller: ctrl,
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColor.hintTextColor, fontSize: 14, fontFamily: AppFont.fontFamily),
          filled: true,
          fillColor: AppColor.textFiledColor,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: AppColor.themeColor, width: 1.5),
          ),
        ),
      );
}
