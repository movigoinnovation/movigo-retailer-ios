import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';

class VehicleTypeController with ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<dynamic> _vehicleTypes = [];
  List<dynamic> get vehicleTypes => _vehicleTypes;

  Future<void> getVehicleTypeList(BuildContext context) async {
    _isLoading = true;
    notifyListeners();

    try {
      final headers = {
        'Authorization': 'Bearer ${AppConstant.token}',
        'Accept': 'application/json',
      };

      final response = await getData(
        'auth/get_vehicle_list',
        context,
        headers: headers,
      );

      if (response != null && response['success'] == true) {
        List data = response['data'] ?? [];

        _vehicleTypes = data.map((vehicle) {
          List subTypes = vehicle['sub_types'] ?? [];

          double pricePerKm = 0;

          if (subTypes.isNotEmpty) {
            pricePerKm = (subTypes[0]['price_per_km'] ?? 0).toDouble();
          }

          return {
            ...vehicle,
            "price_per_km": pricePerKm,
          };
        }).toList();
      } else {
        _vehicleTypes = [];
      }
    } catch (e) {
      print('âŒ Vehicle List Error: $e');
      _vehicleTypes = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void reset() {
    _vehicleTypes.clear();
    _isLoading = false;
    notifyListeners();
  }
}
