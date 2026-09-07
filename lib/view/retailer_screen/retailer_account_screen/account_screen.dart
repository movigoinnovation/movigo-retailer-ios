import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:movigo/view/customer_screen/account_screen/privacy_policy_screen.dart';
import 'package:movigo/view/customer_screen/account_screen/terms_and_conditions_screen.dart';
import 'package:movigo/view/customer_screen/onboarding/login_screen.dart';
import 'package:movigo/view/retailer_screen/retailer_account_screen/profile_screen.dart';
import 'package:movigo/view/retailer_screen/retailer_account_screen/business_profile_screen.dart';
import 'package:movigo/view/retailer_screen/retailer_account_screen/join_business_screen.dart';
import 'package:movigo/view/retailer_screen/retailer_account_screen/register_business_screen.dart';
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

  // ── Business Mode (Stage 2b/2c) ─────────────────────────────────────────
  // Fetched fresh on every screen load rather than trusted from the cached
  // user_details blob — a business name/status is only known server-side
  // (Retailer.businessAccountId points at it), and this indicator must stay
  // correct after a suspend/leave that happened elsewhere (owner panel,
  // admin action) between app sessions.
  Map<String, dynamic>? _businessStatus;
  bool _loadingBusinessStatus = true;

  String _versionName = '';
  String _versionCode = '';

  @override
  void initState() {
    super.initState();
    _fetchBusinessStatus();
    _fetchAppVersion();
  }

  Future<void> _fetchAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _versionName = info.version;
          _versionCode = info.buildNumber;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchBusinessStatus() async {
    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final res = await provider.getBusinessStatusApi(context);
    if (!mounted) return;
    setState(() {
      _businessStatus = (res != null && res['success'] == true) ? res['data'] as Map<String, dynamic>? : null;
      _loadingBusinessStatus = false;
    });
  }

  Future<void> _openJoinBusiness() async {
    final linked = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const JoinBusinessScreen()),
    );
    if (linked == true) _fetchBusinessStatus();
  }

  Future<void> _openRegisterBusiness() async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const RegisterBusinessScreen()),
    );
    if (submitted == true) _fetchBusinessStatus();
  }

  Future<void> _confirmLeaveBusiness(String businessName) async {
    final size = MediaQuery.of(context).size;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (dialogContext) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: size.width * 0.88,
            padding: EdgeInsets.symmetric(horizontal: size.width * 0.05, vertical: size.height * 0.029),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Leave $businessName?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18.5, fontWeight: FontWeight.w500, fontFamily: AppFont.fontFamily, color: AppColor.blackColor),
                ),
                SizedBox(height: size.height * 0.012),
                const Text(
                  'You will stop getting business rates and go back to normal pricing on your next booking. No approval is needed from the business owner.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.4, fontWeight: FontWeight.w400, fontFamily: AppFont.fontFamily, color: AppColor.hinttextColor),
                ),
                SizedBox(height: size.height * 0.040),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(dialogContext, false),
                        child: Container(
                          height: size.height * 0.06,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColor.primaryColor),
                          ),
                          child: const Center(
                            child: Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, fontFamily: AppFont.fontFamily, color: AppColor.primaryColor)),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: size.width * 0.04),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(dialogContext, true),
                        child: Container(
                          height: size.height * 0.06,
                          decoration: BoxDecoration(color: AppColor.primaryColor, borderRadius: BorderRadius.circular(10)),
                          child: const Center(
                            child: Text('Leave', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, fontFamily: AppFont.fontFamily, color: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final res = await provider.leaveBusinessApi(context);
    if (!mounted) return;
    if (res != null && res['success'] == true) {
      SnackBarToastMessage.showSnackBar(context, 'You have left the business');
      _fetchBusinessStatus();
    }
  }

  Widget _businessStatusSection(Size size) {
    if (_loadingBusinessStatus) return const SizedBox.shrink();

    final linked = _businessStatus?['linked'] == true;
    if (!linked) {
      final owned = _businessStatus?['ownedAccount'] as Map<String, dynamic>?;
      if (owned != null && owned['status'] == 'pending_approval') {
        return Padding(
          padding: EdgeInsets.only(bottom: size.height * 0.025),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF9C3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                const Icon(Icons.hourglass_top_rounded, color: Color(0xFF854D0E), size: 22),
                SizedBox(width: size.width * 0.03),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${owned['businessName']} — awaiting approval',
                          style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF854D0E))),
                      const SizedBox(height: 2),
                      const Text('Our team is reviewing your GST details.',
                          style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11, color: Color(0xFF854D0E))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }

      final rejectedReason = (owned != null && owned['status'] == 'rejected') ? (owned['rejectionReason']?.toString() ?? '') : null;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rejectedReason != null)
            Padding(
              padding: EdgeInsets.only(bottom: size.height * 0.015),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFF991B1B), size: 22),
                    SizedBox(width: size.width * 0.03),
                    Expanded(
                      child: Text(
                        rejectedReason.isNotEmpty ? 'Registration rejected: $rejectedReason' : 'Your business registration was rejected.',
                        style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, color: Color(0xFF991B1B)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(bottom: size.height * 0.01),
            child: InkWell(
              onTap: _openJoinBusiness,
              child: Row(
                children: [
                  const Icon(Icons.groups_2_rounded, size: 22, color: AppColor.blackColor),
                  SizedBox(width: size.width * 0.04),
                  const Expanded(
                    child: Text(
                      'Join a Business',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, fontFamily: AppFont.fontFamily, color: AppColor.blackColor),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 20, color: AppColor.blackColor),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: size.height * 0.01),
            child: InkWell(
              onTap: _openRegisterBusiness,
              child: Row(
                children: [
                  const Icon(Icons.domain_add_rounded, size: 22, color: AppColor.blackColor),
                  SizedBox(width: size.width * 0.04),
                  const Expanded(
                    child: Text(
                      'Register My Business',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, fontFamily: AppFont.fontFamily, color: AppColor.blackColor),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 20, color: AppColor.blackColor),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final businessName = (_businessStatus?['businessName'] ?? 'your business').toString();
    return Padding(
      padding: EdgeInsets.only(bottom: size.height * 0.025),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColor.themeColor.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColor.themeColor.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColor.themeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.groups_2_rounded, color: AppColor.themeColor, size: 22),
            ),
            SizedBox(width: size.width * 0.03),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Linked to $businessName',
                      style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 13, color: AppColor.blackColor)),
                  const SizedBox(height: 2),
                  const Text('Your bookings now use business rates',
                      style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11, color: AppColor.textColorTwo)),
                ],
              ),
            ),
            InkWell(
              onTap: () => _confirmLeaveBusiness(businessName),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text('Leave', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red)),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

                  SizedBox(height: size.height * 0.03),

                  // ── Business Mode: linked-to-business indicator / join entry point ──
                  _businessStatusSection(size),

                  SizedBox(height: size.height * 0.01),

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

                  if (_versionName.isNotEmpty) ...[
                    SizedBox(height: size.height * 0.02),
                    Center(
                      child: Text(
                        'Version $_versionName (Build $_versionCode)',
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: AppFont.fontFamily,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],

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
