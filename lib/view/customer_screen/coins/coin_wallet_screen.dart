import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/rect_shimmer.dart';
import 'package:movigo/view/customer_screen/coins/coin_scratch_card_screen.dart';
import 'package:movigo/view/customer_screen/coins/coin_missions_screen.dart' show MissionCard;

class CoinWalletScreen extends StatefulWidget {
  const CoinWalletScreen({super.key});

  @override
  State<CoinWalletScreen> createState() => _CoinWalletScreenState();
}

class _CoinWalletScreenState extends State<CoinWalletScreen> {
  bool _loading = true;
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _pendingCards = [];
  Future<List<Map<String, dynamic>>>? _historyFuture;
  Future<List<Map<String, dynamic>>>? _redeemRequestsFuture;

  bool _missionsLoading = true;
  List<Map<String, dynamic>> _missions = [];
  String? _claimingMissionId;

  static const int minCashRedeem = 50;

  @override
  void initState() {
    super.initState();
    _showIntroIfNeeded();
    _loadBalance();
    _historyFuture = _loadHistory();
    _redeemRequestsFuture = _loadRedeemRequests();
    _loadMissions();
  }

  Future<void> _loadMissions() async {
    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final res = await provider.getCoinMissionsApi(context);
    if (!mounted) return;
    setState(() {
      _missionsLoading = false;
      _missions = List<Map<String, dynamic>>.from(res?['data'] ?? []);
    });
  }

  Future<void> _claimMission(Map<String, dynamic> mission) async {
    final id = mission['_id']?.toString() ?? '';
    if (id.isEmpty || _claimingMissionId != null) return;
    setState(() => _claimingMissionId = id);
    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final res = await provider.claimCoinMissionApi(context, missionId: id);
    if (!mounted) return;
    setState(() => _claimingMissionId = null);

    final bool success = res?['success'] == true;
    final String message = ((res?['message'] as List?)?.isNotEmpty == true)
        ? res!['message'][0].toString()
        : (success ? 'Reward claimed' : 'Something went wrong');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    if (success) {
      await _loadMissions();
      await _loadBalance();
    }
  }

