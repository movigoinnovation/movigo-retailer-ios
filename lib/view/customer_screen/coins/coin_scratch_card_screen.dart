import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_color.dart';

/// Post-delivery coin reward.
///
/// The scratch card is gone — coins are now credited straight to the wallet
/// the moment the ride is Delivered (backend: coinsService.handleRetailerCoinsCredit).
/// This screen is just the one-time "you earned N coins" acknowledgement popup.
/// The class name / [showIfNeeded] signature are kept so existing call sites
/// (booking detail, coin wallet) don't have to change.
class CoinScratchCardScreen {
  const CoinScratchCardScreen._();

  static const _seenIdsKey = 'scratch_card_seen_ids';

  /// Shows the reward popup once per booking. Returns true if the retailer
  /// acknowledged it (server told to stop surfacing it), false if it was
  /// dismissed or already seen.
  static Future<bool> showIfNeeded(
    BuildContext context, {
    required String bookingId,
    required int coins,
  }) async {
    if (bookingId.isEmpty || coins <= 0) return false;

    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList(_seenIdsKey) ?? [];
    if (seen.contains(bookingId)) return false;

    if (!context.mounted) return false;
    final acknowledged = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) => _CoinRewardDialog(coins: coins),
    );

    // Credited already — this only tells the backend to stop returning the
    // "pending" flag, and records it locally so it never pops again.
    if (!seen.contains(bookingId)) {
      seen.add(bookingId);
      await prefs.setStringList(_seenIdsKey, seen);
    }
    if (context.mounted) {
      final provider = Provider.of<PostApiProvider>(context, listen: false);
      // Fire-and-forget ack; a failure just means the popup may show once more.
      await provider.scratchSeenApi(context, bookingId: bookingId);
    }

    return acknowledged == true;
  }
}

class _CoinRewardDialog extends StatelessWidget {
  final int coins;
  const _CoinRewardDialog({required this.coins});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 72,
              width: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4D6),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF2C94C), width: 2),
              ),
              alignment: Alignment.center,
              child: const Text('🪙', style: TextStyle(fontSize: 34)),
            ),
            const SizedBox(height: 18),
            Text(
              '+$coins coins',
              style: const TextStyle(
                fontFamily: AppFont.fontFamily,
                fontWeight: FontWeight.w800,
                fontSize: 26,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'added to your wallet',
              style: TextStyle(
                fontFamily: AppFont.fontFamily,
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'for completing this delivery',
              style: TextStyle(
                fontFamily: AppFont.fontFamily,
                fontSize: 12,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColor.themeColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Awesome!',
                  style: TextStyle(
                    fontFamily: AppFont.fontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
