import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:provider/provider.dart';

import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_constant.dart';

class CancellationPolicyScreen extends StatefulWidget {
  final String? bookingCode;
  final String? bookingId;
  final bool confirmbook;
  final bool openReasonSheet;
  // Feature 10: when bookingStatus is Accepted or beyond, hide the cancel button
  final String? bookingStatus;

  const CancellationPolicyScreen({
    super.key,
    this.openReasonSheet = false,
    this.confirmbook = false,
    this.bookingCode,
    this.bookingId,
    this.bookingStatus,
  });

  @override
  State<CancellationPolicyScreen> createState() =>
      _CancellationPolicyScreenState();
}

class _CancellationPolicyScreenState extends State<CancellationPolicyScreen> {
  @override
  void initState() {
    super.initState();
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
                      AppLanguage.cancelText[language],
                      style: const TextStyle(
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
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              fontFamily: AppFont.fontFamily,
                              color: Color(0xffFF3819),
                            ),
                          ),
                          TextSpan(
                            text: AppLanguage.instantText[language],
                            style: const TextStyle(
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
                    // Feature 10: hide cancel button once driver is assigned
                    Builder(builder: (_) {
                      final noCancel = ['Accepted', 'Arrived', 'Pickup', 'Ongoing', 'Delivered']
                          .contains(widget.bookingStatus ?? '');
                      if (noCancel) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: const Center(
                            child: Text(
                              'Cancellation not allowed after driver is assigned',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                          ),
                        );
                      }
                      return AppButton(
                        text: AppLanguage.cancelBookingText[language],
                        onPress: () {
                          if (widget.openReasonSheet) {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => CancelReasonBottomSheet1(
                                bookingId: widget.bookingId,
                              ),
                            );
                          } else {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => CancelReasonBottomSheet(
                                bookingCode: widget.bookingCode,
                                bookingId: widget.bookingId,
                              ),
                            );
                          }
                        },
                      );
                    }),
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
          "• ",
          style: TextStyle(
            fontSize: 18,
            height: 1.4,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
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
  final String? bookingCode;
  final String? bookingId;
  final bool confirmbook;
  const CancelReasonBottomSheet({
    super.key,
    this.confirmbook = false,
    this.bookingCode,
    this.bookingId,
  });

  @override
  State<CancelReasonBottomSheet> createState() =>
      _CancelReasonBottomSheetState();
}

class _CancelReasonBottomSheetState extends State<CancelReasonBottomSheet> {
  String? selectedReason;
  final TextEditingController issueController = TextEditingController();

