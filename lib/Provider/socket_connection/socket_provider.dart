import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '/utilities/app_constant.dart';

void _log(Object? msg) { if (kDebugMode) print(msg); }

class SocketProvider extends ChangeNotifier with WidgetsBindingObserver {
  IO.Socket? socket;
  String? userId;

  // ── Pusher for driver live location ───────────────────────────────────────
  final PusherChannelsFlutter _pusher = PusherChannelsFlutter.getInstance();
  bool _pusherInitialized = false;
  Completer<void>? _pusherInitCompleter;
  String? _trackingBookingId;

  // ── Retailer personal channel (milestone_reached events) ──────────────────
  String? _retailerChannelName;
  final StreamController<Map<String, dynamic>> _milestoneController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get milestoneStream => _milestoneController.stream;

  // ── Retailer booking reassignment event stream ───────────────────────────
  final StreamController<Map<String, dynamic>> _reassigningController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get reassigningStream => _reassigningController.stream;

  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  List<dynamic> _bookingList = [];
  List<dynamic> get bookingList => _bookingList;

  bool? _isDriverAccepted;
  bool? get isDriverAccepted => _isDriverAccepted;

  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> get messages => _messages;

  Map<String, double>? _lastDriverLocation;
  Map<String, double>? get lastDriverLocation => _lastDriverLocation;

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      final raw = value.trim();
      if (raw.isEmpty) return null;

      // Handle values like "22.74869," or "lat:22.74869"
      final normalized = raw.replaceAll(',', '.');
      final direct = double.tryParse(normalized);
      if (direct != null) return direct;

