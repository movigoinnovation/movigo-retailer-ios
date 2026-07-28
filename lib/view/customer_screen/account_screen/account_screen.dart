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
                  SizedBox(height: size.height * 0.001),

                  Consumer<UserController>(
                    builder: (context, user, _) {
                      final bool isCustomer = userType == 'Customer';

                      final String displayName = isCustomer
                          ? (user.getUserName.isNotEmpty
                              ? user.getUserName
                              : "User")
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
                        width: size.width,
                        padding: EdgeInsets.symmetric(
                          horizontal: size.width * 0.04,
                          vertical: size.height * 0.02,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xff0A3D91).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColor.themeColor,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            /// PROFILE IMAGE
                            ClipRRect(
                              borderRadius: BorderRadius.circular(35),
                              child: image.isNotEmpty
                                  ? Image.network(
                                      "${AppConfigProvider.imgUrl}$image",
                                      height: size.height * 0.07,
                                      width: size.height * 0.07,
                                      fit: BoxFit.cover,
                                      cacheWidth: 200,
                                      errorBuilder: (_, __, ___) {
                                        return Image.asset(
                                          AppImage.userdummyimage,
                                          height: size.height * 0.07,
                                          width: size.height * 0.07,
                                        );
                                      },
                                    )
                                  : Image.asset(
                                      AppImage.userdummyimage,
                                      height: size.height * 0.07,
                                      width: size.height * 0.07,
                                      fit: BoxFit.cover,
                                    ),
                            ),

                            SizedBox(width: size.width * 0.04),

                            /// NAME & EMAIL
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: AppFont.fontFamily,
                                      color: AppColor.blackColor,
                                    ),
                                  ),
                                  SizedBox(height: size.height * 0.005),
                                  Text(
                                    subText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: AppFont.fontFamily,
                                      color: AppColor.hintTextColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            /// EDIT ICON

                            InkWell(
                              onTap: () {
                                if (userType == 'Customer') {
                                  Get.to(
                                    () => ProfileScreen(
                                      mobile: user.getUserMobile,
                                    ),
                                  );
                                }
                                if (userType == 'Retailer') {
                                  Get.to(() => RProfileScreen(
                                        mobile: user.getUserMobile,
                                      ));
                                }
                              },
                              child: Image.asset(
                                AppImage.editIcon,
                                height: size.height * 0.030,
                                width: size.height * 0.030,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  SizedBox(height: size.height * 0.04),

                  // Coins Wallet — Retailer only
                  if (userType == 'Retailer') ...[
                    _menuItem(
                      context,
                      icon: AppImage.coinwallet,
                      title: 'Coins Wallet 🪙',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CoinWalletScreen()),
                        );
                      },
                    ),
                    SizedBox(height: size.height * 0.01),
                  ],

                  _menuItem(
                    context,
                    icon: AppImage.termsimage,
                    title: AppLanguage.termsConditionText[language],
                    onTap: () {
                      Get.to(
                        () => ContentScreen(
                          contenttype: termsandconditionstype,
                          header: AppLanguage.termsConditionText[language],
                        ),
                      );
                    },
                  ),
                  SizedBox(height: size.height * 0.01),
                  _menuItem(
                    context,
                    icon: AppImage.privacyimage,
                    title: AppLanguage.privacyPolicyText[language],
                    onTap: () {
                      Get.to(
                        () => ContentScreen(
                          contenttype: privacypolicytype,
                          header: AppLanguage.privacyPolicyText[language],
                        ),
                      );
                    },
                  ),
                  SizedBox(height: size.height * 0.01),

                  _menuItem(
                    context,
                    icon: AppImage.aboutimage,
                    title: AppLanguage.aboutText[language],
                    onTap: () {
                      Get.to(
                        () => ContentScreen(
                          contenttype: aboutustype,
                          header: AppLanguage.aboutText[language],
                        ),
                      );
                    },
                  ),
                  SizedBox(height: size.height * 0.01),

                  _menuItem(
                    context,
                    icon: AppImage.helpimage,
                    title: AppLanguage.helpSupoortText[language],
                    onTap: () {
                      Get.to(() => HelpAndSupportscreen());
                    },
                  ),
                  SizedBox(height: size.height * 0.01),

                  _menuItem(
                    context,
                    icon: AppImage.rate,
                    title: AppLanguage.rateText[language],
                    onTap: () => openUrl(url: rateappurl),
                  ),
                  SizedBox(height: size.height * 0.01),

                  _menuItem(
                    context,
                    icon: AppImage.shareAcc,
                    title: AppLanguage.shareAppText[language],
                    onTap: () => shareApp(context),
                  ),
                  SizedBox(height: size.height * 0.01),

                  /// LOGOUT
                  _menuItem(
                    context,
                    icon: AppImage.logoutAcc,
                    title: AppLanguage.logoutText[language],
                    onTap: () {
                      _showLogoutDialog(context);
                    },
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
            userType == 'Customer'
                ? Image.asset(
                    icon,
                    height: size.height * 0.035,
                    width: size.height * 0.035,
                    // height:40 ,
                    // width: 40,
                  )
                : Image.asset(
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
