import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';

// Employee-facing entry point for Business Mode (Stage 2b) — lets a retailer
// who isn't yet part of a business redeem a one-time code their business
// owner shared with them. Everything else (rate/discount/wallet application)
// is handled server-side once businessAccountId is set; this screen only
// needs to get that code redeemed and reflect the result.
class JoinBusinessScreen extends StatefulWidget {
  const JoinBusinessScreen({super.key});

  @override
  State<JoinBusinessScreen> createState() => _JoinBusinessScreenState();
}

class _JoinBusinessScreenState extends State<JoinBusinessScreen> {
  final _codeCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      SnackBarToastMessage.showSnackBar(context, 'Enter the code your business owner shared with you');
      return;
    }

    final provider = Provider.of<PostApiProvider>(context, listen: false);
    setState(() => _submitting = true);
    final res = await provider.redeemBusinessLinkCodeApi(context, code: code);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (res != null && res['success'] == true) {
      final businessName = (res['data']?['businessName'] ?? '').toString();
      SnackBarToastMessage.showSnackBar(
        context,
        businessName.isNotEmpty ? 'Linked to $businessName' : 'Successfully linked to your business',
      );
      // Signal the caller (profile screen) to refresh its business-status card.
      Navigator.pop(context, true);
    }
    // On failure, postJsonData's shared error handler already showed the
    // exact backend message (invalid / already used / expired / already
    // linked) via SnackBarToastMessage — nothing further to do here.
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
            'Join a Business',
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
                      child: const Icon(Icons.groups_2_rounded, color: AppColor.themeColor, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ask your business owner for the invite code and enter it below to join their team.',
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
              const Text(
                'Invite Code',
                style: TextStyle(
                  fontFamily: AppFont.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColor.blackColor,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 16, letterSpacing: 1.5),
                decoration: InputDecoration(
                  hintText: 'e.g. MVGO-AB12',
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
              ),
              SizedBox(height: size.height * 0.05),
              _submitting
                  ? const Center(child: CircularProgressIndicator(color: AppColor.themeColor))
                  : AppButton(text: 'Join Business', onPress: _submit),
              SizedBox(height: size.height * 0.03),
            ],
          ),
        ),
      ),
    );
  }
}
