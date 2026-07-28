// driver_eta_banner.dart — Feature 7: Real-time Driver ETA
//
// Placed on the accepted booking detail screen. Polls
// GET /api/v1/app/booking/eta/:bookingId every 60 seconds while
// booking status is Accepted or Arrived.
//
// Usage:
//   DriverEtaBanner(bookingId: '...bookingId...')
//
// If bookingId is empty, the banner silently shows nothing.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_config_provider.dart';
import 'package:movigo/utilities/app_font.dart';

class DriverEtaBanner extends StatefulWidget {
  final String bookingId;

  const DriverEtaBanner({super.key, required this.bookingId});

  @override
  State<DriverEtaBanner> createState() => _DriverEtaBannerState();
}

class _DriverEtaBannerState extends State<DriverEtaBanner> {
  Timer? _timer;
  int? _etaMinutes;
  double? _distanceKm;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    if (widget.bookingId.isNotEmpty) {
      _fetchEta();
      // Refresh every 60 seconds
      _timer = Timer.periodic(const Duration(seconds: 60), (_) => _fetchEta());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchEta() async {
    if (!mounted) return;
    try {
      final url = Uri.parse(
          '${AppConfigProvider.apiUrl}booking/eta/${widget.bookingId}');
      final resp = await http.get(url, headers: {
        'Authorization': 'Bearer ${AppConstant.token}',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 8));

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body['success'] == true && body['data'] != null) {
          final data = body['data'] as Map<String, dynamic>;
          setState(() {
            _etaMinutes  = data['eta_minutes'] as int?;
            _distanceKm  = (data['distance_to_pickup_km'] as num?)?.toDouble();
            _loading     = false;
            _hasError    = false;
          });
          return;
        }
      }
      // 400 = status not Accepted/Arrived — hide banner silently
      if (resp.statusCode == 400) {
        if (mounted) setState(() { _loading = false; _hasError = false; _etaMinutes = null; });
        _timer?.cancel();
        return;
      }
      if (mounted) setState(() { _loading = false; _hasError = true; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to show if booking ID is missing, error, or status is terminal
    if (widget.bookingId.isEmpty || _hasError) return const SizedBox.shrink();
    if (!_loading && _etaMinutes == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1976D2).withOpacity(0.3)),
      ),
      child: _loading
          ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 16, width: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF1976D2)),
                ),
                SizedBox(width: 10),
                Text('Calculating driver ETA...',
                    style: TextStyle(fontSize: 13, color: Color(0xFF1565C0))),
              ],
            )
          : Row(
              children: [
                const Icon(Icons.directions_car, color: Color(0xFF1976D2), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Driver arriving in ~$_etaMinutes min',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0D47A1),
                          fontFamily: AppFont.fontFamily,
                        ),
                      ),
                      if (_distanceKm != null)
                        Text(
                          '${_distanceKm!.toStringAsFixed(1)} km away from pickup',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1565C0),
                            fontFamily: AppFont.fontFamily,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.refresh, color: Color(0xFF1976D2), size: 16),
              ],
            ),
    );
  }
}
