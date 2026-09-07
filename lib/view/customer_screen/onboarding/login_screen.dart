import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/contentService.dart';
import 'package:movigo/helper/contentScreen.dart';
import 'package:movigo/helper/custom_input_field.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';

class LoginScreen extends StatefulWidget {
  final String? mobile;
  /// Pass 'Customer' or 'Retailer' so login sends the correct user_type.
  /// Defaults to empty string — backend fallback order: Customer→Retailer→Driver.
  final String userType;
  const LoginScreen({super.key, this.mobile, this.userType = ''});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final TextEditingController mobileController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isTermsAccepted = true; // Auto-accepted — user can read T&C via link
  String termsandconditionstype = '';
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    loadContentData();

    if (widget.mobile != null) {
      mobileController.text = widget.mobile!;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    mobileController.dispose();
    super.dispose();
  }

  void loadContentData() {
    fetchAllContent((List data) {
      if (!mounted) return;
      for (var item in data) {
        if (item['content_type'] == 2) {
          termsandconditionstype = item['content_url'];
        }
      }
      setState(() {});
    });
  }

  signInUserValidation(String mobileNumber) async {
    if (mobileNumber.isEmpty) {
      SnackBarToastMessage.showSnackBar(
          context, AppLanguage.mobileNumberMessage[language]);
      return false;
    } else if (mobileNumber.length != 10) {
      SnackBarToastMessage.showSnackBar(
          context, AppLanguage.mobilevalidMessage[language]);
      return false;
    } else if (!_isTermsAccepted) {
      SnackBarToastMessage.showSnackBar(
          context, AppLanguage.termsconditionMessage[language]);
      return false;
    } else {
      final apiProvider = Provider.of<PostApiProvider>(context, listen: false);
      apiProvider.loginUserApiCall(context, mobileController.text, userType: widget.userType);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    // Edge-to-edge (Android 15 / SDK 35+): do NOT set statusBarColor /
    // systemNavigationBarColor — those call the deprecated
    // Window.setStatusBarColor() / setNavigationBarColor() and are flagged by
    // Play Console. The Scaffold's own backgroundColor shows behind the
    // transparent system bars. Only icon brightness is set.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarIconBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return PopScope(
      canPop: false,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: const Color(0xFFF3F6FA),
          body: SafeArea(
            child: Stack(
              children: [
                // 1. Scrollable Form Content
                Positioned.fill(
                  child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.07),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(height: size.height * 0.05),

                      /// App Logo
                      Image.asset(
                        AppImage.applogo3,
                        width: size.width * 0.55,
                        fit: BoxFit.contain,
                      ),

                      SizedBox(height: size.height * 0.04),

                      /// TITLE
                      Text(
                        AppLanguage.letsText[language],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColor.themeColor,
                        ),
                      ),

                      SizedBox(height: size.height * 0.01),

                      /// SUBTITLE
                      SizedBox(
                        width: size.width * 0.92,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            AppLanguage.singText[language],
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: AppFont.fontFamily,
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: AppColor.textColorTwo,
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: size.height * 0.045),

                      // ── Unified Authentication Card ────────────────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              language == 1 ? 'मोबाइल नंबर' : 'Mobile Number',
                              style: const TextStyle(
                                fontFamily: AppFont.fontFamily,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColor.themeColor,
                              ),
                            ),
                            const SizedBox(height: 10),
                            CustomInputField(
                              controller: mobileController,
                              hintText: AppLanguage.hintMobText[language],
                              keyboardType: TextInputType.phone,
                              maxLength: 10,
                              prefixText: '+91',
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _RoundedCheckbox(
                                  value: _isTermsAccepted,
                                  onChanged: (value) {
                                    setState(() {
                                      _isTermsAccepted = value;
                                    });
                                  },
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _isTermsAccepted = true;
                                      });
                                    },
                                    child: RichText(
                                      text: TextSpan(
                                        style: const TextStyle(
                                          fontFamily: AppFont.fontFamily,
                                          fontSize: 12,
                                          color: AppColor.textColorTwo,
                                        ),
                                        children: [
                                          const TextSpan(
                                            text: "By logging in, you agree to our ",
                                          ),
                                          TextSpan(
                                            text: "Terms & Conditions",
                                            style: const TextStyle(
                                              color: AppColor.themeColor,
                                              fontWeight: FontWeight.w600,
                                              decoration: TextDecoration.underline,
                                            ),
                                            recognizer: TapGestureRecognizer()
                                              ..onTap = () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => ContentScreen(
                                                      contenttype:
                                                          termsandconditionstype,
                                                      header: AppLanguage
                                                          .termsConditionText[
                                                              language],
                                                      legalKey: 'terms_conditions',
                                                    ),
                                                  ),
                                                );
                                              },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Consumer<PostApiProvider>(
                              builder: (context, apiprovider, child) {
                                return apiprovider.loading
                                    ? const Center(
                                        child: CircularProgressIndicator(
                                            color: AppColor.themeColor),
                                      )
                                    : AppButton(
                                        width: double.infinity,
                                        text: AppLanguage.sendOtpText[language],
                                        onPress: () {
                                          FocusScope.of(context).unfocus();
                                          signInUserValidation(
                                            mobileController.text.trim(),
                                          );
                                        },
                                      );
                              },
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: size.height * 0.02),

                      // Guest browsing: look around the app (vehicle types,
                      // pricing, etc.) without registering. Booking, payment
                      // and account screens still ask for login when needed.
                      // Required by App Store Guideline 5.1.1(v).
                      TextButton(
                        onPressed: () {
                          Get.offAll(() => const CustomBottomNav(
                                userType: UserType.retailer,
                                initialIndex: 0,
                              ));
                        },
                        child: Text(
                          'Continue as Guest',
                          style: const TextStyle(
                            fontFamily: AppFont.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColor.themeColor,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),

                      // Spacer to make sure content scrolls above bottom highway
                      const SizedBox(height: 240),
                    ],
                  ),
                ),
              ),
                  ),
                ),

                // 2. Animated Highway pinned at the bottom
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.fastOutSlowIn,
                  left: 0,
                  right: 0,
                  bottom: isKeyboardOpen ? -220 : 0,
                  height: 200,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: isKeyboardOpen ? 0.0 : 1.0,
                    child: AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: _HighwayParallaxPainter(
                            animationValue: _animationController.value,
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                left: size.width * 0.12,
                                bottom: 35 + sin(_animationController.value * 2 * pi * 8) * 1.8,
                                child: Image.asset(
                                  AppImage.animatedTruckIcon,
                                  height: 96,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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
}

// ── Small rounded checkbox matching the app's brand styling ─────────────────
class _RoundedCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _RoundedCheckbox({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: value ? AppColor.themeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: value ? AppColor.themeColor : AppColor.textColorTwo,
            width: 1.4,
          ),
        ),
        child: value
            ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
            : null,
      ),
    );
  }
}

