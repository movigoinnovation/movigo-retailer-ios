import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'package:movigo/view/customer_screen/coins/coin_wallet_screen.dart';

class CoinTabScreen extends StatefulWidget {
  const CoinTabScreen({super.key});

  @override
  State<CoinTabScreen> createState() => _CoinTabScreenState();
}

class _CoinTabScreenState extends State<CoinTabScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  // Set once _done is true and never reset, so the coin-flip splash plays
  // only on the first visit to the coins tab per app launch — repeat taps
  // go straight to CoinWalletScreen.
  static bool _introPlayedThisLaunch = false;
  late bool _done = _introPlayedThisLaunch;
  // Shared across both render sites below so Flutter preserves the same
  // CoinWalletScreen State (and its already-fetched data) instead of
  // disposing and recreating it — which was firing every coins API call twice.
  final GlobalKey _coinWalletKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    if (_done) return;
    _ctrl.forward().whenComplete(() {
      _introPlayedThisLaunch = true;
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Precache the logo to ensure smooth, flicker-free rendering
    precacheImage(const AssetImage('assets/icons/movigo_app_logo.png'), context);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return CoinWalletScreen(key: _coinWalletKey);

    final size = MediaQuery.of(context).size;
    final cx = size.width / 2;
    final cy = size.height / 2 - 40; // Logo center coordinate
    final logoCenter = Offset(cx, cy);

    // Coins settle target coordinates relative to logo center (forming a triangle)
    final settleTargets = [
      Offset(cx - 70.0, cy - 36.0), // Top Left
      Offset(cx + 70.0, cy - 36.0), // Top Right
      Offset(cx, cy + 50.0),        // Bottom Center
    ];

    return Scaffold(
      backgroundColor: Colors.transparent, // transparency allows dashboard to show behind during wipe
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) {
          final t = _ctrl.value;

          // ── PHASE 1: Z-Depth Zoom (0.00 -> 0.36) ──
          // ── PHASE 2: Edge Settle   (0.36 -> 0.58) ──
          // ── PHASE 3: Combo Pulse   (0.58 -> 0.70) ──
          // ── PHASE 4: Radial Wipe   (0.70 -> 1.00) ──

          // 1. Calculate Coin Coordinates, Scales, and Rotations
          final coinPositions = <Offset>[];
          final coinScales = <double>[];
          final coinRotations = <double>[];
          final coinOpacities = <double>[];

          if (t <= 0.36) {
            final pz = (t / 0.36).clamp(0.0, 1.0);
            for (int i = 0; i < 3; i++) {
              final angleOffset = i * (2 * math.pi / 3);
              final spiralAngle = angleOffset + pz * 2 * math.pi;
              final spiralRadius = 20.0 + 130.0 * Curves.easeOutCubic.transform(pz);

              final x = cx + spiralRadius * math.cos(spiralAngle);
              final y = cy + spiralRadius * math.sin(spiralAngle) * 0.6;
              coinPositions.add(Offset(x, y));

              final scale = 0.05 + 0.95 * Curves.easeOutCubic.transform(pz);
              coinScales.add(scale);
              coinRotations.add(pz * 6 * math.pi);
              coinOpacities.add((pz * 1.5).clamp(0.0, 1.0));
            }
          } else if (t <= 0.58) {
            final pg = ((t - 0.36) / 0.22).clamp(0.0, 1.0);
            final easePg = Curves.easeInOutCubic.transform(pg);
            for (int i = 0; i < 3; i++) {
              // Zoom endpoint coordinates
              final angleOffset = i * (2 * math.pi / 3);
              final endAngle = angleOffset + 2 * math.pi;
              final endX = cx + 150.0 * math.cos(endAngle);
              final endY = cy + 150.0 * math.sin(endAngle) * 0.6;

              final tx = settleTargets[i].dx;
              final ty = settleTargets[i].dy;

              final x = endX + (tx - endX) * easePg;
              final y = endY + (ty - endY) * easePg;
              coinPositions.add(Offset(x, y));

              final scale = 1.0 + (0.75 - 1.0) * easePg;
              coinScales.add(scale);
              coinRotations.add(0.0);
              coinOpacities.add(1.0);
            }
          } else if (t <= 0.70) {
            final pp = ((t - 0.58) / 0.12).clamp(0.0, 1.0);
            final pulseScale = 1.0 + 0.15 * math.sin(pp * math.pi);
            final pushFactor = 1.0 + 0.12 * math.sin(pp * math.pi);
            for (int i = 0; i < 3; i++) {
              final tx = settleTargets[i].dx;
              final ty = settleTargets[i].dy;

              final x = cx + (tx - cx) * pushFactor;
              final y = cy + (ty - cy) * pushFactor;
              coinPositions.add(Offset(x, y));

              coinScales.add(0.75 * pulseScale);
              coinRotations.add(0.0);
              coinOpacities.add(1.0);
            }
          }

          // 2. Calculate Logo Opacity & Scale
          double logoOpacity = 0.0;
          double logoScale = 1.0;
          if (t <= 0.36) {
            final pz = (t / 0.36).clamp(0.0, 1.0);
            logoOpacity = Curves.easeOutCubic.transform(pz);
            logoScale = 0.6 + 0.4 * Curves.easeOutBack.transform(pz);
          } else if (t <= 0.58) {
            logoOpacity = 1.0;
            logoScale = 1.0;
          } else if (t <= 0.70) {
            final pp = ((t - 0.58) / 0.12).clamp(0.0, 1.0);
            logoOpacity = 1.0;
            logoScale = 1.0 + 0.15 * math.sin(pp * math.pi);
          } else if (t > 0.70) {
            final pw = ((t - 0.70) / 0.30).clamp(0.0, 1.0);
            logoOpacity = (1.0 - pw).clamp(0.0, 1.0);
            logoScale = 1.0 - pw * 0.15;
          }

          // 3. Calculate Wipe Progress
          final wipeProgress = t <= 0.70 ? 0.0 : ((t - 0.70) / 0.30).clamp(0.0, 1.0);



          return Stack(
            children: [
              // Underlay dashboard reveals as the wipe progresses
              if (t > 0.70) Positioned.fill(child: CoinWalletScreen(key: _coinWalletKey)),

              // Splash screen overlay layer containing mask wipe
              Positioned.fill(
                child: CustomPaint(
                  painter: _SplashWipePainter(
                    progress: wipeProgress,
                    logoCenter: logoCenter,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Transparent Logo Image (No Borders)
                      if (logoOpacity > 0.0)
                        Positioned(
                          left: cx - 90,
                          top: cy - 90, // Centered vertically around cy
                          width: 180,
                          height: 180,
                          child: Opacity(
                            opacity: logoOpacity,
                            child: Transform.scale(
                              scale: logoScale,
                              child: Image.asset(
                                'assets/icons/movigo_app_logo.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),


                      // 3 Flying/Orbiting Coins
                      if (t <= 0.70)
                        ...List.generate(coinPositions.length, (index) {
                          final pos = coinPositions[index];
                          final scale = coinScales[index];
                          final rot = coinRotations[index];
                          final op = coinOpacities[index];

                          return Positioned(
                            left: pos.dx - 25,
                            top: pos.dy - 25,
                            width: 50,
                            height: 50,
                            child: Opacity(
                              opacity: op,
                              child: Transform(
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, 0.001) // perspective depth
                                  ..rotateY(rot),
                                alignment: Alignment.center,
                                child: Transform.scale(
                                  scale: scale,
                                  child: const _CoinWidget(size: 50),
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Splash Stencil Wipe CustomPainter ──────────────────────────────────────────

class _SplashWipePainter extends CustomPainter {
  final double progress;
  final Offset logoCenter;

  _SplashWipePainter({required this.progress, required this.logoCenter});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    if (progress <= 0.0) {
      // Paint full solid splash background
      canvas.drawRect(rect, Paint()..color = const Color(0xFF08142A));
      return;
    }

    // SaveLayer is required for BlendMode.clear stencil masking
    canvas.saveLayer(rect, Paint());

    // 1. Draw solid dark background
    canvas.drawRect(rect, Paint()..color = const Color(0xFF08142A));

    // 2. Clear circular cutout to reveal underlay
    final maxRadius = math.sqrt(size.width * size.width + size.height * size.height) + 120.0;
    final r = progress * maxRadius;

    canvas.drawCircle(
      logoCenter,
      r,
      Paint()..blendMode = BlendMode.clear,
    );

    canvas.restore();

    // 3. Draw expanding gold ripple wave edge
    if (r > 0.0 && r < maxRadius) {
      final ripplePaint1 = Paint()
        ..color = const Color(0xFFFFD700)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8.0;

      final ripplePaint2 = Paint()
        ..color = const Color(0xFFDAA520)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      canvas.drawCircle(logoCenter, r, ripplePaint1);
      canvas.drawCircle(logoCenter, r + 5.0, ripplePaint2);
    }
  }

  @override
  bool shouldRepaint(covariant _SplashWipePainter old) =>
      old.progress != progress || old.logoCenter != logoCenter;
}

// ── Gold Coin ─────────────────────────────────────────────────────────────────

class _CoinWidget extends StatelessWidget {
  final double size;
  const _CoinWidget({required this.size});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: _CoinPainter(),
      );
}

class _CoinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Outer glow
    canvas.drawCircle(
      c, r + 8,
      Paint()
        ..color = const Color(0xFFFFD700).withOpacity(0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // Coin edge ring — dark gold thick border (milled edge look)
    canvas.drawCircle(c, r,
        Paint()..color = const Color(0xFF7A5200)..style = PaintingStyle.fill);
    canvas.drawCircle(c, r - 1,
        Paint()..color = const Color(0xFFB8860B)..style = PaintingStyle.fill);

    // Raised edge dots (60 small dots around the rim — reeding effect)
    final dotPaint = Paint()..color = const Color(0xFF8B6500);
    const int dots = 60;
    for (int i = 0; i < dots; i++) {
      final angle = (i / dots) * 2 * math.pi;
      final dotCenter = c + Offset(math.cos(angle) * (r - 2.8), math.sin(angle) * (r - 2.8));
      canvas.drawCircle(dotCenter, 1.4, dotPaint);
    }

    // Main face — gold radial gradient
    final faceRect = Rect.fromCircle(center: c, radius: r - 5.5);
    canvas.drawCircle(
      c, r - 5.5,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.30, -0.45),
          radius: 0.90,
          colors: [
            Color(0xFFFFFDE7),
            Color(0xFFFFD700),
            Color(0xFFDAA520),
            Color(0xFFA67C00),
          ],
          stops: [0.0, 0.28, 0.65, 1.0],
        ).createShader(faceRect),
    );

    // Inner raised rim line
    canvas.drawCircle(
      c, r - 12,
      Paint()
        ..color = const Color(0xFFA67C00).withOpacity(0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    // ₹ symbol
    final tp = TextPainter(
      text: TextSpan(
        text: '₹',
        style: TextStyle(
          color: const Color(0xFF5C3A00),
          fontSize: r * 0.80,
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));

    // Shine highlight
    canvas.drawCircle(
      c, r - 5.5,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.55, -0.62),
          radius: 0.50,
          colors: [
            Colors.white.withOpacity(0.58),
            Colors.white.withOpacity(0.0),
          ],
        ).createShader(faceRect),
    );
  }

  @override
  bool shouldRepaint(_CoinPainter o) => false;
}
