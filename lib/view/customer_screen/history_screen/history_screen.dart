import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/view/customer_screen/new_booking_flow/retailer_confirm_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const int _limit = 20;

  final List<dynamic> _bookings = [];
  final ScrollController _scrollController = ScrollController();
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _fetchHistory(loadMore: true);
    }
  }

  Future<void> _fetchHistory({bool loadMore = false}) async {
    if (loadMore) {
      if (!_hasMore || _loadingMore) return;
      setState(() => _loadingMore = true);
    } else {
      _page = 1;
      _hasMore = true;
      setState(() => _loading = true);
    }
    try {
      final page = loadMore ? _page + 1 : 1;
      // Routed through common_api_helper (instead of a raw http.get) so a
      // dead/expired token triggers the shared 401/403 handling — which
      // redirects to login — rather than silently failing forever here.
      final data = await getDataWithParams(
        'user/all_bookings',
        context,
        headers: {'Authorization': 'Bearer ${AppConstant.token}'},
        params: {
          'booking_key': 'completed',
          'page': page,
          'limit': _limit,
        },
      );
      if (data != null && data['success'] == true && mounted) {
        final List<dynamic> newItems = data['data'] ?? [];
        setState(() {
          if (!loadMore) _bookings.clear();
          _bookings.addAll(newItems);
          _page = page;
          _hasMore = newItems.length == _limit;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = _loadingMore = false);
  }

  void _bookAgain(Map<String, dynamic> booking) {
    final pickupLoc = booking['pickup_location'];
    final dropLoc   = booking['dropoff_location'];
    if (pickupLoc == null || dropLoc == null) return;

    final double? pickupLat = double.tryParse(pickupLoc['latitude']?.toString() ?? '');
    final double? pickupLng = double.tryParse(pickupLoc['longitude']?.toString() ?? '');
    final double? dropLat   = double.tryParse(dropLoc['latitude']?.toString() ?? '');
    final double? dropLng   = double.tryParse(dropLoc['longitude']?.toString() ?? '');
    if (pickupLat == null || pickupLng == null || dropLat == null || dropLng == null) return;

    int wheelCount(String tag) {
      final t = tag.toLowerCase();
      if (t.contains('2w') || t.contains('scooter') || t.contains('bike')) return 2;
      if (t.contains('3w') || t.contains('loader')) return 3;
      return 4;
    }

    String extractId(dynamic f) {
      if (f == null) return '';
      if (f is Map) return (f['_id'] ?? '').toString();
      return f.toString();
    }

    final String requiredTag = (booking['required_tag'] ?? booking['vehicle_category'] ?? '').toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RetailerConfirmScreen(
          vehicleTypeId:    extractId(booking['vehicleType_id'] ?? booking['vehicle_type_id']),
          subVehicleTypeId: extractId(booking['subVehicleType_id'] ?? booking['sub_vehicle_type_id']),
          vehicleData: {
            'name':               (booking['requested_vehicle_name'] ?? booking['display_vehicle_name'] ?? 'Vehicle').toString(),
            'wheelCount':         wheelCount(requiredTag),
            'vehicleCategory':    (booking['vehicle_category'] ?? requiredTag).toString(),
            'pricingModifier':    '1.0',
            'vehicleKey':         (booking['vehicle_key'] ?? '').toString(),
            'requiredTag':        requiredTag,
            'bookingFlow':        'retailer',
            'displayVehicleName': (booking['display_vehicle_name'] ?? '').toString(),
          },
          pickupData: {'address': (pickupLoc['address'] ?? '').toString(), 'lat': pickupLat, 'lng': pickupLng},
          dropData:   {'address': (dropLoc['address']   ?? '').toString(), 'lat': dropLat,   'lng': dropLng},
          rawDistanceKm:  double.tryParse((booking['distance_in_km'] ?? booking['raw_distance_km'] ?? '0').toString()) ?? 0.0,
          estimatedFare:  int.tryParse((booking['booking_price'] ?? '0').toString()) ?? 0,
          subVehicleTypeList: const [],
          initialReceiverName:  (booking['receiver_name']  ?? '').toString(),
          initialReceiverPhone: (booking['receiver_phone'] ?? '').toString(),
          initialSenderName:    (booking['sender_name']  ?? booking['customer_name']  ?? '').toString(),
          initialSenderPhone:   (booking['sender_phone'] ?? booking['customer_phone'] ?? '').toString(),
          initialNote:          (booking['note'] ?? '').toString(),
          initialGoodsTypeId:   extractId(booking['item_category_id']),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Delivered': return Colors.green;
      case 'Cancelled': return Colors.red;
      default: return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.secondaryColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Booking History',
            style: TextStyle(
                fontFamily: AppFont.fontFamily,
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: AppColor.blackColor)),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColor.themeColor),
            onPressed: _fetchHistory,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColor.themeColor))
          : _bookings.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_rounded, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('No completed bookings yet',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColor.themeColor,
                  onRefresh: () => _fetchHistory(),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _bookings.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= _bookings.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                          ),
                        );
                      }
                      final b = _bookings[i];
                      final pickup = b['pickup_location'];
                      final drop = b['dropoff_location'];
                      final vehicle = b['vehicleType_id'];
                      final status = (b['booking_status'] ?? '') as String;
                      final price = b['booking_price'] ?? 0;
                      final code = b['booking_code'] ?? '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _statusColor(status).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(status,
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _statusColor(status))),
                                  ),
                                  const Spacer(),
                                  Text('#$code', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              if (vehicle != null)
                                Text(vehicle['name'] ?? '',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColor.blackColor)),
                              const SizedBox(height: 8),
                              Row(children: [
                                const Icon(Icons.radio_button_checked, size: 13, color: AppColor.themeColor),
                                const SizedBox(width: 6),
                                Expanded(
                                    child: Text(pickup?['address'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12, color: Colors.grey))),
                              ]),
                              const SizedBox(height: 4),
                              Row(children: [
                                const Icon(Icons.location_on, size: 13, color: Colors.red),
                                const SizedBox(width: 6),
                                Expanded(
                                    child: Text(drop?['address'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12, color: Colors.grey))),
                              ]),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Text('₹${price.toStringAsFixed(0)}',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColor.blackColor)),
                                  const Spacer(),
                                  if (status == 'Delivered')
                                    GestureDetector(
                                      onTap: () => _bookAgain(b),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        decoration: BoxDecoration(color: AppColor.themeColor, borderRadius: BorderRadius.circular(8)),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.replay_rounded, size: 13, color: Colors.white),
                                            SizedBox(width: 4),
                                            Text('Book Again',
                                                style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
