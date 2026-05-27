import 'dart:async' show Timer, unawaited;

import 'package:flutter/widgets.dart';

import '../shared/delivery_pricing.dart';
import 'api_client.dart';
import 'config_repository.dart';
import 'socket_service.dart';

typedef PricingPayloadHandler = void Function(Map<String, dynamic> payload);

/// Live delivery rate from the server — updates on socket push, poll, and app resume.
class DeliveryPricingConfig extends ChangeNotifier with WidgetsBindingObserver {
  DeliveryPricingConfig(this._api, this._socket);

  final ApiClient _api;
  final SocketService _socket;

  Timer? _pollTimer;
  PricingPayloadHandler? _socketHandler;

  double _pricePerKm = defaultDeliveryPricePerKm;
  double _basePricePerKm = defaultDeliveryPricePerKm;
  bool _surgeActive = false;
  double _surgeMultiplier = 1.5;

  double get pricePerKm => _pricePerKm;
  double get basePricePerKm => _basePricePerKm;
  bool get surgeActive => _surgeActive;
  double get surgeMultiplier => _surgeMultiplier;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    _socketHandler = (data) {
      _applyPayload(Map<String, dynamic>.from(data));
      // Confirm rate from API (socket can race with DB write on some networks).
      unawaited(refresh());
    };
    _socket.addPricingUpdatedListener(_socketHandler!);
    _socket.ensurePricingFeedConnected();
    await refresh();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => refresh(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _socket.ensurePricingFeedConnected();
      refresh();
    }
  }

  Future<void> refresh() async {
    try {
      final data = await ConfigRepository(_api).fetchPricingPayload();
      _applyPayload(data);
    } catch (e) {
      debugPrint('[pricing] refresh failed: $e');
    }
  }

  /// Reconnect pricing socket after logout (session socket is torn down).
  Future<void> onAuthChanged() async {
    _socket.ensurePricingFeedConnected();
    await refresh();
  }

  void _applyPayload(Map<String, dynamic> data) {
    final rate =
        double.tryParse(data['price_per_km']?.toString() ?? '') ??
            defaultDeliveryPricePerKm;
    final base =
        double.tryParse(data['base_price_per_km']?.toString() ?? '') ?? rate;
    final surge = data['surge_active'] == true;
    final mult =
        double.tryParse(data['surge_multiplier']?.toString() ?? '') ?? 1.5;

    final nextRate = rate > 0 ? rate : defaultDeliveryPricePerKm;
    final nextBase = base > 0 ? base : nextRate;
    final changed = nextRate != _pricePerKm ||
        nextBase != _basePricePerKm ||
        surge != _surgeActive ||
        mult != _surgeMultiplier;

    _pricePerKm = nextRate;
    _basePricePerKm = nextBase;
    _surgeActive = surge;
    _surgeMultiplier = mult > 0 ? mult : 1.5;

    if (changed) {
      debugPrint('[pricing] updated: ₵$_pricePerKm/km surge=$_surgeActive');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    if (_socketHandler != null) {
      _socket.removePricingUpdatedListener(_socketHandler!);
    }
    super.dispose();
  }
}
