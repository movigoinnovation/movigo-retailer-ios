import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_image.dart';

class LocationPermissionScreen extends StatefulWidget {
  final UserType userType;
  const LocationPermissionScreen({super.key, required this.userType});

  @override
  State<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  bool _isRequesting = false;

  Future<void> _requestPermission() async {
    setState(() => _isRequesting = true);
    try {
      await Geolocator.requestPermission();
    } catch (_) {}
    if (mounted) setState(() => _isRequesting = false);
    _goHome();
  }

  void _goHome() {
    Get.offAll(() => CustomBottomNav(
          userType: widget.userType,
          initialIndex: 0,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.07),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: size.height * 0.07),
              Image.asset(
                AppImage.applogo3,
                height: size.width * 0.28,
                width: size.width * 0.6,
                fit: BoxFit.contain,
              ),
              SizedBox(height: size.height * 0.06),
              Container(
                height: size.width * 0.38,
                width: size.width * 0.38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColor.themeColor.withOpacity(0.08),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  size: 80,
                  color: AppColor.themeColor,
                ),
              ),
              SizedBox(height: size.height * 0.04),
              const Text(
                "Enable Location Access",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  fontFamily: AppFont.fontFamily,
                  color: AppColor.blackColor,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: size.height * 0.014),
              Text(
                "Movigo needs your location to find nearby drivers and show accurate pickup points.",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  fontFamily: AppFont.fontFamily,
                  color: AppColor.hintTextColor,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isRequesting ? null : _requestPermission,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColor.themeColor,
                    disabledBackgroundColor:
                        AppColor.themeColor.withOpacity(0.5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isRequesting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          "Allow Location Access",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: AppFont.fontFamily,
                          ),
                        ),
                ),
              ),
              SizedBox(height: size.height * 0.018),
              GestureDetector(
                onTap: _goHome,
                child: const Text(
                  "Skip for now",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: AppFont.fontFamily,
                    color: AppColor.hintTextColor,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColor.hintTextColor,
                  ),
                ),
              ),
              SizedBox(height: size.height * 0.05),
            ],
          ),
        ),
      ),
    );
  }
}
