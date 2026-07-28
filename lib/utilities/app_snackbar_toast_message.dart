import 'package:flutter/material.dart';

import 'package:movigo/utilities/app_color.dart';

class SnackBarToastMessage {
  SnackBarToastMessage._();

  static void showSnackBar(BuildContext context, String message) {
    if (message.trim().isEmpty) return;
    // Use overlay approach — floating SnackBar with large bottom margin
    // crashes layout when keyboard is open ("Floating SnackBar presented off screen")
    createnewplaylistfuncation(context, message);
  }

  static createnewplaylistfuncation(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColor.themeColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 3), () {
      overlayEntry.remove();
    });
  }
}
