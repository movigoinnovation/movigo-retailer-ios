import 'dart:io';

import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_config_provider.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_header.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/utilities/common_text_field.dart';

class ProfileScreen extends StatefulWidget {
  final String? mobile;
  ProfileScreen({super.key, this.mobile});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// CONTROLLERS (CLEAN NAMING)
  final TextEditingController fullNameController =
      TextEditingController(text: AppLanguage.jacobJonesText[language]);
  final TextEditingController emailController =
      TextEditingController(text: AppLanguage.jacobMailText[language]);
  final TextEditingController mobileController =
      TextEditingController(text: AppLanguage.jacobMobText[language]);

  @override
  void initState() {
    super.initState();

    final user = Provider.of<UserController>(context, listen: false);

    fullNameController.text = user.getUserName;
    emailController.text = user.getUserEmail;

    /// +91
    if (widget.mobile != null && widget.mobile!.isNotEmpty) {
      mobileController.text = "+91 ${widget.mobile}";
    }
  }

  File? _profileImage;
  var fileName;

  Future<bool> editValidationCustomer(
    String name,
    String email,
    String mobile,
  ) async {
    final user = Provider.of<UserController>(context, listen: false);

    if (_profileImage == null && user.getUserImage.isEmpty) {
      SnackBarToastMessage.showSnackBar(
        context,
        AppLanguage.imageMessage[language],
      );
      return false;
    }

    if (name.isEmpty) {
      SnackBarToastMessage.showSnackBar(
        context,
        AppLanguage.fullNameMessage[language],
      );
      return false;
    }

    if (email.isEmpty) {
      SnackBarToastMessage.showSnackBar(
        context,
        AppLanguage.emailMessage[language],
      );
      return false;
    }

    if (!AppConstant.emailValidatorRegExp.hasMatch(email)) {
      SnackBarToastMessage.showSnackBar(
        context,
        AppLanguage.emailValidMessage[language],
      );
      return false;
    }

    String cleanedMobile = mobile.replaceAll("+91", "").trim();
    if (cleanedMobile.isEmpty || cleanedMobile.length != 10) {
      SnackBarToastMessage.showSnackBar(
        context,
        AppLanguage.mobilevalidMessage[language],
      );
      return false;
    }

    // API
    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final success = await provider.updateCustomerProfileApi(
      context,
      fullName: name,
      email: email,
      phoneNumber: cleanedMobile,
      profileImage: _profileImage != null ? XFile(_profileImage!.path) : null,
    );

    if (success) {
      // Refresh user data before popping
      await user.getUserDetails();

      if (mounted) {
        Navigator.pop(context);
      }
    }

    return success;
  }

  Future<void> _imgFromGallery() async {
    final XFile? image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxHeight: 450,
      maxWidth: 450,
      imageQuality: 50,
    );

