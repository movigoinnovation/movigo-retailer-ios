import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:movigo/view/customer_screen/account_screen/privacy_policy_screen.dart';
import 'package:movigo/view/customer_screen/account_screen/terms_and_conditions_screen.dart';
import 'package:movigo/view/customer_screen/onboarding/login_screen.dart';
import 'package:movigo/view/retailer_screen/retailer_account_screen/profile_screen.dart';
import 'package:movigo/view/retailer_screen/retailer_account_screen/business_profile_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_config_provider.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'about_us_screen.dart';
import 'help_and_support_screen.dart';

class RAccountScreen extends StatefulWidget {
  const RAccountScreen({super.key});

  @override
  State<RAccountScreen> createState() => _RAccountScreenState();
}

class _RAccountScreenState extends State<RAccountScreen> {
  bool _isLoggingOut = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop || _isLoggingOut) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const CustomBottomNav(
              userType: UserType.retailer,
              initialIndex: 0,
            ),
          ),
        );
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.white,
          scrolledUnderElevation: 0,
          toolbarHeight: size.height * 0.12,
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: Padding(
            padding: EdgeInsets.only(top: size.height * 0.015),
            child: Text(
              AppLanguage.accountText[language],
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                fontFamily: AppFont.fontFamily,
                color: AppColor.blackColor,
              ),
            ),
          ),
        ),
        body: Container(
          height: size.height,
          width: size.width,
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
              child: Column(
                children: [
                  SizedBox(height: size.height * 0.015),

                  // ── Profile Card ─────────────────────────────────────
                  Consumer<UserController>(
                    builder: (_, user, __) {
                      final bizName = user.getBusinessName.isNotEmpty
                          ? user.getBusinessName : 'My Business';
                      final ownerName = user.getUserName.isNotEmpty
                          ? user.getUserName : 'Business Owner';
                      final img = user.getUserImage;

                      return Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: size.width * 0.04,
                          vertical: size.height * 0.022,
                        ),
                        decoration: BoxDecoration(
                          color: AppColor.themeColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            // Avatar
                            Container(
                              width: 56, height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withOpacity(0.6), width: 2),
                              ),
                              child: ClipOval(
                                child: img.isNotEmpty
                                  ? Image.network(
                                      '${AppConfigProvider.imgUrl}$img',
                                      fit: BoxFit.cover,
                                      cacheWidth: 200,
                                      errorBuilder: (_, __, ___) =>
                                          Image.asset(AppImage.storeDoorIcon, fit: BoxFit.cover))
                                  : Image.asset(AppImage.storeDoorIcon, fit: BoxFit.cover),
                              ),
                            ),
                            SizedBox(width: size.width * 0.04),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(bizName,
                                    style: const TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.w700,
                                      fontFamily: AppFont.fontFamily, color: Colors.white)),
                                  const SizedBox(height: 3),
                                  Text(ownerName,
                                    style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w400,
                                      fontFamily: AppFont.fontFamily,
                                      color: Colors.white70)),
                                  const SizedBox(height: 3),
                                  if (user.getUserMobile.isNotEmpty)
                                    Text('+91 ${user.getUserMobile}',
                                      style: const TextStyle(
                                        fontSize: 12, fontFamily: AppFont.fontFamily,
                                        color: Colors.white60)),
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: () => Get.to(() => const RProfileScreen()),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.edit_rounded,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  SizedBox(height: size.height * 0.04),

                  // ── Business Profile (Retailer only) ────────────────────
                  _menuItem(
                    context,
                    icon: AppImage.editAcc,
                    title: 'Business Profile',
                    onTap: () {
                      final userCtrl = Provider.of<UserController>(context, listen: false);
                      Get.to(() => BusinessProfileScreen(userData: userCtrl.getAllData));
                    },
                  ),
                  SizedBox(height: size.height * 0.01),

                  _menuItem(
                    context,
                    icon: AppImage.termsimage,
                    title: AppLanguage.termsConditionText[language],
                    onTap: () {
                      Get.to(() => const TermsAndConditionsScreen());
                    },
                  ),
                  SizedBox(height: size.height * 0.01),
                  _menuItem(
                    context,
                    icon: AppImage.privacyimage,
                    title: AppLanguage.privacyPolicyText[language],
                    onTap: () {
                      Get.to(() => const PrivacyPolicyScreen());
                    },
                  ),
                  SizedBox(height: size.height * 0.01),

                  _menuItem(
                    context,
                    icon: AppImage.aboutimage,
                    title: AppLanguage.aboutText[language],
                    onTap: () {
                      Get.to(() => const RAboutUsScreen());
                    },
                  ),
                  SizedBox(height: size.height * 0.01),

                  _menuItem(
                    context,
                    icon: AppImage.helpimage,
                    title: AppLanguage.helpSupoortText[language],
                    onTap: () {
                      Get.to(() => const RHelpAndSupportscreen());
                    },
                  ),
                  SizedBox(height: size.height * 0.01),

                  _menuItem(
                    context,
                    icon: AppImage.rate,
                    title: AppLanguage.rateText[language],
                    onTap: () async {
                      // Don't gate on canLaunchUrl() — on Android 11+ it can
                      // return false without the exact <queries> entry present,
                      // even when the launch itself would succeed. Just attempt it.
                      try {
                        await launchUrl(Uri.parse(AppConstant.appPlayStoreUrl), mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    },
                  ),
                  SizedBox(height: size.height * 0.01),

                  _menuItem(
                    context,
                    icon: AppImage.shareAcc,
                    title: AppLanguage.shareAppText[language],
                    onTap: () {
                      Share.share(
                        'Download the Movigo Retailer App and manage your deliveries easily!\n'
                        '${AppConstant.appPlayStoreUrl}',
                      );
                    },
                  ),
                  SizedBox(height: size.height * 0.01),

                  /// LOGOUT
                  _menuItem(
                    context,
                    icon: AppImage.logoutAcc,
                    title: AppLanguage.logoutText[language],
                    onTap: () {
                      logoutPopup(context);
                    },
                  ),
                  SizedBox(height: size.height * 0.01),

                  /// DELETE ACCOUNT
                  Padding(
                    padding: EdgeInsets.only(bottom: size.height * 0.02),
                    child: InkWell(
                      onTap: () async {
                        final uri = Uri.parse(
                            'https://movigoinnovations.com/delete-account.html');
                        try {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        } catch (_) {
                          if (context.mounted) {
                            SnackBarToastMessage.showSnackBar(
                                context, 'Could not open the delete account page.');
                          }
                        }
                      },
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: size.height * 0.030,
                            color: Colors.red.shade600,
                          ),
                          SizedBox(width: size.width * 0.04),
                          Expanded(
                            child: Text(
                              'Delete Account',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                fontFamily: AppFont.fontFamily,
                                color: Colors.red.shade600,
                              ),
                            ),
                          ),
                          Image.asset(
                            AppImage.arrowAcc,
                            height: 16,
                            width: 16,
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: size.height * 0.04),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuItem(
    BuildContext context, {
    required String icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final size = MediaQuery.of(context).size;

    return Padding(
      padding: EdgeInsets.only(bottom: size.height * 0.02),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Image.asset(
              icon,
              height: size.height * 0.030,
              width: size.height * 0.030,
              color: AppColor.blackColor,
            ),
            SizedBox(width: size.width * 0.04),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontFamily: AppFont.fontFamily,
                  color: AppColor.blackColor,
                ),
              ),
            ),
            Image.asset(
              AppImage.arrowAcc,
              height: 16,
              width: 16,
            )
          ],
        ),
      ),
    );
  }

  void logoutPopup(BuildContext context) {
    final size = MediaQuery.of(context).size;

    showDialog(
      context: context,
      barrierDismissible: !_isLoggingOut,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (context) {
        final rootContext = this.context;
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: size.width * 0.88,
              padding: EdgeInsets.symmetric(
                horizontal: size.width * 0.05,
                vertical: size.height * 0.029,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppLanguage.areYouSureLogoutText[language],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18.5,
                      fontWeight: FontWeight.w500,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.blackColor,
                    ),
                  ),
                  SizedBox(height: size.height * 0.012),
                  Text(
                    AppLanguage.logoutDescText[language],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12.4,
                      fontWeight: FontWeight.w400,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.hinttextColor,
                      // height: 1.4,
                    ),
                  ),
                  SizedBox(height: size.height * 0.040),
                  Row(
                    children: [
                      Expanded(
                        child: Consumer<PostApiProvider>(
                          builder: (context, postApi, _) {
                            return GestureDetector(
                              onTap: postApi.secondaryLoading
                                  ? null
                                  : () => Navigator.pop(context),
                              child: Container(
                                height: size.height * 0.06,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border:
                                      Border.all(color: AppColor.primaryColor),
                                ),
                                child: Center(
                                  child: Text(
                                    AppLanguage.cancelText[language],
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: AppFont.fontFamily,
                                      color: AppColor.primaryColor,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(width: size.width * 0.04),
                      Expanded(
                        child: Consumer<PostApiProvider>(
                          builder: (context, postApi, _) {
                            return GestureDetector(
                              onTap: postApi.secondaryLoading
                                  ? null
                                  : () async {
                                      final dialogNavigator =
                                          Navigator.of(context);
                                      final rootNavigator =
                                          Navigator.of(rootContext);
                                      final messenger =
                                          ScaffoldMessenger.of(rootContext);

                                      if (mounted) {
                                        setState(() {
                                          _isLoggingOut = true;
                                        });
                                      }

                                      final result =
                                          await postApi.logOutApiCalling(
                                        rootContext,
                                      );

                                      if (!mounted) return;

                                      if (result != null) {
                                        dialogNavigator.pop();

                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(result),
                                            duration:
                                                const Duration(seconds: 2),
                                            backgroundColor:
                                                AppColor.primaryColor,
                                          ),
                                        );

                                        await Future.delayed(
                                          const Duration(milliseconds: 500),
                                        );

                                        if (!mounted) return;

                                        rootNavigator.pushAndRemoveUntil(
                                          MaterialPageRoute(
                                            builder: (_) => const LoginScreen(userType: 'Retailer'),
                                          ),
                                          (route) => false,
                                        );
                                      }

                                      if (mounted) {
                                        setState(() {
                                          _isLoggingOut = false;
                                        });
                                      }
                                    },
                              child: Container(
                                height: size.height * 0.06,
                                decoration: BoxDecoration(
                                  color: AppColor.primaryColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: postApi.secondaryLoading
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          AppLanguage.logoutText[language],
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: AppFont.fontFamily,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: size.height * 0.012),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
