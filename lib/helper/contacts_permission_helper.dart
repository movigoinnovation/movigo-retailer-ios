import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';

class ContactsPermissionHelper {
  /// Prominent disclosure and permission requester for contacts access.
  /// Shows dialog explaining contact access, then calls requestPermission.
  /// Returns true if permission is granted.
  static Future<bool> ensureContactsPermission(BuildContext context) async {
    // 1. Check if permission is already granted
    final status = await Permission.contacts.status;
    if (status.isGranted) {
      return true;
    }

    // 2. Show prominent disclosure before system dialog
    if (context.mounted) {
      final proceed = await _showProminentDisclosure(context);
      if (!proceed) return false;
    }

    // 3. Request permission
    final granted = await FlutterContacts.requestPermission(readonly: true);
    return granted;
  }

  static Future<bool> _showProminentDisclosure(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColor.themeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.import_contacts_rounded,
                color: AppColor.themeColor,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Contacts Access',
                style: TextStyle(
                  fontFamily: AppFont.fontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Movigo accesses your contacts so you can quickly select a receiver's name and phone number when placing a delivery booking. Only the selected contact's name and number are used — your full contacts list is never stored or shared.",
                style: TextStyle(
                  fontFamily: AppFont.fontFamily,
                  fontSize: 13,
                  height: 1.5,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Deny',
              style: TextStyle(
                fontFamily: AppFont.fontFamily,
                color: Colors.grey,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColor.themeColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Allow',
              style: TextStyle(
                fontFamily: AppFont.fontFamily,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