    if (image != null) {
      setState(() {
        _profileImage = File(image.path);
        fileName = image.path.split('/').last;
      });
    }
  }

  Future<File?> cropImage(File image) async {
    final cropImage = ImageCropper();
    final croppedFile = await cropImage.cropImage(sourcePath: image.path);
    return croppedFile != null ? File(croppedFile.path) : null;
  }

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    mobileController.dispose();

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
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Container(
            width: size.width,
            height: size.height,
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CommonAppBar(
                  title: AppLanguage.manageProfileText[language],
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                    SizedBox(height: size.height * 0.02),
                    Column(
                      children: [
                        GestureDetector(
                          onTap: () => imagePicker(),
                          child: DottedBorder(
                            borderType: BorderType.Circle,
                            dashPattern: const [4, 4],
                            color: AppColor.hintTextColor.withOpacity(0.5),
                            child: Container(
                              width: 96,
                              height: 96,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xffF2F2F2),
                              ),
                              child: ClipOval(
                                child: _profileImage != null
                                    ? Image.file(
                                        _profileImage!,
                                        fit: BoxFit.cover,
                                        width: 96,
                                        height: 96,
                                        cacheWidth: 200,
                                      )
                                    : Consumer<UserController>(
                                        builder: (context, user, _) {
                                          final String image =
                                              user.getUserImage;
                                          return image.isNotEmpty
                                              ? Image.network(
                                                  "${AppConfigProvider.imgUrl}$image",
                                                  fit: BoxFit.cover,
                                                  cacheWidth: 200,
                                                  errorBuilder: (_, __, ___) =>
                                                      Image.asset(
                                                          AppImage.userdummyimage),
                                                )
                                              : Image.asset(
                                                  AppImage.userdummyimage);
                                        },
                                      ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: size.height * 0.01),
                        GestureDetector(
                          onTap: () => imagePicker(),
                          child: Text(
                            AppLanguage.uploatText[language],
                            style: const TextStyle(
                              fontFamily: AppFont.fontFamily,
                              fontSize: 12,
                              color: AppColor.uploadColor,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColor.uploadColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: size.height * 0.06),
                    CommonTextField(
                      controller: fullNameController,
                      hintText: AppLanguage.enterFullNText[language],
                    ),
                    _gap(size),
                    CommonTextField(
                      controller: emailController,
                      hintText: AppLanguage.enterEmailText[language],
                      keyboardType: TextInputType.emailAddress,
                    ),
                    _gap(size),
                    CommonTextField(
                      controller: mobileController,
                      hintText: AppLanguage.enterMobilenumtext[language],
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      readOnly: true,
                    ),
                    SizedBox(height: size.height * 0.08),
                    Consumer<PostApiProvider>(
                      builder: (context, provider, _) {
                        return provider.loading
                            ? const CircularProgressIndicator()
                            : AppButton(
                                text: AppLanguage.updateText[language],
                                onPress: () {
                                  editValidationCustomer(
                                    fullNameController.text.trim(),
                                    emailController.text.trim(),
                                    mobileController.text
                                        .replaceAll("+91", "")
                                        .trim(),
                                  );
                                },
                              );
                      },
                    ),
                    SizedBox(height: size.height * 0.04),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _gap(Size size) => SizedBox(height: size.height * 0.02);

//
  void imagePicker() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Container(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    _imgFromGallery();
                    setState(() {});
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    color: AppColor.transparentColor,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: MediaQuery.of(context).size.width * 4 / 100,
                        horizontal: MediaQuery.of(context).size.width * 2 / 100,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: MediaQuery.of(context).size.width * 5 / 100,
                          ),
                          Container(
                            child: SizedBox(
                              width:
                                  MediaQuery.of(context).size.width * 8 / 100,
                              height:
                                  MediaQuery.of(context).size.width * 8 / 100,
                              child: Image.asset(
                                AppImage.galleryImgIcon,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: MediaQuery.of(context).size.width * 3 / 100,
                          ),
                          Text(
                            AppLanguage.galleryText[language],
                            style: const TextStyle(
                              fontFamily: AppFont.fontFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColor.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Camera capture is disabled for now (shipped as "adding
                // soon") — the in-app camera flow was unresponsive and got
                // the app rejected under App Store Guideline 2.1(a).
                // Gallery upload above still works.
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    color: AppColor.transparentColor,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: MediaQuery.of(context).size.width * 4 / 100,
                        horizontal: MediaQuery.of(context).size.width * 2 / 100,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: MediaQuery.of(context).size.width * 5 / 100,
                          ),
                          Opacity(
                            opacity: 0.4,
                            child: SizedBox(
                              width:
                                  MediaQuery.of(context).size.width * 8 / 100,
                              height:
                                  MediaQuery.of(context).size.width * 8 / 100,
                              child: Image.asset(
                                AppImage.cameraImgIcon,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: MediaQuery.of(context).size.width * 3 / 100,
                          ),
                          Text(
                            AppLanguage.cameraText[language],
                            style: TextStyle(
                              fontFamily: AppFont.fontFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Adding soon',
                            style: TextStyle(
                              fontFamily: AppFont.fontFamily,
                              fontSize: 12,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

//
}
