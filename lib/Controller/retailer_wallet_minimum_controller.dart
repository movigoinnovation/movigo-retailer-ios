import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';

class RetailerWalletMinimumController with ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  double _walletBalance = 0;
  double get walletBalance => _walletBalance;

  double _minimumRequiredBalance = 0;
  double get minimumRequiredBalance => _minimumRequiredBalance;

  double _shortAmount = 0;
  double get shortAmount => _shortAmount;

  String _validationMessage = '';
  String get validationMessage => _validationMessage;

  bool _shouldShowPopup = false;
  bool get shouldShowPopup => _shouldShowPopup;

  Future<void> getMinimumWalletAmount(BuildContext context) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await getData(
        'wallet/minimum_amount',
        context,
        headers: {
          'Authorization': 'Bearer ${AppConstant.token}',
          'Accept': 'application/json',
        },
      );

      if (response != null && response['success'] == true) {
        final data = response['data'];

        _walletBalance = (data['wallet_balance'] ?? 0).toDouble();
        _minimumRequiredBalance =
            (data['minimum_required_balance'] ?? 0).toDouble();
        _shortAmount = (data['short_amount'] ?? 0).toDouble();
        _validationMessage = data['validation_message'] ?? '';

        // ✅ Show popup if wallet_balance < minimum_required_balance
        _shouldShowPopup = _walletBalance < _minimumRequiredBalance;
      }
    } catch (e) {
      debugPrint("❌ Retailer Wallet Minimum Error: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void resetPopup() {
    _shouldShowPopup = false;
    notifyListeners();
  }
}
