// ignore_for_file: use_build_context_synchronously
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';

// Dismissible "a new version is available" popup — shown when the backend's
// app_version_check reports update_available (installed build is behind the
// latest published build, but still >= min_version_code so it isn't a hard
// block). Unlike ForceUpdateScreen this can be ignored; ignoring a version
// is remembered so the retailer isn't nagged again until an even newer
// build is published.
class SoftUpdatePopup extends StatelessWidget {
  final String latestVersion;
  final int latestVersionCode;
  final String playStoreUrl;

  const SoftUpdatePopup({
    super.key,
    required this.latestVersion,
    required this.latestVersionCode,
    required this.playStoreUrl,
  });

  static const _prefsKey = 'retailer_ignored_update_version_code';
  static const _packageId = 'com.app.movigocustomer';

  /// Shows the popup unless the retailer already dismissed this exact
  /// version (or a newer one). Call after a successful, non-force version check.
  static Future<void> showIfNeeded(
    BuildContext context, {
    required String latestVersion,
    required int latestVersionCode,
    required String playStoreUrl,
  }) async {
    if (latestVersionCode <= 1) return;
    final prefs = await SharedPreferences.getInstance();
    final ignoredCode = prefs.getInt(_prefsKey) ?? 0;
    if (ignoredCode >= latestVersionCode) return;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SoftUpdatePopup(
        latestVersion: latestVersion,
        latestVersionCode: latestVersionCode,
        playStoreUrl: playStoreUrl,
      ),
    );
  }

  Future<void> _openStore(BuildContext context) async {
    final market = Uri.parse('market://details?id=$_packageId');
    final browser = Uri.parse(playStoreUrl.isNotEmpty
        ? playStoreUrl
        : 'https://play.google.com/store/apps/details?id=$_packageId');
    try {
      if (Platform.isAndroid && await canLaunchUrl(market)) {
        await launchUrl(market, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(browser, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(browser, mode: LaunchMode.externalApplication);
    }
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _ignore(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, latestVersionCode);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: EdgeInsets.all(size.width * 0.06),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColor.themeColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.system_update_alt_rounded,
                color: AppColor.themeColor,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Update Available",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: AppFont.fontFamily,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              latestVersion.isNotEmpty
                  ? "Version $latestVersion is available. Update now for the latest features and fixes."
                  : "A new version is available. Update now for the latest features and fixes.",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontFamily: AppFont.fontFamily,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _openStore(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColor.themeColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "Update Now",
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: AppFont.fontFamily,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _ignore(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  "Later",
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontFamily: AppFont.fontFamily,
                    fontWeight: FontWeight.w600,
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
