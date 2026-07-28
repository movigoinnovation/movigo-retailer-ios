import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/utilities/app_font.dart';

/// Scratch-card reveal shown after a retailer's order is Delivered.
/// The coin amount (1-5) is decided entirely by the server (scratch_card_coins
/// on the booking) — this widget only reveals that stored number, it never
/// rolls its own random value.
class CoinScratchCardScreen extends StatefulWidget {
  final String bookingId;
  final int coins;

  const CoinScratchCardScreen({
    super.key,
    required this.bookingId,
    required this.coins,
  });

  static const _seenIdsKey = 'scratch_card_seen_ids';

  /// Shows the scratch card once per booking. The SharedPreferences seen-set
  /// is a backup guard in case the server's scratch_card_pending flag is
  /// stale by the time this is checked (e.g. cached booking-detail response).
  static Future<void> showIfNeeded(
    BuildContext context, {
    required String bookingId,
    required int coins,
  }) async {
    if (bookingId.isEmpty || coins <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList(_seenIdsKey) ?? [];
    if (seen.contains(bookingId)) return;

    if (!context.mounted) return;
    await Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black54,
        pageBuilder: (_, __, ___) => CoinScratchCardScreen(
          bookingId: bookingId,
          coins: coins,
        ),
      ),
    );
  }

  @override
  State<CoinScratchCardScreen> createState() => _CoinScratchCardScreenState();
}

class _CoinScratchCardScreenState extends State<CoinScratchCardScreen>
    with SingleTickerProviderStateMixin {
  bool _revealed = false;
  bool _seenConfirmed = false;
  late final AnimationController _revealCtrl;
  late final Animation<double> _revealScale;

  @override
  void initState() {
    super.initState();
    _revealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _revealScale = CurvedAnimation(parent: _revealCtrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _revealCtrl.dispose();
    super.dispose();
  }

  Future<void> _reveal() async {
    if (_revealed) return;
    setState(() => _revealed = true);
    _revealCtrl.forward();
    await _markSeen();
    if (mounted) setState(() => _seenConfirmed = true);
  }

  Future<void> _markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList(CoinScratchCardScreen._seenIdsKey) ?? [];
    if (!seen.contains(widget.bookingId)) {
      seen.add(widget.bookingId);
      await prefs.setStringList(CoinScratchCardScreen._seenIdsKey, seen);
    }
    if (!mounted) return;
    final provider = Provider.of<PostApiProvider>(context, listen: false);
    // Awaited so the wallet screen's post-close refresh sees scratch_card_pending
    // already cleared server-side, instead of racing it and showing the card again.
    await provider.scratchSeenApi(context, bookingId: widget.bookingId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          decoration: BoxDecoration(
            color: const Color(0xFF0D2137),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'You earned a scratch card!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFamily: AppFont.fontFamily,
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _reveal,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: _revealed
                      ? ScaleTransition(
                          key: const ValueKey('revealed'),
                          scale: _revealScale,
                          child: _RevealedFace(coins: widget.coins),
                        )
                      : const _FoilFace(key: ValueKey('foil')),
                ),
              ),
              const SizedBox(height: 22),
              if (_revealed)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _seenConfirmed ? () => Navigator.of(context).pop() : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      disabledBackgroundColor: const Color(0xFFFFC107).withOpacity(0.6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _seenConfirmed
                        ? const Text(
                            'Awesome!',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontFamily: AppFont.fontFamily,
                              color: Color(0xFF0D2137),
                            ),
                          )
                        : const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF0D2137),
                            ),
                          ),
                  ),
                )
              else
                const Text(
                  'Tap the card to scratch & reveal',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12.5,
                    fontFamily: AppFont.fontFamily,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoilFace extends StatelessWidget {
  const _FoilFace({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 140,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFBFC7D1), Color(0xFF8A93A0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFC107), width: 2),
      ),
      child: const Center(
        child: Icon(Icons.touch_app_rounded, color: Color(0xFF0D2137), size: 40),
      ),
    );
  }
}

class _RevealedFace extends StatelessWidget {
  final int coins;
  const _RevealedFace({required this.coins});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 140,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🪙', style: TextStyle(fontSize: 32)),
            Text(
              '+$coins',
              style: const TextStyle(
                color: Color(0xFF0D2137),
                fontSize: 30,
                fontWeight: FontWeight.w900,
                fontFamily: AppFont.fontFamily,
              ),
            ),
            const Text(
              'coins won!',
              style: TextStyle(
                color: Color(0xFF0D2137),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: AppFont.fontFamily,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