  Future<void> _loadBalance() async {
    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final res = await provider.getCoinsBalanceApi(context);
    if (mounted) {
      setState(() {
        _loading = false;
        _data = res?['data'] as Map<String, dynamic>?;
        _pendingCards = List<Map<String, dynamic>>.from(
          _data?['pending_scratch_cards'] ?? [],
        );
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadHistory() async {
    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final res = await provider.getCoinsHistoryApi(context);
    final list = res?['data'] as List? ?? [];
    return List<Map<String, dynamic>>.from(list);
  }

  Future<List<Map<String, dynamic>>> _loadRedeemRequests() async {
    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final res = await provider.getCoinRedeemRequestsApi(context);
    final list = res?['data'] as List? ?? [];
    return List<Map<String, dynamic>>.from(list);
  }

  Future<void> _refreshAll() async {
    await _loadBalance();
    await _loadMissions();
    setState(() {
      _historyFuture = _loadHistory();
      _redeemRequestsFuture = _loadRedeemRequests();
    });
  }

  Future<void> _openRedeemSheet() async {
    final int balance = (_data?['coin_balance'] ?? 0) as int;
    if (balance < minCashRedeem) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You need at least $minCashRedeem coins to redeem for cash. You have $balance.')),
      );
      return;
    }
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RedeemForCashSheet(coinBalance: balance),
    );
    if (submitted == true) {
      await _refreshAll();
    }
  }

  Future<void> _onCardScratched(String bookingId, int index) async {
    // Remove from visible list immediately so UX feels instant
    if (mounted) setState(() => _pendingCards.removeAt(index));
    // Reload balance and history to reflect updated coin count
    await _refreshAll();
  }

  Future<void> _showIntroIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('coins_intro_shown') ?? false;
    if (!shown && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showIntroSheet();
      });
    }
  }

  Future<void> _showIntroSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CoinsIntroSheet(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('coins_intro_shown', true);
  }

  Future<void> _showHowToUseSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                _HowToUseCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 8),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A), size: 22),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Coins Wallet',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                        fontFamily: AppFont.fontFamily,
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _showHowToUseSheet,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: AppColor.themeColor.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.menu_book_rounded, color: AppColor.themeColor, size: 20),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _showIntroSheet,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColor.themeColor.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.info_outline_rounded, color: AppColor.themeColor, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    return _loading
          ? const Center(child: CircularProgressIndicator(color: AppColor.themeColor))
          : RefreshIndicator(
              onRefresh: _refreshAll,
              color: AppColor.themeColor,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _historyFuture,
                      builder: (context, snapshot) {
                        // Lifetime Earning must be the TRUE all-time total,
                        // so it's summed from the full, unfiltered history
                        // (getCoinsHistoryApi) — not from the balance API's
                        // `transactions` field, which only lists currently
                        // non-expired coins and would otherwise silently
                        // shrink as 30-day-old coins expire.
                        final int lifetimeEarning = (snapshot.data ?? [])
                            .where((t) => t['type'] != 'redeemed')
                            .fold<int>(0, (s, t) => s + ((t['coins'] ?? 0) as num).toInt());
                        return _HeroBalanceCard(
                          data: _data,
                          lifetimeEarning: lifetimeEarning,
                          minRedeemCoins: minCashRedeem,
                          onRedeemTap: _openRedeemSheet,
                        );
                      },
                    ),
                    if (_pendingCards.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _PendingScratchCardsSection(
                        cards: _pendingCards,
                        onScratched: _onCardScratched,
                      ),
                    ],
                    const SizedBox(height: 16),
                    _InlineMissionsSection(
                      loading: _missionsLoading,
                      missions: _missions,
                      claimingId: _claimingMissionId,
                      onClaim: _claimMission,
                    ),
                    const SizedBox(height: 16),
                    _NavButton(
                      icon: Icons.receipt_long_rounded,
                      label: 'Transaction History',
                      subtitle: 'View all your coin transactions',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _TransactionHistoryScreen(future: _historyFuture),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _NavButton(
                      icon: Icons.local_offer_rounded,
                      label: 'Cash Redemption Requests',
                      subtitle: 'View your past redemption requests',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _RedeemRequestsScreen(future: _redeemRequestsFuture),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
  }
}

// ── Inline Missions Section (embedded directly on the wallet page) ────────────

class _InlineMissionsSection extends StatelessWidget {
  final bool loading;
  final List<Map<String, dynamic>> missions;
  final String? claimingId;
  final Future<void> Function(Map<String, dynamic> mission) onClaim;

  const _InlineMissionsSection({
    required this.loading,
    required this.missions,
    required this.claimingId,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Missions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, fontFamily: AppFont.fontFamily, color: AppColor.blackColor)),
        const SizedBox(height: 10),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: AppColor.themeColor)),
          )
        else if (missions.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFECEFF3)),
            ),
            child: const Text(
              'No missions available right now — check back soon for new coin rewards',
              style: TextStyle(fontSize: 12.5, fontFamily: AppFont.fontFamily, color: AppColor.greyColor),
            ),
          )
        else
          ...missions.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: MissionCard(
                  mission: m,
                  claiming: claimingId == m['_id']?.toString(),
                  onClaim: () => onClaim(m),
                ),
              )),
      ],
    );
  }
}

// ── Generic Navigation Button ─────────────────────────────────────────────────

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _NavButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFECEFF3)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: AppColor.themeColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: AppColor.themeColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, fontFamily: AppFont.fontFamily, color: AppColor.blackColor)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11.5, fontFamily: AppFont.fontFamily, color: AppColor.greyColor)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColor.themeColor),
          ],
        ),
      ),
    );
  }
}

