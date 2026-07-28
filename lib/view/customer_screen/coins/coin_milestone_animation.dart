import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';
import 'coin_wallet_screen.dart';

/// Full-screen celebration overlay shown when the retailer reaches the
/// weekly milestone of 10 orders.  Triggered by Pusher 'milestone_reached'.
/// The SharedPreferences flag [milestone_animation_week] ensures it plays
/// at most once per ISO week even if the Pusher event fires multiple times.
class CoinMilestoneAnimation extends StatefulWidget {
  final int bonusCoins;
  final int totalBalance;

  const CoinMilestoneAnimation({
    super.key,
    required this.bonusCoins,
    required this.totalBalance,
  });

  /// Show the animation overlay if not already shown this week.
  static Future<void> showIfNeeded(
    BuildContext context, {
    required int bonusCoins,
    required int totalBalance,
  }) async {
    final prefs   = await SharedPreferences.getInstance();
    final weekStr = _currentISOWeek();
    final stored  = prefs.getString('milestone_animation_week') ?? '';
    if (stored == weekStr) return; // already shown this week

    await prefs.setString('milestone_animation_week', weekStr);
    if (context.mounted) {
      await Navigator.push(
        context,
        PageRouteBuilder(
          opaque: false,
          pageBuilder: (_, __, ___) => CoinMilestoneAnimation(
            bonusCoins:   bonusCoins,
            totalBalance: totalBalance,
          ),
        ),
      );
    }
  }

  static String _currentISOWeek() {
    final now = DateTime.now().toUtc();
    final d   = DateTime.utc(now.year, now.month, now.day);
    final day = d.weekday; // 1=Mon
    final thurOrBefore = d.add(Duration(days: 4 - day));
    final yearStart = DateTime.utc(thurOrBefore.year, 1, 1);
    final weekNo = ((thurOrBefore.difference(yearStart).inDays) ~/ 7) + 1;
    return '${thurOrBefore.year}-W${weekNo.toString().padLeft(2, '0')}';
  }

  @override
  State<CoinMilestoneAnimation> createState() => _CoinMilestoneAnimationState();
}

