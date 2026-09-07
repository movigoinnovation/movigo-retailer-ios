import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';

/// "Complete N delivered orders in the window, then claim X coins."
/// The retailer-side twin of the driver app's mission cards. Progress is
/// computed server-side from real delivered orders; this screen only shows it
/// and lets the retailer claim once `status == 'completed'`.
class CoinMissionsScreen extends StatefulWidget {
  const CoinMissionsScreen({super.key});

  @override
  State<CoinMissionsScreen> createState() => _CoinMissionsScreenState();
}

class _CoinMissionsScreenState extends State<CoinMissionsScreen> {
  bool _loading = true;
  String? _claimingId;
  List<Map<String, dynamic>> _missions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final res = await provider.getCoinMissionsApi(context);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _missions = List<Map<String, dynamic>>.from(res?['data'] ?? []);
    });
  }

  Future<void> _claim(Map<String, dynamic> mission) async {
    final id = mission['_id']?.toString() ?? '';
    if (id.isEmpty || _claimingId != null) return;
    setState(() => _claimingId = id);
    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final res = await provider.claimCoinMissionApi(context, missionId: id);
    if (!mounted) return;
    setState(() => _claimingId = null);

    final bool success = res?['success'] == true;
    final String message = ((res?['message'] as List?)?.isNotEmpty == true)
        ? res!['message'][0].toString()
        : (success ? 'Reward claimed' : 'Something went wrong');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    if (success) await _load();
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
                      'Coin Missions',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                        fontFamily: AppFont.fontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColor.themeColor))
                  : RefreshIndicator(
                      color: AppColor.themeColor,
                      onRefresh: _load,
                      child: _missions.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 120),
                                Icon(Icons.flag_outlined, size: 44, color: Color(0xFFCBD5E1)),
                                SizedBox(height: 12),
                                Center(
                                  child: Text(
                                    'No missions available right now',
                                    style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 15, color: AppColor.greyColor),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Center(
                                  child: Text(
                                    'Check back soon for new coin rewards',
                                    style: TextStyle(fontFamily: AppFont.fontFamily, fontSize: 12.5, color: AppColor.greyColor),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                              itemCount: _missions.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, i) => MissionCard(
                                mission: _missions[i],
                                claiming: _claimingId == _missions[i]['_id']?.toString(),
                                onClaim: () => _claim(_missions[i]),
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

class MissionCard extends StatelessWidget {
  final Map<String, dynamic> mission;
  final bool claiming;
  final VoidCallback onClaim;
  const MissionCard({required this.mission, required this.claiming, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    final String title = mission['title_en']?.toString() ?? 'Mission';
    final String desc = mission['description_en']?.toString() ?? '';
    final String icon = mission['icon']?.toString() ?? '🎯';
    final int target = ((mission['target_orders'] ?? 1) as num).toInt();
    final int progress = ((mission['progress'] ?? 0) as num).toInt();
    final int remaining = ((mission['remaining'] ?? 0) as num).toInt();
    final int reward = ((mission['reward_coins'] ?? 0) as num).toInt();
    final num minFare = (mission['min_order_fare'] ?? 0) as num;
    final String status = mission['status']?.toString() ?? 'locked';
    final double pct = target > 0 ? (progress / target).clamp(0.0, 1.0) : 0.0;
    final bool completed = status == 'completed';
    final bool claimed = status == 'claimed';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: claimed ? Colors.green.shade200 : const Color(0xFFECEFF3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(icon, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, fontFamily: AppFont.fontFamily, color: AppColor.blackColor)),
                    if (desc.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(desc,
                            style: const TextStyle(fontSize: 12, fontFamily: AppFont.fontFamily, color: AppColor.greyColor)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                child: Text('+$reward coins',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, fontFamily: AppFont.fontFamily, color: Color(0xFFB8860B))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: claimed ? 1.0 : pct,
              minHeight: 10,
              backgroundColor: Colors.grey.shade200,
              color: (completed || claimed) ? Colors.green : AppColor.themeColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            claimed
                ? '$target/$target orders completed'
                : completed
                    ? '$target/$target orders — ready to claim!'
                    : '$progress/$target orders · $remaining more to go',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              fontFamily: AppFont.fontFamily,
              color: (completed || claimed) ? Colors.green.shade700 : AppColor.greyColor,
            ),
          ),
          if (minFare > 0)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('Only orders of ₹${minFare.toStringAsFixed(0)}+ count',
                  style: const TextStyle(fontSize: 10.5, fontFamily: AppFont.fontFamily, color: AppColor.greyColor)),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (completed && !claiming) ? onClaim : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: claimed ? Colors.green.shade50 : AppColor.themeColor,
                disabledBackgroundColor: claimed ? Colors.green.shade50 : Colors.grey.shade200,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: claiming
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      claimed ? 'Claimed ✓' : (completed ? 'Claim $reward Coins' : 'Locked'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFamily: AppFont.fontFamily,
                        color: claimed
                            ? Colors.green.shade700
                            : (completed ? Colors.white : AppColor.greyColor),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