// ── Redeem Requests Screen (full history) ─────────────────────────────────────

class _RedeemRequestsScreen extends StatelessWidget {
  final Future<List<Map<String, dynamic>>>? future;
  const _RedeemRequestsScreen({required this.future});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 8),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A), size: 22),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Cash Redemption Requests',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF0F172A), fontFamily: AppFont.fontFamily),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: AppColor.themeColor));
                  }
                  final requests = snapshot.data ?? [];
                  if (requests.isEmpty) {
                    return Center(
                      child: Text('No redemption requests yet', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 15, color: AppColor.greyColor)),
                    );
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                    child: _RedeemRequestsSection(requests: requests),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Transaction History Screen (full history) ──────────────────────────────────

class _TransactionHistoryScreen extends StatelessWidget {
  final Future<List<Map<String, dynamic>>>? future;
  const _TransactionHistoryScreen({required this.future});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 8),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A), size: 22),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Transaction History',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF0F172A), fontFamily: AppFont.fontFamily),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: _HistoryShimmer(),
                    );
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                    child: _TransactionHistory(transactions: snapshot.data ?? []),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hero Balance Card ─────────────────────────────────────────────────────────

class _HeroBalanceCard extends StatelessWidget {
  final Map<String, dynamic>? data;
  // Passed in from the full, unfiltered transaction history (see _body()) —
  // NOT computed from data['transactions'], which is the balance API's list
  // of currently non-expired coins only and would understate the true
  // lifetime total as coins expire after 30 days.
  final int lifetimeEarning;
  final int minRedeemCoins;
  final VoidCallback onRedeemTap;
  const _HeroBalanceCard({
    required this.data,
    required this.lifetimeEarning,
    required this.minRedeemCoins,
    required this.onRedeemTap,
  });

  @override
  Widget build(BuildContext context) {
    final int balance = (data?['coin_balance'] ?? 0) as int;
    final bool redeemEligible = balance >= minRedeemCoins;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff0A3D91), Color(0xff1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0A3D91).withOpacity(0.30),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.monetization_on_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$balance',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      fontFamily: AppFont.fontFamily,
                    ),
                  ),
                  const Text(
                    'Available Coins',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      fontFamily: AppFont.fontFamily,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Lifetime Earning stat and the Redeem action sit side by side as
          // two equal-width, equal-height blocks. IntrinsicHeight (not
          // CrossAxisAlignment.stretch) equalizes their height — stretch
          // tries to stretch children to the Row's own height, which is
          // unbounded here (this Column lives inside a SingleChildScrollView),
          // and that throws "BoxConstraints forces an infinite height".
          IntrinsicHeight(
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatChip(label: 'Lifetime Earning', value: '$lifetimeEarning', icon: Icons.trending_up_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: onRedeemTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Redeem',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, fontFamily: AppFont.fontFamily),
                              ),
                              Text(
                                redeemEligible ? 'Get Cash' : 'Need $minRedeemCoins',
                                style: const TextStyle(color: Colors.white54, fontSize: 10.5, fontFamily: AppFont.fontFamily),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.white70),
                      ],
                    ),
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
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _StatChip({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, fontFamily: AppFont.fontFamily), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10.5, fontFamily: AppFont.fontFamily), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Milestone Progress Card ───────────────────────────────────────────────────

