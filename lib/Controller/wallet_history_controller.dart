import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';

class WalletHistoryController with ChangeNotifier {
  // ================= COMMON =================
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // int _walletBalance = 0;
  // int get walletBalance => _walletBalance;

  double _walletBalance = 0.0;
  double get walletBalance => _walletBalance;

  String _currentType = 'credit'; // credit | transaction
  String get currentType => _currentType;

  final int _limit = 10;

  // ================= CREDIT =================
  int _creditPage = 1;
  List<dynamic> _creditList = [];

  // ================= TRANSACTION =================
  int _transactionPage = 1;
  List<dynamic> _transactionList = [];

  // ================= PUBLIC LIST =================
  List<dynamic> get historyList =>
      _currentType == 'credit' ? _creditList : _transactionList;

  // ================= GET WALLET HISTORY =================
  Future<void> getWalletHistory(
    BuildContext context, {
    required String type, // credit | transaction
    bool isPagination = false,
  }) async {
    _currentType = type;

    if (!isPagination) {
      _isLoading = true;

      if (type == 'credit') {
        _creditPage = 1;
        _creditList.clear();
      } else {
        _transactionPage = 1;
        _transactionList.clear();
      }

      notifyListeners();
    }

    try {
      final response = await getDataWithParams(
        'wallet/my_wallet_history',
        context,
        headers: {
          'Authorization': 'Bearer ${AppConstant.token}',
          'Accept': 'application/json',
        },
        params: {
          'type': type,
          'page': type == 'credit' ? _creditPage : _transactionPage,
          'limit': _limit,
        },
      );

      if (response != null && response['success'] == true) {
        final data = response['data'];

        // ✅ Wallet balance (same for both tabs)
        // _walletBalance = data['wallet_balance'] ?? 0;
        _walletBalance = (data['wallet_balance'] as num?)?.toDouble() ?? 0.0;

        final List list = data['transactions'] ?? data['list'] ?? [];

        if (type == 'credit') {
          _creditList.addAll(list);
          if (list.length == _limit) _creditPage++;
        } else {
          _transactionList.addAll(list);
          if (list.length == _limit) _transactionPage++;
        }
      }
    } catch (e) {
      debugPrint('❌ Wallet History Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ================= RESET =================
  void reset() {
    _walletBalance = 0.0;

    _creditPage = 1;
    _transactionPage = 1;

    _creditList.clear();
    _transactionList.clear();

    _currentType = 'credit';
    _isLoading = false;

    notifyListeners();
  }
}
