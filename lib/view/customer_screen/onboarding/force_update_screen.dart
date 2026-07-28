// ignore_for_file: use_build_context_synchronously
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_image.dart';

class ForceUpdateScreen extends StatelessWidget {
  final String latestVersion;
  final String playStoreUrl;
  const ForceUpdateScreen({
    super.key, required this.latestVersion, required this.playStoreUrl});

  Future<void> _openStore(BuildContext context) async {
    const id = 'com.app.movigocustomer';
    final market = Uri.parse('market://details?id=$id');
    final browser = Uri.parse(playStoreUrl.isNotEmpty
        ? playStoreUrl
        : 'https://play.google.com/store/apps/details?id=$id');
    try {
      if (Platform.isAndroid && await canLaunchUrl(market)) {
        await launchUrl(market, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(browser, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(browser, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.08),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                Image.asset(AppImage.applogo3, width: w * 0.38,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.store_rounded, size: 80, color: AppColor.themeColor)),
                SizedBox(height: h * 0.04),
                Container(width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: AppColor.themeColor.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.system_update_alt_rounded,
                    size: 38, color: AppColor.themeColor)),
                SizedBox(height: h * 0.03),
                const Text('Update Required', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700,
                    fontFamily: AppFont.fontFamily, color: Color(0xFF121212))),
                SizedBox(height: h * 0.015),
                Text(
                  latestVersion.isNotEmpty
                      ? 'Version $latestVersion is now available.\nPlease update to continue using Movigo.'
                      : 'A new version is available.\nPlease update to continue using Movigo.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontFamily: AppFont.fontFamily,
                    color: Color(0xFF686868), height: 1.55)),
                SizedBox(height: h * 0.045),
                SizedBox(width: double.infinity, height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () => _openStore(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColor.themeColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0),
                    icon: const Icon(Icons.download_rounded, size: 22),
                    label: const Text('Update Now',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                        fontFamily: AppFont.fontFamily)))),
                SizedBox(height: h * 0.02),
                Text('Updates keep the app fast, safe & bug-free.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontFamily: AppFont.fontFamily,
                    color: Colors.grey.shade400)),
                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