class _MilestoneProgressCard extends StatelessWidget {
  final Map<String, dynamic>? data;
  const _MilestoneProgressCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final int weeklyCount = (data?['weekly_order_count'] ?? 0) as int;
    final int target = (data?['milestone_target'] ?? 10) as int;
    final bool reached = weeklyCount >= target;
    final double progress = (weeklyCount / target).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEFF3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: AppColor.themeColor.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.flag_rounded, size: 15, color: AppColor.themeColor),
              ),
              const SizedBox(width: 8),
              const Text('Weekly Milestone', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, fontFamily: AppFont.fontFamily, color: AppColor.blackColor)),
              const Spacer(),
              if (reached)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 14),
                      const SizedBox(width: 4),
                      Text('Bonus Earned', style: TextStyle(color: Colors.green.shade700, fontSize: 11.5, fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.grey.shade200,
              color: reached ? Colors.green : AppColor.themeColor,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            reached
                ? '$target/$target orders completed this week — Bonus Credited!'
                : '$weeklyCount/$target orders this week · ${target - weeklyCount} more for bonus coins',
            style: TextStyle(
              fontSize: 12.5,
              color: reached ? Colors.green.shade700 : AppColor.greyColor,
              fontFamily: AppFont.fontFamily,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── How To Use Card ───────────────────────────────────────────────────────────

class _HowToUseCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const rules = [
      (Icons.account_balance_wallet_outlined, 'Redeem 50+ coins for cash to your UPI ID'),
      (Icons.currency_rupee_rounded, '1 Coin = ₹1 cash payout'),
      (Icons.schedule_rounded, 'Coins expire in 30 days from earning'),
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEFF3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How to Use Coins', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, fontFamily: AppFont.fontFamily, color: AppColor.blackColor)),
          const SizedBox(height: 14),
          ...rules.map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColor.themeColor.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(r.$1, size: 16, color: AppColor.themeColor),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(r.$2, style: const TextStyle(fontSize: 13, fontFamily: AppFont.fontFamily, color: AppColor.blackColor))),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

// ── Transaction History ───────────────────────────────────────────────────────

class _TransactionHistory extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;
  const _TransactionHistory({required this.transactions});

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        alignment: Alignment.center,
        child: const Column(
          children: [
            Icon(Icons.monetization_on_outlined, size: 40, color: Color(0xFFCBD5E1)),
            SizedBox(height: 12),
            Text('No transactions yet', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 15, color: AppColor.greyColor)),
            SizedBox(height: 4),
            Text('Complete an order to earn your first coins!', style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12.5, color: AppColor.greyColor)),
          ],
        ),
      );
    }

    // Group by date
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final t in transactions) {
      final raw = t['createdAt']?.toString() ?? '';
      final dt = DateTime.tryParse(raw);
      final key = dt != null
          ? '${dt.day.toString().padLeft(2,'0')} ${_monthName(dt.month)} ${dt.year}'
          : 'Unknown';
      grouped.putIfAbsent(key, () => []).add(t);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Transaction History', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, fontFamily: AppFont.fontFamily, color: AppColor.blackColor)),
        const SizedBox(height: 12),
        ...grouped.entries.map((e) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(e.key, style: const TextStyle(fontSize: 12, color: AppColor.greyColor, fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily)),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFECEFF3)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Column(
                children: e.value.map((t) => _TransactionRow(txn: t)).toList(),
              ),
            ),
          ],
        )),
      ],
    );
  }

  String _monthName(int m) => ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];
}

// Friendly labels for each CoinTransaction type, per the finalized coin spec.
String _coinTypeLabel(String type) {
  switch (type) {
    case 'order_reward':
      return 'Order reward';
    case 'first_order_seed':
      return 'Welcome bonus';
    case 'milestone_bonus':
      return 'Milestone bonus';
    case 'mission_reward':
      return 'Mission reward';
    case 'redeemed':
      return 'Redeemed';
    default:
      return type;
  }
}

class _TransactionRow extends StatelessWidget {
  final Map<String, dynamic> txn;
  const _TransactionRow({required this.txn});