  void overlayValidation(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        top: MediaQuery.of(context).padding.top + 50,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColor.themeColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontFamily: AppFont.fontFamily,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    Future.delayed(const Duration(seconds: 2), () {
      overlayEntry.remove();
    });
  }

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
            Center(
              child: Text(
                AppLanguage.cancelResonText[language],
                style: const TextStyle(
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
                          activeColor: AppColor.themeColor,
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
                          style: const TextStyle(
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
            Text(
              AppLanguage.describeText[language],
              style: const TextStyle(
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
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: AppFont.fontFamily,
                  color: AppColor.blackColor,
                ),
                decoration: InputDecoration(
                  hintText: AppLanguage.writeMoreText[language],
                  hintStyle: const TextStyle(
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
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: AppColor.themeColor,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      AppLanguage.noText[language],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        fontFamily: AppFont.fontFamily,
                        color: AppColor.themeColor,
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
                                if (selectedReason == null ||
                                    selectedReason!.isEmpty) {
                                  overlayValidation(
                                    context,
                                    AppLanguage.reasonMessage[language],
                                  );
                                  return;
                                }
                                if (selectedReason ==
                                        AppLanguage.otherReasonText[language] &&
                                    issueController.text.trim().isEmpty) {
                                  overlayValidation(
                                    context,
                                    AppLanguage.reasonMessage[language],
                                  );
                                  return;
                                }
                                if (widget.bookingId == null ||
                                    widget.bookingId!.isEmpty) {
                                  overlayValidation(
                                    context,
                                    "Booking id not found",
                                  );
                                  return;
                                }

                                FocusScope.of(context).unfocus();

                                final success = await postApi.cancelBookingApi(
                                  context,
                                  bookingId: widget.bookingId!,
                                  cancellationReason: _finalReason(),
                                );

                                // if (success && mounted) {
                                //   Navigator.pop(context);
                                //   Navigator.push(
                                //     context,
                                //     MaterialPageRoute(
                                //       builder: (context) =>
                                //           const CustomBottomNav(
                                //         userType: UserType.individual,
                                //         initialIndex: 1,
                                //         bookingTabIndex: 3,
                                //       ),
                                //     ),
                                //   );
                                // }
                                if (success && mounted) {
                                  Get.offAll(() => const CustomBottomNav(
                                        userType: UserType.retailer,
                                        initialIndex: 1,
                                        bookingTabIndex: 4, // 👈 Cancel tab
                                      ));
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColor.themeColor,
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
                                style: const TextStyle(
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

class CancelReasonBottomSheet1 extends StatefulWidget {
  final String? bookingId;
  const CancelReasonBottomSheet1({
    super.key,
    this.bookingId,
  });

  @override
  State<CancelReasonBottomSheet1> createState() =>
      _CancelReasonBottomSheet1State();
}

class _CancelReasonBottomSheet1State extends State<CancelReasonBottomSheet1> {
  String? selectedReason;
  final TextEditingController issueController = TextEditingController();

  void overlayValidation(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        top: MediaQuery.of(context).padding.top + 50,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColor.themeColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontFamily: AppFont.fontFamily,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    Future.delayed(const Duration(seconds: 2), () {
      overlayEntry.remove();
    });
  }

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
            Center(
              child: Text(
                AppLanguage.cancelResonText[language],
                style: const TextStyle(
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
                          style: const TextStyle(
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
            Text(
              AppLanguage.describeText[language],
              style: const TextStyle(
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
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: AppFont.fontFamily,
                  color: AppColor.blackColor,
                ),
                decoration: InputDecoration(
                  hintText: AppLanguage.writeMoreText[language],
                  hintStyle: const TextStyle(
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
                      side: const BorderSide(
                        color: AppColor.primaryColor,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      AppLanguage.noText[language],
                      style: const TextStyle(
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
                                if (selectedReason == null ||
                                    selectedReason!.isEmpty) {
                                  overlayValidation(
                                    context,
                                    AppLanguage.reasonMessage[language],
                                  );
                                  return;
                                }
                                if (selectedReason ==
                                        AppLanguage.otherReasonText[language] &&
                                    issueController.text.trim().isEmpty) {
                                  overlayValidation(
                                    context,
                                    AppLanguage.reasonMessage[language],
                                  );
                                  return;
                                }
                                if (widget.bookingId == null ||
                                    widget.bookingId!.isEmpty) {
                                  overlayValidation(
                                    context,
                                    "Booking id not found",
                                  );
                                  return;
                                }

                                FocusScope.of(context).unfocus();

                                final success = await postApi.cancelBookingApi(
                                  context,
                                  bookingId: widget.bookingId!,
                                  cancellationReason: _finalReason(),
                                );

                                // if (success && mounted) {
                                //   Navigator.pop(context);
                                //   Navigator.push(
                                //     context,
                                //     MaterialPageRoute(
                                //       builder: (context) =>
                                //           const CustomBottomNav(
                                //         userType: UserType.individual,
                                //         initialIndex: 1,
                                //         bookingTabIndex: 3,
                                //       ),
                                //     ),
                                //   );
                                // }

                                if (success && mounted) {
                                  Get.offAll(() => const CustomBottomNav(
                                        userType: UserType.retailer,
                                        initialIndex: 1,
                                        bookingTabIndex: 4, // 👈 Cancel tab
                                      ));
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
                                style: const TextStyle(
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
