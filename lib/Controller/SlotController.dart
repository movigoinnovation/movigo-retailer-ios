import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';

class SlotController with ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<dynamic> _slots = [];
  List<dynamic> get slots => _slots;

  // ================= GET SLOTS =================
  Future<void> getSlots(BuildContext context, String date) async {
    _isLoading = true;
    notifyListeners();

    try {
      final headers = {
        'Authorization': 'Bearer ${AppConstant.token}',
        'Accept': 'application/json',
      };

      final response = await getData(
        'booking/all_slots?date=$date',
        context,
        headers: headers,
      );

      if (response != null && response['success'] == true) {
        List data = response['data']['slots'] ?? [];

        _slots = data.map((slot) {
          return {
            "start_time": slot['start_time'],
            "end_time": slot['end_time'],
            "slot": slot['slot'],
          };
        }).toList();
      } else {
        _slots = [];
      }
    } catch (e) {
      print('❌ Slot API Error: $e');
      _slots = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ================= RESET =================
  void reset() {
    _slots.clear();
    _isLoading = false;
    notifyListeners();
  }
}