class _CoinMilestoneAnimationState extends State<CoinMilestoneAnimation>
    with TickerProviderStateMixin {
  // Overlay fade-in
  late AnimationController _overlayCtrl;
  late Animation<double> _overlayOpacity;

  // Center coin scale
  late AnimationController _coinCtrl;
  late Animation<double> _coinScale;

  // Confetti
  late AnimationController _confettiCtrl;
  final List<_Confetti> _confettiPieces = [];
  final math.Random _rand = math.Random();

  // Card slide-up
  late AnimationController _cardCtrl;
  late Animation<Offset> _cardSlide;
  late Animation<double> _cardFade;

  @override
  void initState() {
    super.initState();

    _overlayCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _overlayOpacity = CurvedAnimation(parent: _overlayCtrl, curve: Curves.easeIn);

    _coinCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _coinScale = CurvedAnimation(parent: _coinCtrl, curve: Curves.elasticOut);

    _confettiCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));

    _cardCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutCubic));
    _cardFade = CurvedAnimation(parent: _cardCtrl, curve: Curves.easeIn);

    // Seed confetti
    for (int i = 0; i < 60; i++) {
      _confettiPieces.add(_Confetti.random(_rand));
    }

    _runSequence();
  }

  Future<void> _runSequence() async {
    await _overlayCtrl.forward();                        // 400ms
    await _coinCtrl.forward();                           // 700ms
    _confettiCtrl.forward();                             // 3s (no await)
    await Future.delayed(const Duration(milliseconds: 300));
    _cardCtrl.forward();                                 // card slide up
  }

  @override
  void dispose() {
    _overlayCtrl.dispose();
    _coinCtrl.dispose();
    _confettiCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  void _dismiss() {
    Navigator.of(context).pop();
  }

  void _openWallet() {
    Navigator.of(context).pop();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CoinWalletScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _overlayCtrl, _coinCtrl, _confettiCtrl, _cardCtrl,
        ]),
        builder: (context, _) {
          return Stack(
            children: [
              // Semi-transparent dark overlay
              Opacity(
                opacity: _overlayOpacity.value * 0.85,
                child: Container(color: const Color(0xFF0A1628)),
              ),

              // Confetti
              Positioned.fill(
                child: CustomPaint(
                  painter: _ConfettiPainter(
                    pieces:   _confettiPieces,
                    progress: _confettiCtrl.value,
                    size:     size,
                  ),
                ),
              ),

              // Center coin
              Center(
                child: Transform.translate(
                  offset: const Offset(0, -100),
                  child: ScaleTransition(
                    scale: _coinScale,
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFD700).withOpacity(0.6),
                            blurRadius: 30,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text('🪙', style: TextStyle(fontSize: 52)),
                      ),
                    ),
                  ),
                ),
              ),

              // Card slides up from bottom
              if (_cardCtrl.value > 0)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 32,
                  child: FadeTransition(
                    opacity: _cardFade,
                    child: SlideTransition(
                      position: _cardSlide,
                      child: _MilestoneCard(
                        bonusCoins:   widget.bonusCoins,
                        totalBalance: widget.totalBalance,
                        onViewWallet: _openWallet,
                        onContinue:   _dismiss,
                      ),
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

// ── Milestone Card ────────────────────────────────────────────────────────────

class _MilestoneCard extends StatelessWidget {
  final int bonusCoins;
  final int totalBalance;
  final VoidCallback onViewWallet;
  final VoidCallback onContinue;

  const _MilestoneCard({
    required this.bonusCoins,
    required this.totalBalance,
    required this.onViewWallet,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🏆', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text(
            'Weekly Milestone Reached!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              fontFamily: AppFont.fontFamily,
              color: AppColor.blackColor,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'You completed 10 orders this week 🎉',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontFamily: AppFont.fontFamily,
              color: AppColor.greyColor,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  '+$bonusCoins Bonus Coins Credited',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    fontFamily: AppFont.fontFamily,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'New Total: $totalBalance 🪙',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    fontFamily: AppFont.fontFamily,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onViewWallet,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColor.themeColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'View Coins Wallet',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: AppFont.fontFamily, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onContinue,
            child: const Text(
              'Continue',
              style: TextStyle(fontSize: 14, fontFamily: AppFont.fontFamily, color: AppColor.greyColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Confetti ──────────────────────────────────────────────────────────────────

class _Confetti {
  final double x;        // initial x (0-1)
  final double speed;    // fall speed multiplier
  final double size;
  final Color color;
  final double rotation;
  final bool isCircle;

  _Confetti({
    required this.x,
    required this.speed,
    required this.size,
    required this.color,
    required this.rotation,
    required this.isCircle,
  });

  factory _Confetti.random(math.Random rand) {
    const colors = [
      Color(0xFF1E88E5),
      Color(0xFF00BCD4),
      Color(0xFFFFD700),
      Color(0xFF4CAF50),
      Color(0xFFE91E63),
      Color(0xFFFF9800),
    ];
    return _Confetti(
      x:        rand.nextDouble(),
      speed:    0.3 + rand.nextDouble() * 0.7,
      size:     6 + rand.nextDouble() * 8,
      color:    colors[rand.nextInt(colors.length)],
      rotation: rand.nextDouble() * math.pi * 2,
      isCircle: rand.nextBool(),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Confetti> pieces;
  final double progress;
  final Size size;

  _ConfettiPainter({required this.pieces, required this.progress, required this.size});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    for (final p in pieces) {
      final double y = canvasSize.height * p.speed * progress * 1.2;
      final double x = canvasSize.width * p.x;
      final double fade = progress < 0.75 ? 1.0 : (1.0 - progress) / 0.25;
      final paint = Paint()..color = p.color.withOpacity(fade.clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotation + progress * math.pi * 2 * p.speed);

      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.progress != progress;
}
