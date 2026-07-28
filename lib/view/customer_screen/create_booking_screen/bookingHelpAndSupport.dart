import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';

import 'package:movigo/utilities/app_header.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/utilities/common_text_field.dart';

class bookingHelpAndSupport extends StatefulWidget {
    final String bookingId;  
  final String bookingCode;

  const bookingHelpAndSupport({
    super.key,
    required this.bookingCode, required this.bookingId,
  });

  @override
  State<bookingHelpAndSupport> createState() => _bookingHelpAndSupportState();
}

class _bookingHelpAndSupportState extends State<bookingHelpAndSupport> {
  /// CONTROLLERS
  final TextEditingController bookingIDController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    bookingIDController.text = "#${widget.bookingCode}";

    log("booking id/code = #${widget.bookingCode}");
  }

  bool helpSupportValidation(String fullName, String description) {
    if (fullName.isEmpty) {
      SnackBarToastMessage.showSnackBar(
          context, AppLanguage.fullNameMessage[language]);
      return false;
    }
    if (description.isEmpty) {
      SnackBarToastMessage.showSnackBar(
          context, AppLanguage.descriptionMessage[language]);
      return false;
    }

    // final apiprovider = Provider.of<PostApiProvider>(context, listen: false);
    // apiprovider.contactUsApiCalling(
    //   context,
    //   bookingIDController.text.trim(),
    //   emailController.text.trim(),
    //   descriptionController.text.trim(),
    // );

    return true;
  }

  @override
  void dispose() {
    bookingIDController.dispose();

    super.dispose();
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

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: size.width * 0.04),
              child: CommonAppBar(
                title: AppLanguage.helpSupoortText[language],
                onBack: () => Navigator.of(context).maybePop(),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(height: size.height * 0.02),
                      CommonTextField(
                        controller: bookingIDController,
                        hintText: "",
                        readOnly: true,
                      ),
                      _gap(size),
                      _label(AppLanguage.descriptionText[language], size),
                      CommonTextField(
                        controller: descriptionController,
                        hintText: AppLanguage.writeText[language],
                        isMultiline: true,
                        height: 0.15,
                      ),
                      SizedBox(height: size.height * 0.06),
                      Center(
                        child: Consumer<PostApiProvider>(
                          builder: (context, apiprovider, child) {
                            return apiprovider.loading
                                ? const CircularProgressIndicator(
                                    color: AppColor.themeColor)
                                : AppButton(
                                    text: AppLanguage.submitText[language],
                                    onPress: () async {
                                      FocusScope.of(context).unfocus();

                                      final desc =
                                          descriptionController.text.trim();

                                      if (desc.isEmpty) {
                                        SnackBarToastMessage.showSnackBar(
                                          context,
                                          AppLanguage
                                              .descriptionMessage[language],
                                        );
                                        return;
                                      }

                                      final apiProvider =
                                          Provider.of<PostApiProvider>(context,
                                              listen: false);

                                      final success = await apiProvider
                                          .bookingHelpSupportApiCalling(
                                        context,
                                        description: desc,
                                        bookingId: widget.bookingId,
                                        bookingCode: widget.bookingCode,
                                      );

                                      if (success && mounted) {
                                        Navigator.pop(context);
                                      }
                                    },
                                  );
                          },
                        ),
                      ),
                      SizedBox(height: size.height * 0.04),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gap(Size size) => SizedBox(height: size.height * 0.025);

  Widget _label(String text, Size size) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: size.height * 0.008),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            fontFamily: AppFont.fontFamily,
            color: AppColor.nineTextColor,
          ),
        ),
      ),
    );
  }
//
}
