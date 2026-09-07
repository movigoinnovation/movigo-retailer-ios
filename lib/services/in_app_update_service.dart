import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

/// Wraps Google Play's In-App Update API (Android only — no-op on iOS).
///
/// The immediate-vs-flexible decision is driven entirely by our own
/// backend's `app_version_check` response (`force_update`), not by Play
/// Console's staged-rollout priority — the Play priority signal is never
/// consulted here. Callers pass `forceUpdate: data['force_update']` from
/// that endpoint.
class InAppUpdateService {
  InAppUpdateService._();
  static final InAppUpdateService instance = InAppUpdateService._();

  bool _flexibleUpdateStarted = false;

  /// Call once per cold start after app_version_check resolves.
  /// Returns true if a blocking immediate update was successfully launched
  /// (the caller can then skip its own hard-block fallback screen).
  /// Fails silently on any error (not installed via Play Store, no network,
  /// Play services unavailable, etc.) — never throws, never blocks the app.
  Future<bool> check(
    BuildContext? context, {
    required bool forceUpdate,
  }) async {
    if (!Platform.isAndroid) return false;

    AppUpdateInfo info;
    try {
      info = await InAppUpdate.checkForUpdate();
    } catch (e) {
      log('[InAppUpdateService] checkForUpdate failed: $e');
      return false;
    }

    if (info.updateAvailability != UpdateAvailability.updateAvailable) {
      return false;
    }

    if (forceUpdate) {
      if (!info.immediateUpdateAllowed) return false;
      try {
        await InAppUpdate.performImmediateUpdate();
        return true;
      } catch (e) {
        log('[InAppUpdateService] performImmediateUpdate failed: $e');
        return false;
      }
    }

    if (!info.flexibleUpdateAllowed || _flexibleUpdateStarted) return false;
    _flexibleUpdateStarted = true;

    try {
      final result = await InAppUpdate.startFlexibleUpdate();
      if (result == AppUpdateResult.success) {
        InAppUpdate.installUpdateListener.listen((status) {
          if (status == InstallStatus.downloaded && context != null) {
            _showRestartSnackbar(context);
          }
        });
      }
    } catch (e) {
      log('[InAppUpdateService] startFlexibleUpdate failed: $e');
    }
    return false;
  }

  void _showRestartSnackbar(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(days: 1),
        behavior: SnackBarBehavior.floating,
        content: const Text('An update has been downloaded.'),
        action: SnackBarAction(
          label: 'RESTART',
          onPressed: () {
            InAppUpdate.completeFlexibleUpdate().catchError((_) {});
          },
        ),
      ),
    );
  }
}
