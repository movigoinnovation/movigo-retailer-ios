import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';

/// Prompts the retailer once (non-naggy, dismissible) to disable battery
/// optimization so booking-status pushes and background tracking work reliably.
///
/// The prompt is shown at most once per install (stored in SharedPreferences).
/// The user can dismiss it; it will never show again unless the key is cleared.
class BatteryOptimizationHelper {
  static const _prefKey = 'retailer_battery_opt_prompted_v1';

  /// Call from the home screen's initState / postFrameCallback.
  /// No-op on iOS or if already prompted.
  static Future<void> maybePrompt(BuildContext context) async {
    if (!Platform.isAndroid) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefKey) == true) return; // already shown

    // Check if battery optimization is already ignored — skip dialog if fine.
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted) {
      await prefs.setBool(_prefKey, true);
      return;
    }

    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const _BatteryOptDialog(),
    );

    // Mark as shown regardless of how the user dismissed it.
    await prefs.setBool(_prefKey, true);
  }
}

class _BatteryOptDialog extends StatelessWidget {
  const _BatteryOptDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.battery_alert_rounded,
              color: Colors.orange, size: 26),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Keep app active in background',
            style: TextStyle(
                fontFamily: AppFont.fontFamily,
                fontWeight: FontWeight.w700,
                fontSize: 15),
          ),
        ),
      ]),
      content: const Text(
        'Your phone\'s battery settings may pause this app when you receive a '
        'call or switch apps, causing booking updates to be missed.\n\n'
        'Tap "Fix Now" to allow the app to run in the background — this keeps '
        'driver tracking and booking status updates working reliably.\n\n'
        'बैटरी ऑप्टिमाइज़ेशन बंद करें ताकि बुकिंग अपडेट न छूटें।',
        style: TextStyle(
            fontFamily: AppFont.fontFamily, fontSize: 13, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Not Now',
              style: TextStyle(
                  fontFamily: AppFont.fontFamily, color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(context);
            // Direct system request — opens the "Allow background activity"
            // dialog for this app specifically.
            await Permission.ignoreBatteryOptimizations.request();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColor.themeColor,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Fix Now',
              style: TextStyle(
                  fontFamily: AppFont.fontFamily,
                  color: Colors.white,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
