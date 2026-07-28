import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_constant.dart';

class RCancellationPolicyScreen extends StatefulWidget {
  final String? bookingId;

  const RCancellationPolicyScreen({super.key, this.bookingId});

  @override
  State<RCancellationPolicyScreen> createState() =>
      _RCancellationPolicyScreenState();
}

class _RCancellationPolicyScreenState extends State<RCancellationPolicyScreen> {
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
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(height: size.height * 0.04),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.06),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => Get.back(),
                      child: Image.asset(
                        AppImage.backimage,
                        height: 40,
                        width: 40,
                      ),
                    ),
                    SizedBox(width: size.width * 0.04),
                    Text(
                      AppLanguage.cancellationPolicyText[language],
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppFont.fontFamily,
                        color: AppColor.blackColor,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: size.height * 0.015),
              Container(
                width: size.width,
                padding: EdgeInsets.symmetric(
                  horizontal: size.width * 0.08,
                  vertical: size.height * 0.04,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(28),
                    topRight: Radius.circular(28),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _policyPoint(
                      text: AppLanguage.beforeText[language],
                    ),

                    SizedBox(height: size.height * 0.02),

                    _policyPoint(
                      text: AppLanguage.afterText[language],
                    ),

                    SizedBox(height: size.height * 0.02),

                    _policyPoint(
                      text: AppLanguage.afterPickupText[language],
                    ),

                    SizedBox(height: size.height * 0.03),

                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: AppLanguage.notecText[language],
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              fontFamily: AppFont.fontFamily,
                              color: Color(0xffFF3819),
                            ),
                          ),
                          TextSpan(
                            text: AppLanguage.instantText[language],
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              fontFamily: AppFont.fontFamily,
                              color: AppColor.fiveCover,
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: size.height * 0.08),

                    /// CANCEL BOOKING BUTTON
                    AppButton(
                      text: AppLanguage.cancelBookingText[language],
                      onPress: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => CancelReasonBottomSheet(
                            bookingId: widget.bookingId,
                          ),
                        );
                      },
                    ),

                    SizedBox(height: size.height * 0.08),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// BULLET POINT WIDGET
  Widget _policyPoint({required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "â€¢ ",
          style: TextStyle(
            fontSize: 18,
            height: 1.4,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              fontFamily: AppFont.fontFamily,
              color: AppColor.fiveCover,
              // height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class CancelReasonBottomSheet extends StatefulWidget {
  final String? bookingId;

  const CancelReasonBottomSheet({super.key, this.bookingId});

  @override
  State<CancelReasonBottomSheet> createState() =>
      _CancelReasonBottomSheetState();
}

class _CancelReasonBottomSheetState extends State<CancelReasonBottomSheet> {
  String? selectedReason;
  final TextEditingController issueController = TextEditingController();

  final List<String> reasons = [
    AppLanguage.bookedText[language],
    AppLanguage.wrongText[language],
    AppLanguage.itemText[language],
    AppLanguage.driverTakingText[language],
    AppLanguage.changeOfText[language],
    AppLanguage.otherReasonText[language],
  ];

  String _finalReason() {
    final desc = issueController.text.trim();
    if (selectedReason != null && desc.isNotEmpty) {
      return "${selectedReason!} - $desc";
    }
    return (selectedReason ?? desc).trim();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Container(
      padding: EdgeInsets.only(
        left: size.width * 0.06,
        right: size.width * 0.06,
        top: size.height * 0.03,
        bottom: MediaQuery.of(context).viewInsets.bottom + size.height * 0.03,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// TITLE
            Center(
              child: Text(
                AppLanguage.cancelResonText[language],
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppFont.fontFamily,
                  color: AppColor.thirdTextColor,
                ),
              ),
            ),

            SizedBox(height: size.height * 0.03),

            ...reasons.map(
              (reason) => Padding(
                padding: EdgeInsets.only(bottom: size.height * 0.018),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      selectedReason = reason;
                    });
                  },
                  child: Row(
                    children: [
                      SizedBox(
                        height: 18,
                        width: 18,
                        child: Radio<String>(
                          value: reason,
                          groupValue: selectedReason,
                          activeColor: AppColor.primaryColor,
                          onChanged: (value) {
                            setState(() {
                              selectedReason = value;
                            });
                          },
                        ),
                      ),
                      SizedBox(width: size.width * 0.03),
                      Expanded(
                        child: Text(
                          reason,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            fontFamily: AppFont.fontFamily,
                            color: AppColor.fiveCover,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SizedBox(height: size.height * 0.02),

            /// DESCRIBE ISSUE
            Text(
              AppLanguage.describeText[language],
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: AppFont.fontFamily,
                color: AppColor.blackColor,
              ),
            ),

            SizedBox(height: size.height * 0.012),

            Container(
              height: size.height * 0.12,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.grey.shade300,
                ),
              ),
              child: TextField(
                controller: issueController,
                maxLines: null,
                expands: true,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: AppFont.fontFamily,
                  color: AppColor.blackColor,
                ),
                decoration: InputDecoration(
                  hintText: AppLanguage.writeMoreText[language],
                  hintStyle: TextStyle(
                    fontSize: 14,
                    fontFamily: AppFont.fontFamily,
                    fontWeight: FontWeight.w500,
                    color: Color(0xff747474),
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),

            SizedBox(height: size.height * 0.04),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppColor.primaryColor,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      AppLanguage.noText[language],
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        fontFamily: AppFont.fontFamily,
                        color: AppColor.primaryColor,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: size.width * 0.04),
                Expanded(
                  child: Consumer<PostApiProvider>(
                    builder: (context, postApi, _) {
                      return ElevatedButton(
                        onPressed: postApi.loading
                            ? null
                            : () async {
                                if (widget.bookingId == null ||
                                    widget.bookingId!.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Booking id not found"),
                                    ),
                                  );
                                  return;
                                }

                                FocusScope.of(context).unfocus();

                                final success = await postApi.cancelBookingApi(
                                  context,
                                  bookingId: widget.bookingId!,
                                  cancellationReason: _finalReason(),
                                );

                                if (success && mounted) {
                                  // Close the reason sheet, then pop the
                                  // cancellation policy screen so the
                                  // retailer lands back on the booking
                                  // list/detail screen, which reflects the
                                  // now-cancelled booking on refresh.
                                  Navigator.pop(context);
                                  Get.back();
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColor.primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: postApi.loading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                AppLanguage.yescText[language],
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: AppFont.fontFamily,
                                  color: Colors.white,
                                ),
                              ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
