import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:movigo/utilities/app_config_provider.dart';
import 'package:movigo/view/customer_screen/account_screen/profile_screen.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/contentService.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/helper/contentScreen.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:movigo/Provider/app_provider/theme_provider.dart';
import 'package:movigo/view/retailer_screen/retailer_account_screen/profile_screen.dart';
import 'package:movigo/view/customer_screen/onboarding/login_screen.dart';
import 'help_and_support_screen.dart';
import 'package:movigo/view/customer_screen/coins/coin_wallet_screen.dart';
import 'package:movigo/view/retailer_screen/retailer_account_screen/join_business_screen.dart';
import 'package:movigo/view/retailer_screen/retailer_account_screen/register_business_screen.dart';
import 'package:movigo/view/retailer_screen/retailer_account_screen/enterprise_mode_screen.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  String userType = "";
  bool _isLoggingOut = false;
  bool _isLoading = true;
  String aboutustype = '';
  String privacypolicytype = '';
  String termsandconditionstype = '';
  String rateappurl = '';
  String shareWith = '';

  // ── Business Mode (Stage 2b/2c) — retailer-only, fetched fresh on every
  // load (never trusted from cached user_details) so it stays correct after
  // a suspend/leave that happened elsewhere between app sessions.
  Map<String, dynamic>? _businessStatus;
  bool _loadingBusinessStatus = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _loadUserData();
    loadContentData();
    _fetchBusinessStatus();
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
                  style: TextStyle(fontSize: 12.4, fontWeight: FontWeight.w400, fontFamily: AppFont.fontFamily, color: AppColor.hintTextColor),
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
                            border: Border.all(color: AppColor.themeColor),
                          ),
                          child: const Center(
                            child: Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, fontFamily: AppFont.fontFamily, color: AppColor.themeColor)),
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
                          decoration: BoxDecoration(color: AppColor.themeColor, borderRadius: BorderRadius.circular(10)),
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
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
          child: Container(
            width: double.infinity,
            margin: EdgeInsets.only(bottom: size.height * 0.02),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF9C3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                const Icon(Icons.hourglass_top_rounded, color: Color(0xFF854D0E), size: 22),
                const SizedBox(width: 12),
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

      return Padding(
        padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rejectedReason != null)
              Container(
                width: double.infinity,
                margin: EdgeInsets.only(bottom: size.height * 0.015),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFF991B1B), size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        rejectedReason.isNotEmpty ? 'Registration rejected: $rejectedReason' : 'Your business registration was rejected.',
                        style: const TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12, color: Color(0xFF991B1B)),
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              margin: EdgeInsets.only(bottom: size.height * 0.02),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEEF0F3)),
              ),
              child: Column(
                children: [
                  InkWell(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    onTap: _openJoinBusiness,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: AppColor.themeColor.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.groups_2_rounded, size: 18, color: AppColor.themeColor),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text('Join a Business',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily, color: AppColor.blackColor)),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColor.hintTextColor, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, indent: 56, color: Color(0xFFF1F2F5)),
                  InkWell(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                    onTap: _openRegisterBusiness,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: AppColor.themeColor.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.domain_add_rounded, size: 18, color: AppColor.themeColor),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text('Register My Business',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily, color: AppColor.blackColor)),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColor.hintTextColor, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final businessName = (_businessStatus?['businessName'] ?? 'your business').toString();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.only(bottom: size.height * 0.02),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColor.themeColor.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Linked to $businessName',
                      style: const TextStyle(fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 13, color: AppColor.blackColor)),
                  const SizedBox(height: 2),
                  const Text('Your bookings now use business rates',
                      style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 11, color: AppColor.hintTextColor)),
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

  Future<void> _loadUserData() async {
    final userController = Provider.of<UserController>(context, listen: false);
    await userController.getUserDetails();

    if (mounted) {
      setState(() {
        userType = userController.getUserType;
        _isLoading = false;
      });
    }

    if (kDebugMode) print("ACCOUNT SCREEN USER TYPE => $userType");
  }

  loadContentData() {
    fetchAllContent((List data) {
      // Collect all values first, then call setState exactly once
      String newAboutus = aboutustype;
      String newPrivacy = privacypolicytype;
      String newTerms = termsandconditionstype;
      String newRateapp = rateappurl;
      String newShareWith = shareWith;

      for (var item in data) {
        if (item['content_type'] == 0) {
          newAboutus = item['content_url'];
        }
        if (item['content_type'] == 1) {
          newPrivacy = item['content_url'];
        }
        if (item['content_type'] == 2) {
          newTerms = item['content_url'];
        }
        if (item['content_type'] == 3 && AppConstant.deviceType == 'ios') {
          newRateapp = item['content'];
        }
        if (item['content_type'] == 4 && AppConstant.deviceType == 'android') {
          newRateapp = item['content'];
        }
        if (item['content_type'] == 5) {
          newShareWith = item['content_url'];
        }
      }

      if (mounted) {
        setState(() {
          aboutustype = newAboutus;
          privacypolicytype = newPrivacy;
          termsandconditionstype = newTerms;
          rateappurl = newRateapp;
          shareWith = newShareWith;
        });
      }
    });
  }

  Future openUrl({
    required String url,
    bool inApp = false,
  }) async {
    if (url.isEmpty) url = AppConstant.appPlayStoreUrl;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    // Don't gate on canLaunchUrl() — on Android 11+ it can return false
    // without the exact <queries> entry present, even when a browser is
    // available and the launch itself would succeed. Just attempt it.
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('openUrl error: $e');
    }
  }

  shareApp(BuildContext context) async {
    final String message = shareWith.isNotEmpty
        ? shareWith
        : (language == 1
            ? 'Movigo App डाउनलोड करें और आज ही डिलीवरी बुक करना शुरू करें 👇\n${AppConstant.appPlayStoreUrl}'
            : 'Download the Movigo App and start booking deliveries today 👇\n${AppConstant.appPlayStoreUrl}');
    await Share.share(message);
  }

  void _handleBack() {
    Get.offAll(
      () => const CustomBottomNav(
        userType: UserType.retailer,
        initialIndex: 3, // Account tab
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop || _isLoggingOut) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F9),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: size.height * 0.04),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      size.width * 0.05, size.height * 0.02, size.width * 0.05, 0),
                  child: Text(
                    AppLanguage.accountText[language],
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.blackColor,
                    ),
                  ),
                ),
                SizedBox(height: size.height * 0.02),

                // ── Profile hero card ──
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
                  child: Consumer<UserController>(
                    builder: (context, user, _) {
                      final bool isCustomer = userType == 'Customer';

                      final String displayName = isCustomer
                          ? (user.getUserName.isNotEmpty ? user.getUserName : "User")
                          : (user.getBusinessName.isNotEmpty
                              ? user.getBusinessName
                              : "Business");

                      final String subText = isCustomer
                          ? (user.getUserEmail.isNotEmpty
                              ? user.getUserEmail
                              : "user@email.com")
                          : (user.getAddress.isNotEmpty
                              ? user.getAddress
                              : (user.getLandmark.isNotEmpty
                                  ? user.getLandmark
                                  : "Address"));
                      final String image = user.getUserImage;

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF0A3D91), Color(0xFF091932)],
                          ),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(32),
                              child: image.isNotEmpty
                                  ? Image.network(
                                      "${AppConfigProvider.imgUrl}$image",
                                      height: 64,
                                      width: 64,
                                      fit: BoxFit.cover,
                                      cacheWidth: 200,
                                      errorBuilder: (_, __, ___) => Image.asset(
                                        AppImage.userdummyimage,
                                        height: 64,
                                        width: 64,
                                      ),
                                    )
                                  : Image.asset(
                                      AppImage.userdummyimage,
                                      height: 64,
                                      width: 64,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: AppFont.fontFamily,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: AppFont.fontFamily,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                if (userType == 'Customer') {
                                  Get.to(() => ProfileScreen(mobile: user.getUserMobile));
                                }
                                if (userType == 'Retailer') {
                                  Get.to(() => RProfileScreen(mobile: user.getUserMobile));
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.14),
                                  shape: BoxShape.circle,
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
                ),

                SizedBox(height: size.height * 0.025),

                // ── Coins Wallet — Retailer only, highlighted card ──
                if (userType == 'Retailer')
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CoinWalletScreen()),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFFE0A3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: const BoxDecoration(
                                color: Color(0xFFFFECB3),
                                shape: BoxShape.circle,
                              ),
                              child: const Text('🪙', style: TextStyle(fontSize: 18)),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Coins Wallet',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: AppFont.fontFamily,
                                  color: AppColor.blackColor,
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: Color(0xFF9A7B2F), size: 22),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (userType == 'Retailer') SizedBox(height: size.height * 0.025),

                // ── Business Mode: linked-to-business indicator / join+register entry points ──
                if (userType == 'Retailer') _businessStatusSection(size),

                // ── Movigo Enterprise (feature showcase + interest form) ──
                if (userType == 'Retailer')
                  _menuSection(context, title: 'Enterprise', items: [
                    _MenuEntry(
                      icon: AppImage.storeDoorIcon,
                      title: 'Movigo Enterprise',
                      onTap: () => Get.to(() => const EnterpriseModeScreen()),
                    ),
                  ]),
                if (userType == 'Retailer') SizedBox(height: size.height * 0.02),

                // ── Grouped menu sections ──
                _menuSection(context, title: 'Legal', items: [
                  _MenuEntry(
                    icon: AppImage.termsimage,
                    title: AppLanguage.termsConditionText[language],
                    onTap: () => Get.to(() => ContentScreen(
                          contenttype: termsandconditionstype,
                          header: AppLanguage.termsConditionText[language],
                          legalKey: 'terms_conditions',
                        )),
                  ),
                  _MenuEntry(
                    icon: AppImage.privacyimage,
                    title: AppLanguage.privacyPolicyText[language],
                    onTap: () => Get.to(() => ContentScreen(
                          contenttype: privacypolicytype,
                          header: AppLanguage.privacyPolicyText[language],
                          legalKey: 'privacy_policy',
                        )),
                  ),
                  _MenuEntry(
                    icon: AppImage.aboutimage,
                    title: AppLanguage.aboutText[language],
                    onTap: () => Get.to(() => ContentScreen(
                          contenttype: aboutustype,
                          header: AppLanguage.aboutText[language],
                          legalKey: 'about_us',
                        )),
                  ),
                ]),

                SizedBox(height: size.height * 0.02),

                _menuSection(context, title: 'Support', items: [
                  _MenuEntry(
                    icon: AppImage.helpimage,
                    title: AppLanguage.helpSupoortText[language],
                    onTap: () => Get.to(() => HelpAndSupportscreen()),
                  ),
                  _MenuEntry(
                    icon: AppImage.rate,
                    title: AppLanguage.rateText[language],
                    onTap: () => openUrl(url: rateappurl),
                  ),
                  _MenuEntry(
                    icon: AppImage.shareAcc,
                    title: AppLanguage.shareAppText[language],
                    onTap: () => shareApp(context),
                  ),
                ]),

                SizedBox(height: size.height * 0.02),

                // ── Logout — separated, destructive styling ──
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _showLogoutDialog(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFFCDD2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.logout_rounded,
                              color: Color(0xFFE53935), size: 18),
                          const SizedBox(width: 8),
                          Text(
                            AppLanguage.logoutText[language],
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              fontFamily: AppFont.fontFamily,
                              color: Color(0xFFE53935),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuSection(
    BuildContext context, {
    required String title,
    required List<_MenuEntry> items,
  }) {
    final size = MediaQuery.of(context).size;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: AppFont.fontFamily,
                color: AppColor.hintTextColor,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEEF0F3)),
            ),
            child: Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  _menuRow(items[i]),
                  if (i != items.length - 1)
                    const Divider(height: 1, indent: 56, color: Color(0xFFF1F2F5)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuRow(_MenuEntry entry) {
    return InkWell(
      onTap: entry.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColor.themeColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Image.asset(
                entry.icon,
                height: 18,
                width: 18,
                color: AppColor.themeColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entry.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppFont.fontFamily,
                  color: AppColor.blackColor,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColor.hintTextColor, size: 20),
          ],
        ),
      ),
    );
  }

  void _showThemeSheet(BuildContext context) {
    // Now handled inline via toggle — kept for compatibility but not called
  }

  Widget _themeOption(BuildContext context, ThemeProvider provider, String value, IconData icon, String title, String subtitle) {
    return const SizedBox.shrink();
  }

  void _showLanguageSheet(BuildContext context) {
    // Now handled inline via toggle — kept for compatibility but not called
  }

  void _showLogoutDialog(BuildContext context) {
    final size = MediaQuery.of(context).size;

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(
            horizontal: size.width * 0.06,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: size.width * 0.05,
                vertical: size.height * 0.03,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppLanguage.areYouSureLogoutText[language],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppFont.fontFamily,
                      color: AppColor.blackColor,
                    ),
                  ),
                  SizedBox(height: size.height * 0.015),
                  Text(
                    AppLanguage.logoutDescText[language],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      fontFamily: AppFont.fontFamily,
                      color: Color(0xff8A8A8A),
                    ),
                  ),
                  SizedBox(height: size.height * 0.05),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => Get.back(),
                          child: Container(
                            height: size.height * 0.055,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColor.themeColor,
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                AppLanguage.cancelText[language],
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: AppFont.fontFamily,
                                  color: AppColor.themeColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: size.width * 0.04),
                      Expanded(
                        child: Consumer<PostApiProvider>(
                          builder: (context, postApi, _) {
                            return InkWell(
                              onTap: postApi.secondaryLoading
                                  ? null
                                  : () async {
                                      // ✅ Capture the root context BEFORE closing dialog
                                      final rootContext = this.context;

                                      // Close dialog
                                      // Navigator.of(context).pop();

                                      // Set logging out state
                                      if (mounted) {
                                        setState(() {
                                          _isLoggingOut = true;
                                        });
                                      }

                                      // Call logout and get result
                                      final result = await postApi
                                          .logOutApiCalling(rootContext);

                                      // Only proceed if logout was successful
                                      if (result != null && mounted) {
                                        // Show success message using root context
                                        ScaffoldMessenger.of(rootContext)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(result),
                                            duration:
                                                const Duration(seconds: 2),
                                            backgroundColor:
                                                AppColor.themeColor,
                                          ),
                                        );

                                        // Wait for snackbar to show
                                        await Future.delayed(
                                            const Duration(milliseconds: 500));

                                        // Navigate to login using root context
                                        if (mounted) {
                                          Navigator.of(rootContext)
                                              .pushAndRemoveUntil(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const LoginScreen(userType: 'Customer'),
                                            ),
                                            (route) => false,
                                          );
                                        }
                                      }

                                      // Reset loading state if still mounted
                                      if (mounted) {
                                        setState(() {
                                          _isLoggingOut = false;
                                        });
                                      }
                                    },
                              child: Container(
                                height: size.height * 0.055,
                                decoration: BoxDecoration(
                                  color: AppColor.themeColor,
                                  borderRadius: BorderRadius.circular(16),
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
                                            fontSize: 16,
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }

//
}

class _MenuEntry {
  final String icon;
  final String title;
  final VoidCallback onTap;

  const _MenuEntry({required this.icon, required this.title, required this.onTap});
}
