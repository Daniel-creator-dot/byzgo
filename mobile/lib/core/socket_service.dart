import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/order.dart';
import '../models/support_message.dart';
import '../models/trip_message.dart';
import 'env.dart';
import 'push_notification_service.dart';
import 'json_parse.dart';

typedef OrderHandler = void Function(Order order);
typedef OrderIdHandler = void Function(String orderId);
typedef RideTakenHandler = void Function(String orderId, {String? reason});
typedef WalletHandler = void Function(double balance);
typedef LocationHandler = void Function(String riderId, double lat, double lng);
typedef OrderMessageHandler = void Function(String orderId, TripMessage message);
typedef SupportMessageHandler = void Function(String ticketId, SupportMessage message);
typedef ProductUpdatedHandler = void Function(String vendorId, Map<String, dynamic> product);
typedef PulseGuideHandler = void Function({
  required String orderId,
  required double lat,
  required double lng,
  required String phase,
  String? at,
});
typedef StatusUpdatedHandler = void Function({
  required String status,
  bool? isOnline,
  String? reason,
});
typedef VendorPromoHandler = void Function(Map<String, dynamic> promo);

/// Real-time layer — mirrors `src/lib/socket.ts` and `App.tsx` listeners.
class SocketService {
  io.Socket? _socket;
  String? _userId;

  OrderHandler? onRideIncoming;
  RideTakenHandler? onRideTaken;
  OrderHandler? onOrderNew;
  OrderHandler? onOrderUpdated;
  WalletHandler? onWalletUpdated;
  LocationHandler? onLocationUpdated;
  OrderMessageHandler? onOrderMessage;
  final List<OrderMessageHandler> _orderMessageListeners = [];
  SupportMessageHandler? onSupportMessage;
  final List<SupportMessageHandler> _supportMessageListeners = [];
  ProductUpdatedHandler? onProductUpdated;
  PulseGuideHandler? onPulseGuide;
  StatusUpdatedHandler? onStatusUpdated;
  VendorPromoHandler? onVendorPromo;
  final List<VendorPromoHandler> _vendorPromoListeners = [];

  bool get isConnected => _socket?.connected ?? false;

  Future<void> connect({required String userId}) async {
    if (_userId == userId && isConnected) return;
    disconnect(clearCallbacks: false);
    _userId = userId;

    _socket = io.io(
      Env.apiBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(999)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .build(),
    );

    _socket!
      ..onConnect((_) {
        debugPrint('[socket] connected');
        _socket!.emit('join', userId);
      })
      ..on('ride:incoming', _onRideIncoming)
      ..on('ride:taken', _onRideTaken)
      ..on('order:new', _onOrderNew)
      ..on('order:updated', _onOrderUpdated)
      ..on('wallet:updated', _onWalletUpdated)
      ..on('location:updated', _onLocationUpdated)
      ..on('order:message', _onOrderMessage)
      ..on('ticket:message', _onSupportMessage)
      ..on('product:updated', _onProductUpdated)
      ..on('pulse:guide', _onPulseGuide)
      ..on('status:updated', _onStatusUpdated)
      ..on('vendor:promo', _onVendorPromo);
  }

  void addVendorPromoListener(VendorPromoHandler listener) {
    if (!_vendorPromoListeners.contains(listener)) {
      _vendorPromoListeners.add(listener);
    }
  }

  void removeVendorPromoListener(VendorPromoHandler listener) {
    _vendorPromoListeners.remove(listener);
  }

  void _onVendorPromo(dynamic data) {
    final map = _asMap(data);
    if (map == null) return;
    final payload = Map<String, dynamic>.from(map);
    onVendorPromo?.call(payload);
    for (final listener in List<VendorPromoHandler>.from(_vendorPromoListeners)) {
      listener(payload);
    }
  }

  void _onStatusUpdated(dynamic data) {
    final map = _asMap(data);
    if (map == null) return;
    onStatusUpdated?.call(
      status: map['status']?.toString() ?? '',
      isOnline: map['is_online'] as bool?,
      reason: map['reason']?.toString(),
    );
  }

  void _onRideIncoming(dynamic data) {
    if (!PushNotificationService.instance.acceptsIncomingRideJobs) return;
    final order = _parseOrder(data);
    if (order == null) return;
    if (order.expiresAt != null) {
      try {
        if (DateTime.parse(order.expiresAt!).isBefore(DateTime.now())) return;
      } catch (_) {
        return;
      }
    }
    onRideIncoming?.call(order);
  }

  void _onRideTaken(dynamic data) {
    final map = _asMap(data);
    if (map == null || map['orderId'] == null) return;
    onRideTaken?.call(
      map['orderId'].toString(),
      reason: map['reason']?.toString(),
    );
  }