  @override
  Widget build(BuildContext context) {
    final bool isRedeemed = txn['type'] == 'redeemed';
    final bool isExpired = txn['is_expired'] == true;
    final int coins = ((txn['coins'] ?? 0) as num).toInt().abs();
    final String label = _coinTypeLabel(txn['type']?.toString() ?? '');
    final String desc = txn['description']?.toString() ?? '';

    int? daysLeft;
    final rawExpiry = txn['expires_at']?.toString();
    if (!isRedeemed && rawExpiry != null && rawExpiry.isNotEmpty) {
      final expiryDt = DateTime.tryParse(rawExpiry);
      if (expiryDt != null) {
        daysLeft = expiryDt.difference(DateTime.now()).inDays;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRedeemed ? Colors.orange.shade50 : Colors.green.shade50,
            ),
            child: Icon(
              isRedeemed ? Icons.local_offer_rounded : Icons.add_circle_rounded,
              color: isRedeemed ? Colors.orange.shade600 : Colors.green.shade600,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 13, fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, color: AppColor.blackColor),
                ),
                if (desc.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      desc,
                      style: const TextStyle(fontSize: 11, fontFamily: AppFont.fontFamily, color: AppColor.greyColor),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (isExpired)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Expired',
                        style: TextStyle(fontSize: 10.5, color: AppColor.greyColor, fontFamily: AppFont.fontFamily),
                      ),
                    ),
                  )
                else if (!isRedeemed && daysLeft != null && daysLeft >= 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: daysLeft <= 3 ? Colors.red.shade50 : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Expires in $daysLeft day${daysLeft == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: daysLeft <= 3 ? Colors.red.shade600 : Colors.blue.shade600,
                          fontFamily: AppFont.fontFamily,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            isRedeemed ? '-$coins' : '+$coins',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontFamily: AppFont.fontFamily,
              fontSize: 14,
              color: isRedeemed ? Colors.orange.shade700 : Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Redeem For Cash Button ────────────────────────────────────────────────────

class _RedeemForCashButton extends StatelessWidget {
  final int coinBalance;
  final int minCoins;
  final VoidCallback onTap;
  const _RedeemForCashButton({
    required this.coinBalance,
    required this.minCoins,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool eligible = coinBalance >= minCoins;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColor.themeColor.withOpacity(0.25)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: AppColor.themeColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(Icons.account_balance_wallet_rounded, color: AppColor.themeColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Redeem Coins for Cash', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, fontFamily: AppFont.fontFamily, color: AppColor.blackColor)),
                  const SizedBox(height: 2),
                  Text(
                    eligible
                        ? 'Get paid to your UPI ID'
                        : 'Earn at least $minCoins coins to redeem (you have $coinBalance)',
                    style: TextStyle(fontSize: 11.5, fontFamily: AppFont.fontFamily, color: AppColor.greyColor),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: eligible ? AppColor.themeColor : Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

// ── Redeem Requests History Section ───────────────────────────────────────────

class _RedeemRequestsSection extends StatelessWidget {
  final List<Map<String, dynamic>> requests;
  const _RedeemRequestsSection({required this.requests});

  Color _statusColor(String status) {
    switch (status) {
      case 'Paid':
        return Colors.green;
      case 'Rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Cash Redemption Requests', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, fontFamily: AppFont.fontFamily, color: AppColor.blackColor)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFECEFF3)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            children: requests.map((r) {
              final int coins = ((r['coins'] ?? 0) as num).toInt();
              final String status = r['status']?.toString() ?? 'Pending';
              final String method = r['payout_method']?.toString() ?? '';
              final Color color = _statusColor(status);
              final rawDate = r['createdAt']?.toString() ?? '';
              final dt = DateTime.tryParse(rawDate);
              final dateStr = dt != null ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}' : '';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.1)),
                      child: Icon(
                        method == 'bank' ? Icons.account_balance_rounded : Icons.qr_code_rounded,
                        color: color,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('₹$coins via ${method == 'bank' ? 'Bank Transfer' : 'UPI'}',
                              style: const TextStyle(fontSize: 13, fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600, color: AppColor.blackColor)),
                          if (dateStr.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Text(dateStr, style: const TextStyle(fontSize: 11, fontFamily: AppFont.fontFamily, color: AppColor.greyColor)),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                      child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily, color: color)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── Redeem For Cash Bottom Sheet ──────────────────────────────────────────────

class _RedeemForCashSheet extends StatefulWidget {
  final int coinBalance;
  const _RedeemForCashSheet({required this.coinBalance});

  @override
  State<_RedeemForCashSheet> createState() => _RedeemForCashSheetState();
}

class _RedeemForCashSheetState extends State<_RedeemForCashSheet> {
  static const int minCoins = 50;
  static const String _method = 'upi';
  bool _submitting = false;
  late final TextEditingController _coinsCtrl;
  final _upiCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _coinsCtrl = TextEditingController(text: '$minCoins');
  }

  @override
  void dispose() {
    _coinsCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final int coins = int.tryParse(_coinsCtrl.text.trim()) ?? 0;
    if (coins < minCoins) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Minimum $minCoins coins required')));
      return;
    }
    if (coins > widget.coinBalance) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You don\'t have enough coins')));
      return;
    }
    if (_upiCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your UPI ID')));
      return;
    }

    setState(() => _submitting = true);
    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final res = await provider.createCoinRedeemRequestApi(
      context,
      coins: coins,
      payoutMethod: _method,
      bankAccountNumber: '',
      bankIfsc: '',
      bankAccountHolder: '',
      upiId: _upiCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    final bool success = res?['success'] == true;
    final String message = ((res?['message'] as List?)?.isNotEmpty == true)
        ? res!['message'][0].toString()
        : (success ? 'Redemption request submitted' : 'Something went wrong');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    if (success) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const Text('Redeem Coins for Cash', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, fontFamily: AppFont.fontFamily, color: AppColor.blackColor)),
              const SizedBox(height: 4),
              Text('You have ${widget.coinBalance} coins available · Minimum $minCoins coins per request',
                  style: TextStyle(fontSize: 12.5, fontFamily: AppFont.fontFamily, color: AppColor.greyColor)),
              const SizedBox(height: 18),
              Text('Coins to redeem (₹1 = 1 coin)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily, color: AppColor.blackColor)),
              const SizedBox(height: 6),
              TextField(
                controller: _coinsCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 18),
              _LabeledField(label: 'UPI ID', controller: _upiCtrl, hint: 'yourname@upi'),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColor.themeColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: _submitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Submit Request', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: AppFont.fontFamily, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Once submitted, our team will review and pay the amount to your account manually within a few business days.',
                style: TextStyle(fontSize: 11.5, fontFamily: AppFont.fontFamily, color: AppColor.greyColor, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? hint;
  const _LabeledField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily, color: AppColor.greyColor)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          decoration: InputDecoration(
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}

// ── Pending Scratch Cards Section ────────────────────────────────────────────

class _PendingScratchCardsSection extends StatelessWidget {
  final List<Map<String, dynamic>> cards;
  final Future<void> Function(String bookingId, int index) onScratched;

  const _PendingScratchCardsSection({
    required this.cards,
    required this.onScratched,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEFF3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.card_giftcard_rounded, size: 15, color: Color(0xFFB8860B)),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Delivery Rewards',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, fontFamily: AppFont.fontFamily, color: AppColor.blackColor),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColor.themeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${cards.length} pending',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, fontFamily: AppFont.fontFamily, color: AppColor.themeColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Coins are added to your wallet automatically after each delivery — tap to view',
            style: TextStyle(fontSize: 12, color: AppColor.greyColor, fontFamily: AppFont.fontFamily),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.6,
            ),
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final card = cards[index];
              return _ScratchCardTile(
                key: ValueKey(card['booking_id']?.toString() ?? '$index'),
                bookingId: card['booking_id']?.toString() ?? '',
                coins: (card['coins'] ?? 0) as int,
                bookingCode: card['booking_code']?.toString() ?? '',
                onScratched: () => onScratched(card['booking_id']?.toString() ?? '', index),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ScratchCardTile extends StatefulWidget {
  final String bookingId;
  final int coins;
  final String bookingCode;
  final VoidCallback onScratched;

  const _ScratchCardTile({
    super.key,
    required this.bookingId,
    required this.coins,
    required this.bookingCode,
    required this.onScratched,
  });

  @override
  State<_ScratchCardTile> createState() => _ScratchCardTileState();
}

class _ScratchCardTileState extends State<_ScratchCardTile> {
  bool _tapped = false;

  Future<void> _onTap() async {
    if (_tapped) return;
    setState(() => _tapped = true);
    final claimed = await CoinScratchCardScreen.showIfNeeded(
      context,
      bookingId: widget.bookingId,
      coins: widget.coins,
    );
    if (!mounted) return;
    if (claimed) {
      widget.onScratched();
    } else {
      // User backed out before scratching/claiming — nothing was earned,
      // so put the tile back to its untapped state instead of leaving it
      // stuck on "Opening..." and silently dropping the card.
      setState(() => _tapped = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _tapped
                ? [const Color(0xFFFFD700), const Color(0xFFFFA500)]
                : [const Color(0xFF1A3A6B), const Color(0xFF091932)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: _tapped ? null : Border.all(color: const Color(0xFFFFC107), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: _tapped
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.monetization_on_rounded, color: Color(0xFF0D2137), size: 22),
                    SizedBox(height: 2),
                    Text('Opening...', style: TextStyle(color: Color(0xFF0D2137), fontSize: 10, fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w600)),
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.touch_app_rounded, color: Colors.white70, size: 26),
                  const SizedBox(height: 4),
                  const Text(
                    'Tap to View',
                    style: TextStyle(color: Colors.white70, fontSize: 10, fontFamily: AppFont.fontFamily),
                  ),
                  if (widget.bookingCode.isNotEmpty)
                    Text(
                      '#${widget.bookingCode}',
                      style: const TextStyle(color: Colors.white38, fontSize: 9, fontFamily: AppFont.fontFamily),
                    ),
                ],
              ),
      ),
    );
  }
}

class _HistoryShimmer extends StatelessWidget {
  const _HistoryShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RectShimmer(height: 16, width: 140),
        const SizedBox(height: 12),
        ...List.generate(
          3,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: RectShimmer(height: 64, width: double.infinity, radius: 14),
          ),
        ),
      ],
    );
  }
}

// ── One-time Intro Bottom Sheet ───────────────────────────────────────────────

class _CoinsIntroSheet extends StatelessWidget {
  const _CoinsIntroSheet();

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24, 12, 24, 24 + MediaQuery.of(context).padding.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
          ),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xff0A3D91), Color(0xff1565C0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.monetization_on_rounded, color: Colors.white, size: 34),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Movigo Coins',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, fontFamily: AppFont.fontFamily),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Earn coins on every order,\nredeem them for real cash',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13.5, fontFamily: AppFont.fontFamily, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _InfoRow(icon: Icons.add_circle_rounded, color: Colors.green, text: 'Scratch a card on every delivered order to win 1–5 coins'),
          const SizedBox(height: 12),
          _InfoRow(icon: Icons.star_rounded, color: Colors.amber, text: 'Bonus coins every week on 10+ orders (up to 50 bonus coins)'),
          const SizedBox(height: 12),
          _InfoRow(icon: Icons.account_balance_wallet_rounded, color: AppColor.themeColor, text: 'Redeem 50+ coins for cash to your UPI ID'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, color: Colors.amber.shade700, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Coins expire in 30 days from the date they were earned',
                    style: TextStyle(fontSize: 12.5, fontFamily: AppFont.fontFamily, color: Color(0xFF6B4C00)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColor.themeColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: const Text('Got It', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: AppFont.fontFamily, color: Colors.white)),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(text, style: const TextStyle(fontSize: 13.5, fontFamily: AppFont.fontFamily, color: AppColor.blackColor, height: 1.4)),
          ),
        ),
      ],
    );
  }
}
