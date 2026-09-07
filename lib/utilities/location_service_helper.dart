import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

import 'app_color.dart';
import 'app_font.dart';

/// Shared "please turn on GPS" prompt — used once at app startup and again
/// when the user tries to search for a pickup/drop location with location
/// services off. Uses Get's global overlay context so it can be shown from
/// background/startup code without depending on a specific screen's
/// BuildContext staying mounted.
class LocationServiceHelper {
  static Future<bool> ensureEnabled({String? message}) async {
    if (await Geolocator.isLocationServiceEnabled()) return true;

    final bool goToSettings = await Get.dialog<bool>(
          AlertDialog(
            title: const Text(
              'Turn On Location',
              style: TextStyle(
                fontFamily: AppFont.fontFamily,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Text(
              message ??
                  'Location services are off. Turn on GPS so we can detect '
                      'your pickup point automatically.',
              style: const TextStyle(fontFamily: AppFont.fontFamily),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(result: false),
                child: const Text(
                  'Not Now',
                  style: TextStyle(fontFamily: AppFont.fontFamily),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColor.themeColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Get.back(result: true),
                child: const Text(
                  'Turn On',
                  style: TextStyle(fontFamily: AppFont.fontFamily),
                ),
              ),
            ],
          ),
          barrierDismissible: true,
        ) ??
        false;

    if (!goToSettings) return false;

    await Geolocator.openLocationSettings();
    // Best-effort recheck — the user may still be on the settings screen
    // when this resolves, so a false result here doesn't necessarily mean
    // they refused, just that we can't confirm it turned on yet.
    await Future.delayed(const Duration(milliseconds: 500));
    return Geolocator.isLocationServiceEnabled();
  }
}