  void _onOrderNew(dynamic data) {
    final order = _parseOrder(data);
    if (order != null) onOrderNew?.call(order);
  }

  void _onOrderUpdated(dynamic data) {
    final order = _parseOrder(data);
    if (order != null) onOrderUpdated?.call(order);
  }

  void _onWalletUpdated(dynamic data) {
    final map = _asMap(data);
    if (map == null || map['balance'] == null) return;
    final balance = parseJsonDouble(map['balance']);
    if (balance == null) return;
    onWalletUpdated?.call(balance);
  }

  void addOrderMessageListener(OrderMessageHandler listener) {
    if (!_orderMessageListeners.contains(listener)) {
      _orderMessageListeners.add(listener);
    }
  }

  void removeOrderMessageListener(OrderMessageHandler listener) {
    _orderMessageListeners.remove(listener);
  }

  void addSupportMessageListener(SupportMessageHandler listener) {
    if (!_supportMessageListeners.contains(listener)) {
      _supportMessageListeners.add(listener);
    }
  }

  void removeSupportMessageListener(SupportMessageHandler listener) {
    _supportMessageListeners.remove(listener);
  }

  void _onSupportMessage(dynamic data) {
    final map = _asMap(data);
    if (map == null || map['ticketId'] == null || map['message'] == null) return;
    try {
      final message = SupportMessage.fromJson(
        Map<String, dynamic>.from(map['message'] as Map),
      );
      final ticketId = map['ticketId'].toString();
      onSupportMessage?.call(ticketId, message);
      for (final listener in List<SupportMessageHandler>.from(_supportMessageListeners)) {
        listener(ticketId, message);
      }
    } catch (e) {
      debugPrint('[socket] bad ticket:message: $e');
    }
  }

  void _onPulseGuide(dynamic data) {
    final map = _asMap(data);
    if (map == null || map['orderId'] == null) return;
    final lat = parseJsonDouble(map['lat']);
    final lng = parseJsonDouble(map['lng']);
    if (lat == null || lng == null) return;
    onPulseGuide?.call(
      orderId: map['orderId'].toString(),
      lat: lat,
      lng: lng,
      phase: map['phase']?.toString() ?? 'pickup',
      at: map['at']?.toString(),
    );
  }

  void _onProductUpdated(dynamic data) {
    final map = _asMap(data);
    if (map == null || map['vendorId'] == null) return;
    final productMap = _asMap(map['product']);
    if (productMap == null) return;
    onProductUpdated?.call(map['vendorId'].toString(), productMap);
  }

  void _onOrderMessage(dynamic data) {
    final map = _asMap(data);
    if (map == null || map['orderId'] == null || map['message'] == null) return;
    try {
      final message = TripMessage.fromJson(
        Map<String, dynamic>.from(map['message'] as Map),
      );
      final orderId = map['orderId'].toString();
      onOrderMessage?.call(orderId, message);
      for (final listener in List<OrderMessageHandler>.from(_orderMessageListeners)) {
        listener(orderId, message);
      }
    } catch (e) {
      debugPrint('[socket] bad order:message: $e');
    }
  }

  void _onLocationUpdated(dynamic data) {
    final map = _asMap(data);
    if (map == null ||
        map['riderId'] == null ||
        map['lat'] == null ||
        map['lng'] == null) {
      return;
    }
    final lat = parseJsonDouble(map['lat']);
    final lng = parseJsonDouble(map['lng']);
    if (lat == null || lng == null) return;
    onLocationUpdated?.call(map['riderId'].toString(), lat, lng);
  }

  Map<String, dynamic>? _asMap(dynamic data) {
    if (data is! Map) return null;
    try {
      return Map<String, dynamic>.from(data);
    } catch (e) {
      debugPrint('[socket] bad map: $e');
      return null;
    }
  }

  Order? _parseOrder(dynamic data) {
    final map = _asMap(data);
    if (map == null) return null;
    try {
      return Order.fromJson(map);
    } catch (e) {
      debugPrint('[socket] bad order payload: $e');
      return null;
    }
  }

  void clearHandlers() {
    onRideIncoming = null;
    onRideTaken = null;
    onOrderNew = null;
    onOrderUpdated = null;
    onWalletUpdated = null;
    onLocationUpdated = null;
    onOrderMessage = null;
    onSupportMessage = null;
    onProductUpdated = null;
    onPulseGuide = null;
    onStatusUpdated = null;
  }

  void emitLocationUpdate({
    required String userId,
    required double lat,
    required double lng,
  }) {
    _socket?.emit('location:update', {
      'userId': userId,
      'lat': lat,
      'lng': lng,
    });
  }

  void disconnect({bool clearCallbacks = true}) {
    _socket?.dispose();
    _socket = null;
    _userId = null;
    if (clearCallbacks) clearHandlers();
  }
}
