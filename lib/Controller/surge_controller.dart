// surge_controller.dart — Feature 3: Surge Multiplier
// Fetches pricing.surge_multiplier from /app_settings on app start.
// Retailer app + Individual app share the same package name 'movigo'.

import 'package:flutter/material.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:provider/provider.dart';

class SurgeController with ChangeNotifier {
  double _multiplier = 1.0;
  bool _isLoading = false;

  double get multiplier => _multiplier;
  bool get isSurgeActive => _multiplier > 1.0;
  bool get isLoading => _isLoading;

  /// Call this on app start (e.g. from home_screen initState or splash).
  Future<void> fetchSurge(BuildContext context) async {
    _isLoading = true;
    notifyListeners();
    try {
      final uc = Provider.of<UserController>(context, listen: false);
      final res = await getData(
        'app_settings',
        context,
        headers: {
          'Authorization': 'Bearer ${uc.getToken}',
          'Accept': 'application/json',
        },
      );
      if (res != null && res['success'] == true) {
        final pricing = res['data']?['pricing'];
        if (pricing != null) {
          _multiplier = (pricing['surge_multiplier'] ?? 1.0).toDouble();
        }
      }
    } catch (e) {
      debugPrint('[SurgeController] fetch error: $e');
    }
    _isLoading = false;
    notifyListeners();
  }
}
