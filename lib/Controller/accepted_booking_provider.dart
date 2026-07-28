import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/Provider/common_api_helper/common_api_helper.dart';

class AcceptedBookingController with ChangeNotifier {
  // ================= COMMON =================
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  final int _limit = 10;

  /// all | accepted | ongoing | upcoming | completed | cancelled
  String _currentBookingKey = 'all';
  String get currentBookingKey => _currentBookingKey;

  // Booking keys for which the last page has already been fetched.
  final Set<String> _exhausted = {};
  bool get hasMore => !_exhausted.contains(_currentBookingKey);

  // ================= PAGINATION =================
  int _allPage = 1;
  int _acceptedPage = 1;
  int _ongoingPage = 1;
  int _upcomingPage = 1;
  int _completedPage = 1;
  int _cancelledPage = 1;

  // ================= LISTS =================
  final List<dynamic> _allList = [];
  final List<dynamic> _acceptedList = [];
  final List<dynamic> _ongoingList = [];
  final List<dynamic> _upcomingList = [];
  final List<dynamic> _completedList = [];
  final List<dynamic> _cancelledList = [];

  // ================= PUBLIC LIST =================
  List<dynamic> get bookingList {
    switch (_currentBookingKey) {
      case 'ongoing':
        return _ongoingList;
      case 'upcoming':
        return _upcomingList;
      case 'completed':
        return _completedList;
      case 'cancelled':
        return _cancelledList;
      case 'accepted':
        return _acceptedList;
      default:
        return _allList;
    }
  }

  // ================= GET BOOKINGS =================
  Future<void> getBookings(
    BuildContext context, {
    required String
        bookingKey, // all | accepted | ongoing | upcoming | completed | cancelled
    bool isPagination = false,
  }) async {
    _currentBookingKey = bookingKey;

    if (!isPagination) {
      _isLoading = true;
      _exhausted.remove(bookingKey);

      switch (bookingKey) {
        case 'accepted':
          _acceptedPage = 1;
          _acceptedList.clear();
          break;
        case 'ongoing':
          _ongoingPage = 1;
          _ongoingList.clear();
          break;
        case 'upcoming':
          _upcomingPage = 1;
          _upcomingList.clear();
          break;
        case 'completed':
          _completedPage = 1;
          _completedList.clear();
          break;
        case 'cancelled':
          _cancelledPage = 1;
          _cancelledList.clear();
          break;
        default:
          _allPage = 1;
          _allList.clear();
          break;
      }

      notifyListeners();
    } else {
      // Already fetched every page for this key, or a page fetch is in flight.
      if (_exhausted.contains(bookingKey) || _isLoadingMore) return;
      _isLoadingMore = true;
      notifyListeners();
    }

    try {
      final response = await getDataWithParams(
        'user/all_bookings',
        context,
        headers: {
          'Authorization': 'Bearer ${AppConstant.token}',
          'Accept': 'application/json',
        },
        params: {
          'booking_key': bookingKey,
          'page': _getCurrentPage(bookingKey),
          'limit': _limit,
        },
      );

      if (response != null && response['success'] == true) {
        final List list = response['data'] ?? [];
        if (list.length < _limit) _exhausted.add(bookingKey);

        switch (bookingKey) {
          case 'accepted':
            _acceptedList.addAll(list);
            if (list.length == _limit) _acceptedPage++;
            break;

          case 'ongoing':
            _ongoingList.addAll(list);
            if (list.length == _limit) _ongoingPage++;
            break;

          case 'upcoming':
            _upcomingList.addAll(list);
            if (list.length == _limit) _upcomingPage++;
            break;

          case 'completed':
            _completedList.addAll(list);
            if (list.length == _limit) _completedPage++;
            break;

          case 'cancelled':
            _cancelledList.addAll(list);
            if (list.length == _limit) _cancelledPage++;
            break;

          default:
            _allList.addAll(list);
            if (list.length == _limit) _allPage++;
            break;
        }
      }
    } catch (e) {
      debugPrint('❌ Booking Error: $e');
    } finally {
      _isLoading = false;
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  // ================= HELPERS =================
  int _getCurrentPage(String key) {
    switch (key) {
      case 'ongoing':
        return _ongoingPage;
      case 'upcoming':
        return _upcomingPage;
      case 'completed':
        return _completedPage;
      case 'cancelled':
        return _cancelledPage;
      case 'accepted':
        return _acceptedPage;
      default:
        return _allPage;
    }
  }

  // ================= RESET =================
  void reset() {
    _allPage = 1;
    _acceptedPage = 1;
    _ongoingPage = 1;
    _upcomingPage = 1;
    _completedPage = 1;
    _cancelledPage = 1;

    _allList.clear();
    _acceptedList.clear();
    _ongoingList.clear();
    _upcomingList.clear();
    _completedList.clear();
    _cancelledList.clear();

    _exhausted.clear();
    _currentBookingKey = 'all';
    _isLoading = false;
    _isLoadingMore = false;

    notifyListeners();
  }
}
