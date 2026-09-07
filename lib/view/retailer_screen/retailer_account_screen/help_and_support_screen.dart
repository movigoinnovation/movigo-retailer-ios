// help_and_support_screen.dart — Retailer
// Fix 4: Shows helpline numbers from backend (admin-controlled)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:movigo/Controller/helpline_controller.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_header.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/utilities/common_text_field.dart';

class RHelpAndSupportscreen extends StatefulWidget {
  // Booking-tracking screens (accept/arrived/pickup) only want the helpline
  // numbers to call — not the full name/email/description complaint form,
  // which stays for the general Account > Help & Support entry point.
  final bool showComplaintForm;

  const RHelpAndSupportscreen({super.key, this.showComplaintForm = true});
  @override
  State<RHelpAndSupportscreen> createState() => _RHelpAndSupportscreenState();
}

class _RHelpAndSupportscreenState extends State<RHelpAndSupportscreen> {
  final TextEditingController fullNameController    = TextEditingController();
  final TextEditingController emailController       = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uc = Provider.of<UserController>(context, listen: false);
      fullNameController.text = uc.getUserName;
      emailController.text    = uc.getUserEmail;
      Provider.of<HelplineController>(context, listen: false).getHelplines(context);
    });
  }

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}');
    try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark));

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
          child: CommonAppBar(title: AppLanguage.helpSupoortText[language], onBack: () => Navigator.of(context).maybePop()),
        ),
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(height: size.height * 0.02),
            if (widget.showComplaintForm) ...[
              _label(AppLanguage.fullNameText[language], size),
              CommonTextField(controller: fullNameController, hintText: AppLanguage.enterFullNText[language]),
              SizedBox(height: size.height * 0.025),
              _label(AppLanguage.emailText[language], size),
              CommonTextField(controller: emailController, hintText: AppLanguage.enterEmailText[language], keyboardType: TextInputType.emailAddress),
              SizedBox(height: size.height * 0.025),
              _label(AppLanguage.descriptionText[language], size),
              CommonTextField(controller: descriptionController, hintText: AppLanguage.writeText[language], isMultiline: true, height: 0.15),
              SizedBox(height: size.height * 0.035),
              Consumer<PostApiProvider>(builder: (ctx, api, _) => api.loading
                ? const Center(child: CircularProgressIndicator(color: AppColor.themeColor))
                : AppButton(text: AppLanguage.sendText[language], onPress: () {
                    if (fullNameController.text.trim().isEmpty) { SnackBarToastMessage.showSnackBar(context, AppLanguage.fullNameMessage[language]); return; }
                    if (descriptionController.text.trim().isEmpty) { SnackBarToastMessage.showSnackBar(context, AppLanguage.descriptionMessage[language]); return; }
                    api.contactUsApiCalling(context, fullNameController.text.trim(), emailController.text.trim().isNotEmpty ? emailController.text.trim() : 'retailer@movigo.com', descriptionController.text.trim());
                  })),
              SizedBox(height: size.height * 0.04),
              Row(children: [
                const Expanded(child: Divider(thickness: 1.5)),
                Padding(padding: EdgeInsets.symmetric(horizontal: size.width * 0.03),
                  child: const Text('Or call Us', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 14, color: AppColor.textColorTwo, fontWeight: FontWeight.w500))),
                const Expanded(child: Divider(thickness: 1.5)),
              ]),
              SizedBox(height: size.height * 0.025),
            ],
            Consumer<HelplineController>(builder: (ctx, hCtrl, _) {
              if (hCtrl.isLoading) return const Center(child: CircularProgressIndicator(color: AppColor.themeColor));
              if (hCtrl.helplineList.isEmpty) return const SizedBox.shrink();
              return Column(children: hCtrl.helplineList.map((item) {
                final title  = item['helpline_label']?.toString()  ?? 'Support';
                final number = item['helpline_number']?.toString() ?? '';
                return GestureDetector(
                  onTap: () { if (number.isNotEmpty) _call(number); },
                  child: Container(
                    margin: EdgeInsets.only(bottom: size.height * 0.012),
                    padding: EdgeInsets.symmetric(horizontal: size.width * 0.04, vertical: size.height * 0.016),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColor.greyColor),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
                    child: Row(children: [
                      Container(padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: AppColor.themeColor.withOpacity(0.1), shape: BoxShape.circle),
                          child: const Icon(Icons.call, color: AppColor.themeColor, size: 20)),
                      SizedBox(width: size.width * 0.04),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 14, fontWeight: FontWeight.w600, color: AppColor.blackColor)),
                        const SizedBox(height: 2),
                        Text(number, style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 14, color: AppColor.themeColor, fontWeight: FontWeight.w600)),
                      ])),
                      const Icon(Icons.chevron_right, color: AppColor.greyColor),
                    ]),
                  ),
                );
              }).toList());
            }),
            SizedBox(height: size.height * 0.04),
          ]),
        )),
      ]),
    );
  }

  Widget _label(String text, Size size) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(padding: EdgeInsets.only(bottom: size.height * 0.008),
      child: Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, fontFamily: AppFont.fontFamily, color: AppColor.nineTextColor))),
  );
}
