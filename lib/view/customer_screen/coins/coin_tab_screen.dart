import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/view/customer_screen/coins/coin_wallet_screen.dart';

class CoinTabScreen extends StatefulWidget {
  const CoinTabScreen({super.key});

  @override
  State<CoinTabScreen> createState() => _CoinTabScreenState();
}

class _CoinTabScreenState extends State<CoinTabScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _ctrl.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const CoinWalletScreen();

    return Scaffold(
      backgroundColor: const Color(0xFF08142A),
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) {
          final t = _ctrl.value;

          // ── Phase 1: pop OUT — coin grows from 0 → 1.28  (0.00 → 0.28) ──
          // ── Phase 2: pop IN  — coin shrinks 1.28 → 1.0   (0.28 → 0.44) ──
          final double coinScale;
          if (t < 0.28) {
            coinScale = 1.28 * Curves.easeOut.transform(t / 0.28);
          } else if (t < 0.44) {
            final settle = Curves.easeInOut.transform((t - 0.28) / 0.16);
            coinScale = 1.28 - 0.28 * settle;
          } else {
            coinScale = 1.0;
          }

          // Tiny rotation wiggle during the pop (adds life)
          final double coinRot;
          if (t < 0.44) {
            coinRot = math.sin(t / 0.44 * math.pi * 2) * 0.18;
          } else {
            coinRot = 0.0;
          }

          // ── Phase 3: "Movigo Coins" fades + slides up    (0.44 → 0.66) ──
          final textT = t < 0.44
              ? 0.0
              : t > 0.66
                  ? 1.0
                  : Curves.easeOut.transform((t - 0.44) / 0.22);

          // ── Phase 4: coin floats up above the text        (0.62 → 0.82) ──
          double floatY = 0.0;
          if (t >= 0.62) {
            final ft = ((t - 0.62) / 0.20).clamp(0.0, 1.0);
            floatY = -92.0 * Curves.easeInOut.transform(ft);
          }

          // ── Phase 5: fade to wallet                       (0.88 → 1.00) ──
          final splashOpacity = t < 0.88
              ? 1.0
              : 1.0 - Curves.easeIn.transform((t - 0.88) / 0.12);

          // Glow intensity follows coin scale
          final glowOpacity = (coinScale - 0.5).clamp(0.0, 0.8) * 0.22;

          return Opacity(
            opacity: splashOpacity,
            child: SizedBox.expand(
              child: Stack(
                alignment: Alignment.center,
                children: [
                // Ambient glow behind coin
                Opacity(
                  opacity: glowOpacity,
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0xFFFFD700), Colors.transparent],
                      ),
                    ),
                  ),
                ),

                // "Movigo Coins" — always centred on screen
                Opacity(
                  opacity: textT,
                  child: Transform.translate(
                    offset: Offset(0, 20.0 * (1.0 - textT)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Movigo Coins',
                          style: TextStyle(
                            fontFamily: AppFont.fontFamily,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Earn  •  Scratch  •  Redeem',
                          style: TextStyle(
                            fontFamily: AppFont.fontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFFFFD700).withOpacity(0.80),
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Coin — starts at centre, pops out/in, then floats up
                Transform.translate(
                  offset: Offset(0, floatY),
                  child: Transform.rotate(
                    angle: coinRot,
                    child: Transform.scale(
                      scale: coinScale,
                      child: const _CoinWidget(size: 100),
                    ),
                  ),
                ),
              ],
            ),
          ),
          );
        },
      ),
    );
  }
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
