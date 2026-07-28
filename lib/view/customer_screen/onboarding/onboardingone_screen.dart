import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:movigo/view/customer_screen/onboarding/login_screen.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_language.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      setState(() => currentIndex = 1);
    });
    Future.delayed(const Duration(milliseconds: 4200), () {
      if (!mounted) return;
      Get.offAll(() => LoginScreen());
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: AppColor.transparentColor,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColor.transparentColor,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 800),
        switchInCurve: Curves.easeInOutQuart,
        switchOutCurve: Curves.easeInOutQuart,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          ),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeInOut),
            ),
            child: child,
          ),
        ),
        child: currentIndex == 0 ? _onboardingOne(size) : _onboardingTwo(size),
      ),
    );
  }

  Widget _onboardingOne(Size size) {
    return SizedBox(
      key: const ValueKey(0),
      width: size.width,
      height: size.height,
      child: Stack(
        children: [
          // Animated delivery scene
          const _DeliveryAnimation(),
          // Text overlay
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: size.height * 0.08),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _indicator(size),
                    GestureDetector(
                      onTap: () => Get.offAll(() => LoginScreen()),
                      child: Text(
                        AppLanguage.skipText[language],
                        style: const TextStyle(
                          color: AppColor.whiteColor,
                          fontFamily: AppFont.fontFamily,
                          fontWeight: FontWeight.w400,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: size.height * 0.5),
                Text(
                  AppLanguage.splashText[language],
                  style: const TextStyle(
                    color: AppColor.whiteColor,
                    fontFamily: AppFont.fontFamily1,
                    fontWeight: FontWeight.w500,
                    fontSize: 24,
                  ),
                ),
                SizedBox(height: size.height * 0.02),
                Text(
                  AppLanguage.shipText[language],
                  style: const TextStyle(
                    color: AppColor.whiteColor,
                    fontFamily: AppFont.fontFamily1,
                    fontWeight: FontWeight.w600,
                    fontSize: 32,
                  ),
                ),
                SizedBox(height: size.height * 0.02),
                Text(
                  AppLanguage.bookText[language],
                  style: const TextStyle(
                    color: AppColor.textColor,
                    fontFamily: AppFont.fontFamily,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _onboardingTwo(Size size) {
    return SizedBox(
      key: const ValueKey(1),
      width: size.width,
      height: size.height,
      child: Stack(
        children: [
          // Same animated background, different feel via overlay tint
          const _DeliveryAnimation(),
          Container(color: const Color(0xFF0A1628).withOpacity(0.35)),
          // Text overlay
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: size.height * 0.08),
                _indicator(size),
                SizedBox(height: size.height * 0.1),
                Text(
                  AppLanguage.splashText[language],
                  style: const TextStyle(
                    color: AppColor.whiteColor,
                    fontFamily: AppFont.fontFamily1,
                    fontWeight: FontWeight.w500,
                    fontSize: 24,
                  ),
                ),
                SizedBox(height: size.height * 0.02),
                Text(
                  AppLanguage.trackText[language],
                  style: const TextStyle(
                    color: AppColor.whiteColor,
                    fontFamily: AppFont.fontFamily1,
                    fontWeight: FontWeight.w600,
                    fontSize: 32,
                  ),
                ),
                SizedBox(height: size.height * 0.02),
                Text(
                  AppLanguage.monitorText[language],
                  style: const TextStyle(
                    color: AppColor.textColor,
                    fontFamily: AppFont.fontFamily,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _indicator(Size size) {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 5,
          width: size.width * 0.16,
          decoration: BoxDecoration(
            color: currentIndex == 0
                ? AppColor.whiteColor
                : AppColor.onbContainerColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: size.width * 0.03),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 5,
          width: size.width * 0.16,
          decoration: BoxDecoration(
            color: currentIndex == 1
                ? AppColor.whiteColor
                : AppColor.onbContainerColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

// ── Delivery Animation ────────────────────────────────────────────────────────

class _DeliveryAnimation extends StatefulWidget {
  const _DeliveryAnimation();

  @override
  State<_DeliveryAnimation> createState() => _DeliveryAnimationState();
}

class _DeliveryAnimationState extends State<_DeliveryAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) => SizedBox.expand(
          child: CustomPaint(
            painter: _DeliveryPainter(t: _ctrl.value),
          ),
        ),
      );
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _DeliveryPainter extends CustomPainter {
  final double t;
  const _DeliveryPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    _sky(canvas, size);
    _ground(canvas, size);
    _house(canvas, size);
    _person(canvas, size);
  }

  // ── Sky + stars ──────────────────────────────────────────────────────────
  void _sky(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF050E1C), Color(0xFF0D2137), Color(0xFF1A3A6B)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Stars — twinkle offset by t
    final rng = [
      Offset(w * 0.08, h * 0.04), Offset(w * 0.22, h * 0.09),
      Offset(w * 0.40, h * 0.05), Offset(w * 0.58, h * 0.10),
      Offset(w * 0.72, h * 0.04), Offset(w * 0.88, h * 0.07),
      Offset(w * 0.14, h * 0.16), Offset(w * 0.50, h * 0.18),
      Offset(w * 0.78, h * 0.14), Offset(w * 0.33, h * 0.22),
      Offset(w * 0.92, h * 0.20), Offset(w * 0.62, h * 0.25),
    ];
    for (int i = 0; i < rng.length; i++) {
      final twinkle = 0.5 + 0.5 * math.sin(t * math.pi * 2 + i * 1.3);
      canvas.drawCircle(
        rng[i], 1.5,
        Paint()..color = Colors.white.withOpacity(0.35 + 0.40 * twinkle),
      );
    }

    // Moon (top-right)
    final moonC = Offset(w * 0.84, h * 0.09);
    canvas.drawCircle(moonC, w * 0.055,
        Paint()..color = const Color(0xFFFFF9E0).withOpacity(0.92));
    // crescent shadow
    canvas.drawCircle(moonC + Offset(w * 0.022, -w * 0.008), w * 0.045,
        Paint()..color = const Color(0xFF0D2137));
  }

  // ── Ground ───────────────────────────────────────────────────────────────
  void _ground(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final gy = h * 0.71;

    // Ground fill
    canvas.drawRect(
      Rect.fromLTRB(0, gy, w, h),
      Paint()..color = const Color(0xFF081523),
    );

    // Grass strip
    canvas.drawRect(
      Rect.fromLTRB(0, gy - h * 0.012, w, gy + h * 0.010),
      Paint()..color = const Color(0xFF1A4A2E),
    );

    // Path from house door to right edge
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.33, gy + h * 0.010, w, gy + h * 0.035),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF12293D),
    );

    // Path centre line
    for (double x = w * 0.40; x < w; x += w * 0.10) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, gy + h * 0.018, w * 0.05, h * 0.006),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFFFFFFFF).withOpacity(0.10),
      );
    }
  }

  // ── House ────────────────────────────────────────────────────────────────
  void _house(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final gy       = h * 0.71;
    final left     = w * 0.06;
    final right    = w * 0.54;
    final wallTop  = h * 0.40;
    final roofPeak = h * 0.22;
    final cx       = (left + right) / 2;

    // House shadow
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, gy + h * 0.005),
          width: (right - left) * 0.80,
          height: h * 0.022),
      Paint()
        ..color = Colors.black.withOpacity(0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // ── Walls ──────────────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(left, wallTop, right, gy), const Radius.circular(5)),
      Paint()..color = const Color(0xFFFEF4DC),
    );

    // Wall texture lines (horizontal)
    final wallLinePaint = Paint()
      ..color = const Color(0xFFE8D5B0).withOpacity(0.60)
      ..strokeWidth = 1.0;
    for (double y = wallTop + h * 0.04; y < gy; y += h * 0.04) {
      canvas.drawLine(Offset(left, y), Offset(right, y), wallLinePaint);
    }

    // ── Roof ───────────────────────────────────────────────────────────
    final roofPath = Path()
      ..moveTo(left - w * 0.025, wallTop + 5)
      ..lineTo(cx, roofPeak)
      ..lineTo(right + w * 0.025, wallTop + 5)
      ..close();
    canvas.drawPath(roofPath, Paint()..color = const Color(0xFFD96B2E));

    // Roof shingle lines
    final shinglePaint = Paint()
      ..color = const Color(0xFFB85520).withOpacity(0.55)
      ..strokeWidth = 1.5;
    for (int i = 1; i <= 5; i++) {
      final y = roofPeak + (wallTop - roofPeak) * i / 6;
      final halfW = (right - left) * 0.5 * (i / 6.0) + w * 0.025;
      canvas.drawLine(Offset(cx - halfW, y), Offset(cx + halfW, y), shinglePaint);
    }

    // Roof edge trim
    canvas.drawPath(
        roofPath,
        Paint()
          ..color = const Color(0xFF9B3E10)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);

    // ── Chimney ────────────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(cx + w * 0.04, roofPeak + h * 0.015, w * 0.055, h * 0.08),
          const Radius.circular(3)),
      Paint()..color = const Color(0xFFC26A50),
    );
    // chimney top
    canvas.drawRect(
      Rect.fromLTWH(
          cx + w * 0.035, roofPeak + h * 0.013, w * 0.065, h * 0.010),
      Paint()..color = const Color(0xFF9B3E10),
    );
    // smoke puffs
    for (int i = 0; i < 3; i++) {
      final smokeT = (t + i * 0.33) % 1.0;
      final sy = roofPeak + h * 0.013 - smokeT * h * 0.06;
      final opacity = (1 - smokeT) * 0.35;
      final sr = w * 0.012 + smokeT * w * 0.018;
      canvas.drawCircle(
        Offset(cx + w * 0.065 + math.sin(smokeT * math.pi) * w * 0.008, sy),
        sr,
        Paint()..color = Colors.grey.withOpacity(opacity),
      );
    }

    // ── Door ───────────────────────────────────────────────────────────
    final doorW = w * 0.085;
    final doorH = h * 0.135;
    final doorL = cx - doorW / 2;
    final doorPath = Path()
      ..moveTo(doorL, gy)
      ..lineTo(doorL, gy - doorH + doorW / 2)
      ..arcToPoint(Offset(doorL + doorW, gy - doorH + doorW / 2),
          radius: Radius.circular(doorW / 2))
      ..lineTo(doorL + doorW, gy)
      ..close();
    canvas.drawPath(doorPath, Paint()..color = const Color(0xFF5C2E1A));
    // door frame
    canvas.drawPath(
        doorPath,
        Paint()
          ..color = const Color(0xFF3D1C0A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0);
    // door knob
    canvas.drawCircle(
      Offset(doorL + doorW * 0.72, gy - doorH * 0.40),
      h * 0.0085,
      Paint()..color = const Color(0xFFFFD700),
    );

    // ── Windows ────────────────────────────────────────────────────────
    _window(canvas,
        Offset(left + w * 0.045, wallTop + h * 0.052), w * 0.105, h * 0.092);
    _window(canvas,
        Offset(right - w * 0.155, wallTop + h * 0.052), w * 0.105, h * 0.092);

    // Warm light glow from windows
    for (final wx in [left + w * 0.048, right - w * 0.152]) {
      canvas.drawRect(
        Rect.fromLTWH(wx, wallTop + h * 0.055, w * 0.099, h * 0.086),
        Paint()
          ..color = const Color(0xFFFFE082).withOpacity(0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  void _window(Canvas canvas, Offset pos, double ww, double wh) {
    final rect = Rect.fromLTWH(pos.dx, pos.dy, ww, wh);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = const Color(0xFFFFF59D).withOpacity(0.88));
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..color = const Color(0xFF8B6914)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2);
    // pane dividers
    canvas.drawLine(Offset(pos.dx + ww / 2, pos.dy),
        Offset(pos.dx + ww / 2, pos.dy + wh),
        Paint()..color = const Color(0xFF8B6914)..strokeWidth = 1.8);
    canvas.drawLine(Offset(pos.dx, pos.dy + wh / 2),
        Offset(pos.dx + ww, pos.dy + wh / 2),
        Paint()..color = const Color(0xFF8B6914)..strokeWidth = 1.8);
  }

  // ── Person ───────────────────────────────────────────────────────────────
  void _person(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final gy = h * 0.71;

    // Door X
    final doorX = (w * 0.06 + w * 0.54) / 2;
    final startX = w * 1.05;

    double px;
    bool facingLeft;
    bool hasParcel;
    double bendY = 0.0;   // person crouches down when placing parcel
    double walkCycle = 0; // drives leg/arm swing

    if (t < 0.40) {
      // Walk toward house
      final p = Curves.easeInOut.transform(t / 0.40);
      px = startX - (startX - doorX - w * 0.12) * p;
      facingLeft = true;
      hasParcel = true;
      walkCycle = t / 0.40 * 6.0; // 6 walk cycles
    } else if (t < 0.56) {
      // At house — place parcel (crouch and stand)
      px = doorX + w * 0.13;
      facingLeft = true;
      final bd = (t - 0.40) / 0.16;
      bendY = math.sin(bd * math.pi) * h * 0.04;
      hasParcel = bd < 0.50;
      walkCycle = 0;
    } else if (t < 0.62) {
      // Brief pause, turns around
      px = doorX + w * 0.13;
      facingLeft = false;
      hasParcel = false;
      walkCycle = 0;
    } else {
      // Walk back toward right
      final p = Curves.easeInOut.transform((t - 0.62) / 0.38);
      px = (doorX + w * 0.13) + (startX - doorX - w * 0.13) * p;
      facingLeft = false;
      hasParcel = false;
      walkCycle = (t - 0.62) / 0.38 * 6.0;
    }

    final headR = h * 0.028;
    final bodyH = h * 0.058;
    final legH  = h * 0.062;
    final armH  = h * 0.040;
    final lThk  = h * 0.020;   // limb thickness

    final footY  = gy;
    final hipY   = footY - legH + bendY;
    final neckY  = hipY - bodyH;
    final headY  = neckY - headR;

    final dir = facingLeft ? -1.0 : 1.0;
    final swing = math.sin(walkCycle * math.pi) * 0.48;
    final aSwing = math.sin(walkCycle * math.pi) * 0.32;

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(px, footY + h * 0.004),
          width: headR * 5.0,
          height: headR * 0.85),
      Paint()
        ..color = Colors.black.withOpacity(0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Legs
    _limb(canvas, Offset(px, hipY), legH, dir * swing, lThk * 1.1,
        const Color(0xFF1E2440));
    _limb(canvas, Offset(px, hipY), legH, -dir * swing, lThk * 1.1,
        const Color(0xFF1E2440));

    // Body — delivery vest (brand navy)
    canvas.drawLine(
      Offset(px, neckY),
      Offset(px, hipY),
      Paint()
        ..color = const Color(0xFF1A3A6B)
        ..strokeWidth = lThk * 1.9
        ..strokeCap = StrokeCap.round,
    );
    // Vest stripe
    canvas.drawLine(
      Offset(px, neckY + bodyH * 0.30),
      Offset(px, hipY - bodyH * 0.10),
      Paint()
        ..color = const Color(0xFFFFD700).withOpacity(0.80)
        ..strokeWidth = lThk * 0.45
        ..strokeCap = StrokeCap.round,
    );

    // Arms
    _limb(canvas, Offset(px, neckY + bodyH * 0.22), armH, dir * aSwing,
        lThk * 0.88, const Color(0xFFE8A878));
    _limb(canvas, Offset(px, neckY + bodyH * 0.22), armH, -dir * aSwing,
        lThk * 0.88, const Color(0xFFE8A878));

    // Head
    canvas.drawCircle(
        Offset(px, headY), headR, Paint()..color = const Color(0xFFFAC898));

    // Delivery cap
    final capRect = Rect.fromCenter(
        center: Offset(px + dir * headR * 0.12, headY - headR * 0.35),
        width: headR * 2.30,
        height: headR * 1.0);
    canvas.drawArc(capRect, math.pi, math.pi, true,
        Paint()..color = const Color(0xFF1A3A6B));
    // cap brim
    canvas.drawRect(
      Rect.fromLTWH(
          px - dir * headR * 0.05 - headR * 1.2,
          headY - headR * 0.10,
          headR * 2.4,
          headR * 0.28),
      Paint()..color = const Color(0xFF0D2137),
    );

    // Eye
    canvas.drawCircle(
      Offset(px + dir * headR * 0.40, headY - headR * 0.08),
      headR * 0.14,
      Paint()..color = const Color(0xFF3B2507),
    );

    // Parcel
    if (hasParcel) {
      final parcelCx = px + dir * (headR * 1.35 + lThk * 0.5);
      final parcelCy = hipY - bodyH * 0.18 + bendY;
      final pw = h * 0.055;
      final ph = h * 0.050;

      // Box
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(parcelCx, parcelCy), width: pw, height: ph),
            const Radius.circular(3)),
        Paint()..color = const Color(0xFFD4883A),
      );
      // Box shade (bottom face)
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(
                parcelCx - pw / 2, parcelCy + ph * 0.30, pw, ph * 0.25),
            const Radius.circular(2)),
        Paint()..color = const Color(0xFFB06020).withOpacity(0.55),
      );
      // Tape cross
      final tp = Paint()
        ..color = const Color(0xFFFFD700).withOpacity(0.85)
        ..strokeWidth = h * 0.0055
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(parcelCx - pw / 2, parcelCy),
          Offset(parcelCx + pw / 2, parcelCy), tp);
      canvas.drawLine(Offset(parcelCx, parcelCy - ph / 2),
          Offset(parcelCx, parcelCy + ph / 2), tp);
    }

    // Parcel on doorstep after delivery
    if (t >= 0.50 && t < 0.56) {
      final pd = (t - 0.50) / 0.06;
      _parcelOnStep(canvas, size, pd);
    } else if (t >= 0.56) {
      _parcelOnStep(canvas, size, 1.0);
    }
  }

  void _parcelOnStep(Canvas canvas, Size size, double opacity) {
    final w = size.width;
    final h = size.height;
    final gy = h * 0.71;
    final doorX = (w * 0.06 + w * 0.54) / 2;
    final pw = h * 0.048;
    final ph = h * 0.044;
    final cx = doorX + w * 0.005;
    final cy = gy - ph / 2;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy), width: pw, height: ph),
          const Radius.circular(3)),
      Paint()..color = const Color(0xFFD4883A).withOpacity(opacity),
    );
    final tp = Paint()
      ..color = const Color(0xFFFFD700).withOpacity(0.85 * opacity)
      ..strokeWidth = h * 0.005
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - pw / 2, cy), Offset(cx + pw / 2, cy), tp);
    canvas.drawLine(Offset(cx, cy - ph / 2), Offset(cx, cy + ph / 2), tp);
  }

  void _limb(Canvas canvas, Offset origin, double length, double angle,
      double thickness, Color color) {
    final end = origin +
        Offset(math.sin(angle) * length, math.cos(angle) * length);
    canvas.drawLine(origin, end,
        Paint()
          ..color = color
          ..strokeWidth = thickness
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_DeliveryPainter old) => old.t != t;
}
