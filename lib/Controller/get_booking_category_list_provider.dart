import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';

class BookingCategoryController with ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<dynamic> _categories = [];
  List<dynamic> get categories => _categories;

  String _searchKey = '';

  // ================= GET CATEGORY LIST (WITH SEARCH) =================
  Future<void>  getCategoryList(
    BuildContext context, {
    String searchKey = '',
  }) async {
    _isLoading = true;
    _searchKey = searchKey;
    notifyListeners();

    try {
      final headers = {
        'Authorization': 'Bearer ${AppConstant.token}',
        'Accept': 'application/json',
      };

      final response = await getData(
        'user/get_category_list?search_key=$_searchKey',
        context,
        headers: headers,
      );

      if (response != null && response['success'] == true) {
        _categories = response['data'] ?? [];
      } else {
        _categories = [];
      }
    } catch (e) {
      debugPrint('❌ Category List Error: $e');
      _categories = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ================= RESET =================
  void reset() {
    _categories.clear();
    _searchKey = '';
    _isLoading = false;
    notifyListeners();
  }
}
