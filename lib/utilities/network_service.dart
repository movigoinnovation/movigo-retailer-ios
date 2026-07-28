import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class NetworkService extends GetxService {
  final Connectivity _connectivity = Connectivity();
  final RxBool isOnline = true.obs;
  OverlayEntry? _overlayEntry;

  Future<NetworkService> init() async {

    final results = await _connectivity.checkConnectivity();
    _updateStatus(results);


    _connectivity.onConnectivityChanged.listen((results) {
      _updateStatus(results);
    });

    return this;
  }

  void _updateStatus(List<ConnectivityResult> results) {
    bool connected = results.any((r) => r != ConnectivityResult.none);

    if (!connected) {
      if (isOnline.value) {
        _showBanner(
          message: "No Internet Connection",
          color: Colors.redAccent,
          persistent: true,
        );
      }
      isOnline.value = false;
    } else {
      if (!isOnline.value) {
        _showBanner(
          message: "We are back online!",
          color: Colors.green,
          persistent: false,
        );
      }
      isOnline.value = true;
    }
  }

  void _showBanner({
    required String message,
    required Color color,
    required bool persistent,
  }) {
    _removeBanner();

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Material(
          color: color,
          child: SafeArea(
            child: Container(
              height: 32,

              padding: const EdgeInsets.symmetric( horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    persistent ? Icons.wifi_off : Icons.wifi,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    message,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final context = Get.overlayContext;
    if (context != null) {
      Overlay.of(context)?.insert(_overlayEntry!);
    }


    if (!persistent) {
      Future.delayed(const Duration(seconds: 3), _removeBanner);
    }
  }

  void _removeBanner() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}