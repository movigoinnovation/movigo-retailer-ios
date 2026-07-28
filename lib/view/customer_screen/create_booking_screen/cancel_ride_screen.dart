import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/get_navigation.dart';
import 'package:http/http.dart' as http;

import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_config_provider.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_header.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'bookingHelpAndSupport.dart';

class CancelRideScreen extends StatefulWidget {
  final String bookingId;
  final String? bookingCode;
  final String userType;

  const CancelRideScreen({
    super.key,
    required this.bookingId,
    this.bookingCode,
    this.userType = "",
  });

  @override
  State<CancelRideScreen> createState() => _CancelRideScreenState();
}

class _CancelRideScreenState extends State<CancelRideScreen> {
  String? _selectedReason;
  final TextEditingController _otherController = TextEditingController();
  bool _isLoading = false;
  bool _showCannotCancelMessage = false;

  static const List<String> _reasons = [
    "Changed my mind",
    "Booked by mistake",
    "Waiting time is too long",
    "Found another option",
    "Other",
  ];

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedReason == null) {
      SnackBarToastMessage.showSnackBar(
          context, "Please select a reason to cancel.");
      return;
    }

    final reason = _selectedReason == "Other"
        ? _otherController.text.trim()
        : _selectedReason!;

    if (_selectedReason == "Other" && reason.isEmpty) {
      SnackBarToastMessage.showSnackBar(
          context, "Please describe your reason.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final url = Uri.parse(
        "${AppConfigProvider.apiUrl}booking/cancel_by_customer/${widget.bookingId}",
      );
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer ${AppConstant.token}',
        },
        body: jsonEncode({'cancellation_reason': reason}),
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        SnackBarToastMessage.showSnackBar(context, "Ride cancelled successfully.");
        Get.offAll(() => const CustomBottomNav(
              userType: UserType.retailer,
              initialIndex: 1,
            ));
        return;
      }

      // Determine if the booking was already accepted
      final rawMsg = body['message'];
      final msg = (rawMsg is List
              ? rawMsg.isNotEmpty ? rawMsg[0].toString() : ""
              : rawMsg?.toString() ?? "")
          .toLowerCase();

      if (msg.contains('accepted') || msg.contains('cannot cancel')) {
        setState(() => _showCannotCancelMessage = true);
      } else {
        SnackBarToastMessage.showSnackBar(
          context,
          msg.isNotEmpty ? msg : "Unable to cancel. Please try again.",
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      SnackBarToastMessage.showSnackBar(
          context, "Something went wrong. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size.width * 0.04),
            child: CommonAppBar(
              title: "Cancel Ride",
              onBack: () => Navigator.of(context).maybePop(),
            ),
          ),
          Expanded(
            child: _showCannotCancelMessage
                ? _buildCannotCancelView(size)
                : _buildReasonView(size),
          ),
        ],
      ),
    );
  }

  // ── Reason Selection ────────────────────────────────────────────────────────
  Widget _buildReasonView(Size size) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: size.width * 0.05,
        vertical: size.height * 0.02,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Why are you cancelling?",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFamily: AppFont.fontFamily,
              color: AppColor.blackColor,
            ),
          ),
          SizedBox(height: size.height * 0.006),
          const Text(
            "Help us improve by telling us what went wrong.",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              fontFamily: AppFont.fontFamily,
              color: AppColor.hintTextColor,
            ),
          ),
          SizedBox(height: size.height * 0.025),

          ..._reasons.map((r) => _reasonTile(r, size)),

          if (_selectedReason == "Other") ...[
            SizedBox(height: size.height * 0.015),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColor.borderColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _otherController,
                maxLines: 3,
                maxLength: 200,
                style: const TextStyle(
                  fontSize: 14,
                  fontFamily: AppFont.fontFamily,
                  color: AppColor.blackColor,
                ),
                decoration: const InputDecoration(
                  hintText: "Please describe your reason...",
                  hintStyle: TextStyle(
                    fontSize: 13,
                    fontFamily: AppFont.fontFamily,
                    color: AppColor.hintTextColor,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(14),
                  counterStyle:
                      TextStyle(fontSize: 11, color: AppColor.greyColor),
                ),
              ),
            ),
          ],

          SizedBox(height: size.height * 0.04),

          _isLoading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: AppColor.themeColor))
              : SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColor.redAppColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text(
                      "Cancel Ride",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppFont.fontFamily,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

          SizedBox(height: size.height * 0.03),
        ],
      ),
    );
  }

  Widget _reasonTile(String reason, Size size) {
    final bool selected = _selectedReason == reason;
    return GestureDetector(
      onTap: () => setState(() => _selectedReason = reason),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: EdgeInsets.only(bottom: size.height * 0.012),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColor.themeColor : AppColor.borderColor,
            width: selected ? 1.8 : 1,
          ),
          color: selected
              ? AppColor.themeColor.withOpacity(0.05)
              : Colors.white,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                reason,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w400,
                  fontFamily: AppFont.fontFamily,
                  color: selected
                      ? AppColor.themeColor
                      : AppColor.thirdTextColor,
                ),
              ),
            ),
            Container(
              height: 20,
              width: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      selected ? AppColor.themeColor : AppColor.greyColor,
                  width: 1.5,
                ),
                color: selected ? AppColor.themeColor : Colors.white,
              ),
              child: selected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ── Cannot Cancel (driver already accepted) ─────────────────────────────────
  Widget _buildCannotCancelView(Size size) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: size.width * 0.06,
        vertical: size.height * 0.04,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: 90,
            width: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.amber.shade50,
            ),
            child: const Icon(
              Icons.directions_car_rounded,
              size: 50,
              color: Colors.amber,
            ),
          ),
          SizedBox(height: size.height * 0.03),

          const Text(
            "Your Driver is On the Way",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              fontFamily: AppFont.fontFamily,
              color: AppColor.blackColor,
            ),
          ),
          SizedBox(height: size.height * 0.018),

          const Text(
            "We're sorry, but your ride cannot be cancelled at this time. "
            "A driver has already accepted your booking and is on the way "
            "to pick you up. Cancelling now may inconvenience the driver "
            "who has already started travelling towards you.\n\n"
            "We truly appreciate your understanding and patience.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              fontFamily: AppFont.fontFamily,
              color: AppColor.secondTextColor,
              height: 1.6,
            ),
          ),
          SizedBox(height: size.height * 0.04),

          const Divider(color: AppColor.borderColor),
          SizedBox(height: size.height * 0.03),

          const Text(
            "Need further assistance?",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFamily: AppFont.fontFamily,
              color: AppColor.blackColor,
            ),
          ),
          SizedBox(height: size.height * 0.008),
          const Text(
            "Our support team is available to help you with any concerns "
            "regarding your booking.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              fontFamily: AppFont.fontFamily,
              color: AppColor.hintTextColor,
            ),
          ),
          SizedBox(height: size.height * 0.025),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => bookingHelpAndSupport(
                      bookingId: widget.bookingId,
                      bookingCode: widget.bookingCode ?? "",
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.headset_mic_rounded,
                  color: Colors.white, size: 20),
              label: const Text(
                "Contact Help & Support",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppFont.fontFamily,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColor.themeColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          SizedBox(height: size.height * 0.015),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColor.borderColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                "Go Back",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppFont.fontFamily,
                  color: AppColor.thirdTextColor,
                ),
              ),
            ),
          ),

          SizedBox(height: size.height * 0.04),
        ],
      ),
    );
  }
}