      final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(raw);
      if (match != null) {
        return double.tryParse(match.group(0)!);
      }
      return null;
    }
    return double.tryParse(value.toString());
  }

  SocketProvider() {
    WidgetsBinding.instance.addObserver(this);
  }

  // ================= APP LIFECYCLE =================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _reconnectIfLoggedIn();
    }
  }

  // ================= CHECK LOGIN & RECONNECT =================
  Future<void> _reconnectIfLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDetails = prefs.getString("user_details");

      if (userDetails != null && userDetails.isNotEmpty) {
        final data = json.decode(userDetails);
        final String? newUserId = (data['_id'] ?? data['user_id'])?.toString();

        if (newUserId != null && newUserId.isNotEmpty) {
          userId = newUserId;
          await initSocket(AppConstant.token);
        }
      }
    } catch (e) {
      debugPrint('❌ Reconnect check error: $e');
    }
  }

  // ================= INIT SOCKET =================
  Future<void> initSocket(String jwtToken) async {
    if (socket != null && socket!.connected) {
      debugPrint("ℹ️ Socket already connected, refreshing listeners");
      _setupListeners();
      return;
    }

    debugPrint('🎯 initSocket called');

    if (jwtToken.isEmpty) {
      debugPrint('🚫 Token empty, socket not connecting');
      return;
    }

    // Socket.IO requires WebSocket upgrade which shared hosting (LiteSpeed) doesn't support.
    // Real-time updates handled via Pusher (driver location) and HTTP polling (booking status).
    debugPrint('ℹ️ Socket.IO disabled on shared hosting — using Pusher + polling');
    return;
  }

  // ================= LISTENERS =================
  void _setupListeners() {
    // ✅ Clear old listeners to avoid duplicate handlers
    socket!.clearListeners();

    socket!.onConnect((_) {
      debugPrint('✅ Socket connected');
      _isConnected = true;
      notifyListeners();
    });

    socket!.onDisconnect((reason) {
      debugPrint('❌ Socket disconnected: $reason');
      _isConnected = false;
      notifyListeners();
    });

    socket!.on("booking_status", (data) {
      debugPrint("📥 SOCKET EVENT booking_status received");
      _isDriverAccepted = data['is_driver_accepted'];
      notifyListeners();
    });

    socket!.onConnectError((err) {
      _log('🚫 Socket connect error: $err');
      _isConnected = false;
      notifyListeners();
    });

    socket!.onError((err) {
      _log('⚠️ Socket error: $err');
      _isConnected = false;
      notifyListeners();
    });

    socket!.onReconnect((attempt) {
      _log('🔄 Socket reconnected after $attempt attempts');
      _isConnected = true;
      notifyListeners();
    });

    // for Old MSG
    socket!.on('get_message_list', (data) {
      _log('📥 SOCKET get_message_list => $data');

      if (data is List) {
        final newMessages = List<Map<String, dynamic>>.from(data)
            .reversed
            .toList(); // 👈 reverse

        if (newMessages.isEmpty) {
          _hasMore = false;
          _log("ℹ️ No more messages to load");
          return;
        }

        if (_currentPage == 1) {
          _messages = newMessages;
        } else {
          _messages = [...newMessages, ..._messages]; // old upar add
        }

        notifyListeners();
      }
    });

    // send
    // ✅ When server confirms / echoes sent message
    socket!.on('send_message', (data) {
      _log('📥 [SEND_MESSAGE ACK] => $data');

      if (data == null) return;

      Map<String, dynamic>? incoming;

      if (data is Map && data['newObj'] != null) {
        incoming = Map<String, dynamic>.from(data['newObj']);
      } else if (data is Map) {
        incoming = Map<String, dynamic>.from(data);
      }

      if (incoming == null) return;

      // 🔁 Try to replace optimistic message (tmp_...) with real one
      final index = _messages.indexWhere((m) =>
          m['_id'] != null &&
          m['_id'].toString().startsWith('tmp_') &&
          m['message'] == incoming!['message'] &&
          m['booking_id'] == incoming!['booking_id']);

      if (index != -1) {
        // Replace temp with real message
        _messages[index] = incoming;
        _log("🔁 Replaced temp message with server message");
      } else {
        // If not found, just add
        _messages.add(incoming);
        _log("➕ Added new server message");
      }

      notifyListeners();
    });

    // For new MSG
    socket!.on('receive_message', (data) {
      _log('📥 [RECEIVE RAW] => $data');

      if (data == null) return;

      Map<String, dynamic>? incoming;

      // Server newObj ke andar bhej raha hai
      if (data is Map && data['newObj'] != null) {
        incoming = Map<String, dynamic>.from(data['newObj']);
      } else if (data is Map) {
        incoming = Map<String, dynamic>.from(data);
      }

      if (incoming == null) return;

      _log('📥 [RECEIVE PARSED] => $incoming');

      // ✅ Direct add karo, koi duplicate check nahi (abhi ke liye)
      _messages.add(incoming);
      notifyListeners();

      _log("✅ Message added, total = ${_messages.length}");
    });

    // ================= DRIVER LIVE LOCATION =================
    socket!.on('driver_live_location', (data) {
      _log('📍 SOCKET driver_live_location => $data');

      if (data == null) return;

      try {
        final root = data is Map ? Map<String, dynamic>.from(data) : null;
        final nestedData = root?['data'] is Map
            ? Map<String, dynamic>.from(root!['data'])
            : null;
        final driverObj = nestedData?['driver_id'] is Map
            ? Map<String, dynamic>.from(nestedData!['driver_id'])
            : null;

        final lat = _toDouble(root?['latitude']) ??
            _toDouble(nestedData?['latitude']) ??
            _toDouble(driverObj?['latitude']);
        final lng = _toDouble(root?['longitude']) ??
            _toDouble(nestedData?['longitude']) ??
            _toDouble(driverObj?['longitude']);

        if (lat == null || lng == null) {
          _log("❌ driver_live_location missing valid coordinates. raw=$data");
          return;
        }

        _log("✅ driver_live_location parsed => lat=$lat, lng=$lng");
        _lastDriverLocation = {'lat': lat, 'lng': lng};
        notifyListeners();
      } catch (e) {
        _log("❌ Error parsing driver location: $e");
      }
    });

    // (Future use) message deleted
    // socket!.on('message_deleted', (data) {
    //   _log('📥 SOCKET message_deleted => $data');
    // });
  }

  // ================= EMIT ACCEPT / REJECT =================
  void emitBookingAcceptReject({
    required String userId,
    required String bookingId,
    required String driverId,
    required String action,
  }) {
    if (socket == null || !socket!.connected) {
      _log("❌ Socket not connected, cannot emit booking_accept_reject");
      return;
    }

    final data = {
      "user_id": userId,
      "booking_id": bookingId,
      "driver_id": driverId,
      "action": action,
    };

    _log("📤 SOCKET EMIT booking_accept_reject => $data");
    socket!.emit("booking_accept_reject", data);
  }

  // ================= CLEANUP =================
  void disconnect() {
    if (socket != null) {
      socket!.clearListeners();
      socket!.disconnect();
      socket!.dispose();
      socket = null;
      _isConnected = false;
      notifyListeners();
    }
    _stopTrackingDriver();
  }

  // ── Retailer personal Pusher channel ─────────────────────────────────────

  Future<void> _ensurePusherInitialized() async {
    if (_pusherInitialized) return;
    if (_pusherInitCompleter != null) {
      await _pusherInitCompleter!.future;
      return;
    }
    _pusherInitCompleter = Completer<void>();
    try {
      await _pusher.init(apiKey: 'fbc781bd287b02cbfce3', cluster: 'ap2');
      await _pusher.connect();
      _pusherInitialized = true;
      _pusherInitCompleter!.complete();
    } catch (e) {
      _pusherInitCompleter!.completeError(e);
      _pusherInitCompleter = null;
      rethrow;
    }
  }

  /// Subscribes to 'customer-{userId}' for both milestone_reached (retailer coins)
  /// and booking-status (driver accepted/arrived/etc.) events.
  Future<void> subscribeRetailerChannel(String userId) async {
    if (userId.isEmpty) return;
    final channelName = 'customer-$userId';
    // Skip entirely if already subscribed to this channel
    if (_retailerChannelName == channelName && _pusherInitialized) return;
    try {
      await _ensurePusherInitialized();
      if (_retailerChannelName != null && _retailerChannelName != channelName) {
        try { await _pusher.unsubscribe(channelName: _retailerChannelName!); } catch (_) {}
      }
      await _pusher.subscribe(
        channelName: channelName,
        onEvent: (event) {
          if (event.eventName == 'milestone_reached') {
            _handleMilestoneEvent(event.data);
          } else if (event.eventName == 'booking-status') {
            _handleBookingStatusEvent(event.data);
          } else if (event.eventName == 'booking_reassigning') {
            _handleBookingReassigningEvent(event.data);
          }
        },
      );
      _retailerChannelName = channelName;
      debugPrint('✅ Subscribed to customer channel $channelName (milestone_reached + booking-status + booking_reassigning)');
    } catch (e) {
      debugPrint('❌ subscribeRetailerChannel error: $e');
    }
  }

  void _handleBookingReassigningEvent(dynamic data) {
    try {
      Map<String, dynamic> payload = {};
      if (data is String) {
        payload = jsonDecode(data) as Map<String, dynamic>;
      } else if (data is Map) {
        payload = Map<String, dynamic>.from(data);
      }
      debugPrint('📬 Pusher booking_reassigning event received: $payload');
      _isDriverAccepted = false;
      notifyListeners();
      
      if (!_reassigningController.isClosed) {
        _reassigningController.add(payload);
      }
    } catch (e) {
      debugPrint('❌ _handleBookingReassigningEvent error: $e');
    }
  }

  void _handleBookingStatusEvent(dynamic data) {
    try {
      Map<String, dynamic> payload = {};
      if (data is String) {
        payload = jsonDecode(data) as Map<String, dynamic>;
      } else if (data is Map) {
        payload = Map<String, dynamic>.from(data);
      }
      final status = (payload['status'] ?? '').toString();
      debugPrint('📬 Pusher booking-status event received: status=$status');
      if (status == 'Accepted') {
        _isDriverAccepted = true;
        notifyListeners();
        debugPrint('✅ isDriverAccepted set to true — FindingDriverScreen will navigate');
      }
    } catch (e) {
      debugPrint('❌ _handleBookingStatusEvent error: $e');
    }
  }

  void _handleMilestoneEvent(dynamic data) {
    try {
      Map<String, dynamic> payload = {};
      if (data is String) {
        payload = jsonDecode(data) as Map<String, dynamic>;
      } else if (data is Map) {
        payload = Map<String, dynamic>.from(data);
      }
      if (!_milestoneController.isClosed) {
        _milestoneController.add(payload);
      }
    } catch (e) {
      debugPrint('❌ _handleMilestoneEvent error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disconnect();
    if (_pusherInitialized) {
      try { _pusher.disconnect(); } catch (_) {}
    }
    _milestoneController.close();
    _reassigningController.close();
    super.dispose();
  }

  void emitBookingStatus({
    required String userId,
    required String bookingId,
  }) {
    if (socket == null || !socket!.connected) {
      _log("❌ Socket not connected, cannot emit check_booking");
      return;
    }

    final Map<String, dynamic> data = {
      "user_id": userId,
      "booking_id": bookingId,
    };

    _log("📤 SOCKET EMIT check_booking => $data");
    socket!.emit("check_booking", data);
  }

  void myBookingStatus({
    required String userId,
    required String bookingId,
  }) {
    emitBookingStatus(userId: userId, bookingId: bookingId);
  }

  void setDriverAccepted(bool value) {
    _isDriverAccepted = value;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DRIVER LIVE LOCATION — via Pusher (booking-{bookingId} channel)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Call this when driver accepts the booking.
  /// Subscribes to Pusher channel and starts receiving driver-location events.
  Future<void> startTrackingDriver({required String bookingId}) async {
    if (_trackingBookingId == bookingId) return; // already tracking
    await _stopTrackingDriver(); // unsubscribe from any previous booking

    try {
      await _ensurePusherInitialized();

      await _pusher.subscribe(
        channelName: 'booking-$bookingId',
        onEvent: (event) {
          if (event.eventName == 'driver-location') {
            _handleDriverLocationEvent(event.data);
          }
        },
      );
      _trackingBookingId = bookingId;
      debugPrint('✅ Started tracking driver on channel booking-$bookingId');
    } catch (e) {
      debugPrint('❌ startTrackingDriver error: $e');
    }
  }

  /// Call this when booking is Delivered or Cancelled.
  Future<void> stopTrackingDriver() async {
    await _stopTrackingDriver();
    _lastDriverLocation = null;
    notifyListeners();
  }

  Future<void> _stopTrackingDriver() async {
    if (_trackingBookingId != null) {
      try {
        await _pusher.unsubscribe(channelName: 'booking-$_trackingBookingId');
        debugPrint('🛑 Stopped tracking driver for booking-$_trackingBookingId');
      } catch (_) {}
      _trackingBookingId = null;
    }
  }

  void _handleDriverLocationEvent(dynamic data) {
    try {
      Map<String, dynamic> payload = {};
      if (data is String) {
        payload = json.decode(data);
      } else if (data is Map) {
        payload = Map<String, dynamic>.from(data);
      }

      final nestedData = payload['data'] is Map
          ? Map<String, dynamic>.from(payload['data'])
          : null;
      final driverObj = payload['driver'] is Map
          ? Map<String, dynamic>.from(payload['driver'])
          : payload['driver_id'] is Map
              ? Map<String, dynamic>.from(payload['driver_id'])
              : nestedData?['driver_id'] is Map
                  ? Map<String, dynamic>.from(nestedData!['driver_id'])
                  : null;

      final lat = _toDouble(payload['lat']) ??
          _toDouble(payload['latitude']) ??
          _toDouble(nestedData?['lat']) ??
          _toDouble(nestedData?['latitude']) ??
          _toDouble(driverObj?['latitude']);
      final lng = _toDouble(payload['lng']) ??
          _toDouble(payload['longitude']) ??
          _toDouble(nestedData?['lng']) ??
          _toDouble(nestedData?['longitude']) ??
          _toDouble(driverObj?['longitude']);

      if (lat != null && lng != null) {
        _lastDriverLocation = {'lat': lat, 'lng': lng};
        debugPrint('📍 Driver location via Pusher: lat=$lat lng=$lng booking=$_trackingBookingId');
        notifyListeners();
      } else {
        debugPrint('⚠️ Pusher driver-location received without coordinates: $payload');
      }
    } catch (e) {
      debugPrint('❌ _handleDriverLocationEvent error: $e');
    }
  }

  // Keep for backward compatibility — now a no-op since Pusher handles it
  void emitDriverLiveLocation({
    required String userId,
    required String bookingId,
  }) {
    // Driver location is now pushed by backend via Pusher.
    // This method is kept so MapImageScreen doesn't need changes.
    if (_trackingBookingId != bookingId) {
      startTrackingDriver(bookingId: bookingId);
    }
  }

  // ================= Get Message List (with pagination) =================
  void getMessageList({
    required String userId,
    required String bookingId,
    int page = 1,
    int limit = 30,
  }) {
    if (socket == null || !socket!.connected) {
      _log("❌ Socket not connected, cannot get message list");
      return;
    }

    final data = {
      "user_id": userId,
      "booking_id": bookingId,
      "page": page,
      "limit": limit,
    };

    _log("📤 SOCKET EMIT get_message_list => $data");
    socket!.emit("get_message_list", data);
  }

  // ================= Join Chat =================
  // ================= JOIN CHAT (Feature 16 — Pusher-based, not socket.io) =================
  // Subscribes to the Pusher 'chat-<bookingId>' channel and loads message history via HTTP.
  // This replaces the broken socket.io emit("join_chat") approach.
  Future<void> joinChat({
    required String userId,
    required String bookingId,
    String? otherUserId,
  }) async {
    _currentPage = 1;
    _hasMore = true;
    _messages = [];
    notifyListeners();

    final channelName = 'chat-$bookingId';
    if (_currentChatChannel == channelName) return;

    try {
      if (_currentChatChannel != null) {
        await _pusher.unsubscribe(channelName: _currentChatChannel!);
      }
      await _pusher.subscribe(
        channelName: channelName,
        onEvent: (event) {
          if (event.eventName == 'new-message') {
            _handleIncomingMessage(event.data);
          }
        },
      );
      _currentChatChannel = channelName;
      await _getMessageListHttp(bookingId: bookingId, page: 1, limit: 30);
    } catch (e) {
      _log('joinChat error: $e');
    }
  }

  String? _currentChatChannel;

  void _handleIncomingMessage(dynamic data) {
    try {
      Map<String, dynamic> incoming = {};
      if (data is String) {
        incoming = jsonDecode(data) as Map<String, dynamic>;
      } else if (data is Map) {
        incoming = Map<String, dynamic>.from(data);
      }
      if (incoming['_id'] != null) {
        if (_messages.any((m) => m['_id'] == incoming['_id'])) return;
      }
      _messages.insert(0, incoming);
      notifyListeners();
    } catch (e) {
      _log('_handleIncomingMessage error: $e');
    }
  }

  Future<void> _getMessageListHttp({required String bookingId, int page = 1, int limit = 30}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? AppConstant.token;
      final response = await http.get(
        Uri.parse('${AppConstant.apiBaseUrl}chat/messages?booking_id=$bookingId&page=$page&limit=$limit'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 movigo',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<Map<String, dynamic>> newMessages =
            List<Map<String, dynamic>>.from(data['data'] ?? []);
        if (newMessages.isEmpty) { _hasMore = false; return; }
        newMessages.sort((a, b) {
          final at = DateTime.tryParse(a['createdAt']?.toString() ?? '');
          final bt = DateTime.tryParse(b['createdAt']?.toString() ?? '');
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
        if (page == 1) { _messages = newMessages; } else { _messages = [..._messages, ...newMessages]; }
        notifyListeners();
      }
    } catch (e) {
      _log('_getMessageListHttp error: $e');
    }
  }

  // ================= Leave Chat =================
  Future<void> leaveChat({
    required String userId,
    required String bookingId,
  }) async {
    if (_currentChatChannel != null) {
      await _pusher.unsubscribe(channelName: _currentChatChannel!);
      _currentChatChannel = null;
    }
  }

  // ================= Send MSG (Feature 16 — HTTP POST to /chat/send) =================
  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String bookingId,
    required String message,
  }) async {
    final now = DateTime.now();
    final formattedTime = "${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}";
    final optimistic = {
      'sender_id': senderId,
      'receiver_id': receiverId,
      'booking_id': bookingId,
      'message': message,
      'type': 'message',
      'time': formattedTime,
      'createdAt': now.toIso8601String(),
    };
    _messages.insert(0, optimistic);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? AppConstant.token;
      final response = await http.post(
        Uri.parse('${AppConstant.apiBaseUrl}chat/send'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 movigo',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'booking_id': bookingId, 'receiver_id': receiverId, 'message': message}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final saved = Map<String, dynamic>.from(data['data'] ?? {});
        final idx = _messages.indexWhere((m) => m['_id'] == null && m['message'] == message && m['sender_id'] == senderId);
        if (idx != -1) _messages[idx] = saved;
        notifyListeners();
      }
    } catch (e) {
      _log('sendMessage error: $e');
    }
  }

  // ================= Load more (pagination) =================
  void loadMoreMessages({
    required String userId,
    required String bookingId,
    int limit = 30,
  }) {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    _currentPage += 1;
    _log("📤 Loading more messages: page=$_currentPage");
    // Bug 3 fix: use HTTP (Pusher-based) instead of broken socket.io getMessageList
    _getMessageListHttp(
      bookingId: bookingId,
      page: _currentPage,
      limit: limit,
    ).then((_) {
      _isLoadingMore = false;
    });
  }

//
}