// ── Custom Painter for the Animated Highway Parallax Effect ──────────────────
class _HighwayParallaxPainter extends CustomPainter {
  final double animationValue;

  _HighwayParallaxPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // 1. Draw Sky (Soft gradient fading to light blue-gray)
    final skyRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.7);
    const skyGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFF3F6FA),
        Color(0xFFE5ECF6),
      ],
    );
    paint.shader = skyGradient.createShader(skyRect);
    canvas.drawRect(skyRect, paint);
    paint.shader = null;

    // 2. Draw Clouds (Slow movement: ~0.45x speed)
    paint.color = Colors.white.withValues(alpha: 0.7);
    final cloudOffset = animationValue * size.width * 0.45;
    for (int i = 0; i < 3; i++) {
      double cloudX = (size.width * 0.4 * i - cloudOffset) % (size.width + 120) - 60;
      double cloudY = size.height * (0.08 + i * 0.04);
      canvas.drawCircle(Offset(cloudX, cloudY), 14, paint);
      canvas.drawCircle(Offset(cloudX + 10, cloudY - 3), 16, paint);
      canvas.drawCircle(Offset(cloudX + 22, cloudY), 12, paint);
    }

    // 3. Draw Skyline / Trees silhouette (Medium movement: ~1.05x speed)
    const buildingColor = Color(0xFFCAD4E3);
    paint.color = buildingColor;
    final skylineOffset = animationValue * size.width * 1.05;
    final double roadY = size.height * 0.65;

    final buildings = [
      _Building(width: 40, height: 65, gap: 15),
      _Building(width: 55, height: 90, gap: 20),
      _Building(width: 35, height: 50, gap: 12),
      _Building(width: 50, height: 100, gap: 25),
      _Building(width: 65, height: 75, gap: 18),
      _Building(width: 45, height: 85, gap: 14),
    ];

    double currentX = -skylineOffset;
    while (currentX < size.width + 150) {
      for (var b in buildings) {
        if (currentX + b.width > -50 && currentX < size.width + 50) {
          canvas.drawRect(
            Rect.fromLTWH(currentX, roadY - b.height, b.width, b.height),
            paint,
          );
        }
        currentX += b.width + b.gap;
      }
    }

    // 4. Draw Road (Bottom 35%) using dark asphalt black color
    final roadRect = Rect.fromLTWH(0, roadY, size.width, size.height - roadY);
    paint.color = const Color(0xFF18181A);
    canvas.drawRect(roadRect, paint);

    // 5. Draw Road dashes (Fast movement: ~4.5x speed)
    paint.color = Colors.white.withValues(alpha: 0.85);
    const dashWidth = 24.0;
    const dashHeight = 3.0;
    const dashGap = 16.0;
    final dashY = roadY + (size.height - roadY) * 0.45;

    const totalDashCycle = dashWidth + dashGap;
    final dashOffset = (animationValue * size.width * 4.5) % totalDashCycle;

    double dashX = -dashOffset;
    while (dashX < size.width) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(dashX, dashY, dashWidth, dashHeight),
          const Radius.circular(1.5),
        ),
        paint,
      );
      dashX += totalDashCycle;
    }
  }

  @override
  bool shouldRepaint(covariant _HighwayParallaxPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

// ── Building dimensions model for skyline painting ─────────────────────────
class _Building {
  final double width;
  final double height;
  final double gap;
  _Building({required this.width, required this.height, required this.gap});
}
