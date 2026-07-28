import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';

class HelplineController with ChangeNotifier {
  // ================= COMMON =================
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<dynamic> _helplineList = [];
  List<dynamic> get helplineList => _helplineList;

  // ================= GET HELPLINES =================
  Future<void> getHelplines(BuildContext context) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await getData(
        'contact/get_helplines',
        context,
        headers: {
          'Authorization': 'Bearer ${AppConstant.token}',
          'Accept': 'application/json',
        },
      );

      if (response != null && response['success'] == true) {
        final List list = response['data'] ?? [];
        _helplineList = list;
      }
    } catch (e) {
      debugPrint('❌ Get Helplines Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ================= RESET =================
  void reset() {
    _helplineList.clear();
    _isLoading = false;
    notifyListeners();
  }
}
