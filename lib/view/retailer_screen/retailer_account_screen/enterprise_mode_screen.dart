import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';

/// Movigo Enterprise — feature showcase + an "I'm interested" form.
/// The form posts a BusinessLead (source: retailer_app) which the team
/// reviews in the admin panel's Business Leads view. It does NOT enroll the
/// retailer into Business Mode — that still goes through registration + approval.
class EnterpriseModeScreen extends StatefulWidget {
  const EnterpriseModeScreen({super.key});

  @override
  State<EnterpriseModeScreen> createState() => _EnterpriseModeScreenState();
}

class _EnterpriseModeScreenState extends State<EnterpriseModeScreen> {
  final _bizCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  bool _submitting = false;
  bool _done = false;

  static const List<List<String>> _features = [
    ['account_balance_wallet_rounded', 'Company wallet',
        'One prepaid wallet funds every employee’s deliveries — no per-order cash.'],
    ['groups_rounded', 'Employee accounts',
        'Add your staff, set a spending budget per employee, remove them anytime.'],
    ['handshake_rounded', 'Preferred drivers',
        'Build a trusted pool of drivers who get your company’s orders first.'],
    ['location_on_rounded', 'Live team tracking',
        'See every active delivery your team places on one live map.'],
    ['dashboard_rounded', 'Business dashboard',
        'All company bookings, spend and history in a single view.'],
    ['receipt_long_rounded', 'GST invoices',
        'Monthly consolidated tax invoices, generated automatically.'],
    ['bookmark_rounded', 'Saved business locations',
        'A shared address book for pickups and drops across the whole team.'],
  ];

  static const Map<String, IconData> _icons = {
    'account_balance_wallet_rounded': Icons.account_balance_wallet_rounded,
    'groups_rounded': Icons.groups_rounded,
    'handshake_rounded': Icons.handshake_rounded,
    'location_on_rounded': Icons.location_on_rounded,
    'dashboard_rounded': Icons.dashboard_rounded,
    'receipt_long_rounded': Icons.receipt_long_rounded,
    'bookmark_rounded': Icons.bookmark_rounded,
  };

  @override
  void initState() {
    super.initState();
    final u = Provider.of<UserController>(context, listen: false);
    _bizCtrl.text = u.getBusinessName;
    _nameCtrl.text = u.getUserName;
    _phoneCtrl.text = u.getUserMobile;
    _emailCtrl.text = u.getUserEmail;
  }

  @override
  void dispose() {
    for (final c in [_bizCtrl, _nameCtrl, _phoneCtrl, _emailCtrl, _msgCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final biz = _bizCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    if (biz.isEmpty) return _snack('Enter your business name');
    if (name.isEmpty) return _snack('Enter a contact name');
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      return _snack('Enter a valid phone number');
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return _snack('Enter a valid email');
    }

    setState(() => _submitting = true);
    final res = await Provider.of<PostApiProvider>(context, listen: false)
        .submitBusinessLeadApi(
      context,
      businessName: biz,
      contactName: name,
      phoneNumber: phone,
      email: email,
      message: _msgCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (res != null && res['success'] == true) {
      setState(() => _done = true);
    } else {
      _snack((res?['message'] is List && (res!['message'] as List).isNotEmpty)
          ? res['message'][0].toString()
          : 'Something went wrong. Please try again.');
    }
  }

  void _snack(String m) => SnackBarToastMessage.showSnackBar(context, m);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        backgroundColor: AppColor.themeColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Movigo Enterprise',
            style: TextStyle(
                fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w700, fontSize: 17)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColor.themeColor, Color(0xFF13315C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Run deliveries for your whole company',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          fontFamily: AppFont.fontFamily)),
                  SizedBox(height: 8),
                  Text(
                    'One prepaid wallet, staff accounts with budgets, preferred '
                    'drivers, live tracking and GST invoices — built for teams.',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        height: 1.4,
                        fontFamily: AppFont.fontFamily),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text("What you get",
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColor.blackColor,
                    fontFamily: AppFont.fontFamily)),
            const SizedBox(height: 10),
            ..._features.map((f) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFECEFF3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColor.themeColor.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(_icons[f[0]] ?? Icons.check_rounded,
                            color: AppColor.themeColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f[1],
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColor.blackColor,
                                    fontFamily: AppFont.fontFamily)),
                            const SizedBox(height: 3),
                            Text(f[2],
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    height: 1.35,
                                    color: Color(0xFF64748B),
                                    fontFamily: AppFont.fontFamily)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 12),

            // Interest form / success
            if (_done)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF7EE),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF16A34A).withOpacity(0.3)),
                ),
                child: Column(
                  children: const [
                    Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 34),
                    SizedBox(height: 10),
                    Text('Request received',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF166534),
                            fontFamily: AppFont.fontFamily)),
                    SizedBox(height: 4),
                    Text('Our enterprise team will reach out within 1 business day.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF166534),
                            fontFamily: AppFont.fontFamily)),
                  ],
                ),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFECEFF3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Interested? Tell us about your business',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppColor.blackColor,
                            fontFamily: AppFont.fontFamily)),
                    const SizedBox(height: 12),
                    _field('Business name', _bizCtrl),
                    _field('Contact name', _nameCtrl),
                    _field('Phone number', _phoneCtrl,
                        keyboard: TextInputType.phone),
                    _field('Email', _emailCtrl,
                        keyboard: TextInputType.emailAddress),
                    _field('Your requirements (optional)', _msgCtrl,
                        maxLines: 3),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColor.themeColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text("I'm interested",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: AppFont.fontFamily)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {TextInputType keyboard = TextInputType.text, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 13.5, fontFamily: AppFont.fontFamily),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
              fontSize: 12.5, color: Color(0xFF64748B), fontFamily: AppFont.fontFamily),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFD8DEE6))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFD8DEE6))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColor.themeColor)),
        ),
      ),
    );
  }
}
