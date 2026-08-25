import 'dart:async' show Timer, unawaited;

import 'package:flutter/widgets.dart';

import '../models/delivery_zone.dart';
import '../models/ride_service.dart';
import '../shared/delivery_pricing.dart';
import 'api_client.dart';
import 'config_repository.dart';
import 'socket_service.dart';

typedef PricingPayloadHandler = void Function(Map<String, dynamic> payload);

/// Live delivery rate and fee caps from the server.
class DeliveryPricingConfig extends ChangeNotifier with WidgetsBindingObserver {
  DeliveryPricingConfig(this._api, this._socket);

  final ApiClient _api;
  final SocketService _socket;

  Timer? _pollTimer;
  PricingPayloadHandler? _socketHandler;

  double _pricePerKm = defaultDeliveryPricePerKm;
  double _basePricePerKm = defaultDeliveryPricePerKm;
  double? _globalMinFee;
  double? _globalMaxFee;
  List<DeliveryZone> _zones = [];
  final Map<RideServiceType, RideServiceOption> _rideServices = {};
  bool _surgeActive = false;
  double _surgeMultiplier = 1.5;

  double get pricePerKm => _pricePerKm;
  double get basePricePerKm => _basePricePerKm;
  double? get globalMinFee => _globalMinFee;
  double? get globalMaxFee => _globalMaxFee;
  List<DeliveryZone> get zones => List.unmodifiable(_zones);
  Map<RideServiceType, RideServiceOption> get rideServices =>
      Map.unmodifiable(_rideServices);
  bool get surgeActive => _surgeActive;

  RideServiceOption? optionFor(RideServiceType type) => _rideServices[type];

  double? minFeeFor(RideServiceType type, {String? region}) {
    final serviceMin = _rideServices[type]?.minFee;
    final bounds = boundsForRegion(region);
    final mins = [
      if (serviceMin != null && serviceMin > 0) serviceMin,
      if (bounds.min != null && bounds.min! > 0) bounds.min!,
      if (_globalMinFee != null && _globalMinFee! > 0) _globalMinFee!,
    ];
    if (mins.isEmpty) return null;
    return mins.reduce((a, b) => a > b ? a : b);
  }
  double get surgeMultiplier => _surgeMultiplier;

  ({double? min, double? max}) boundsForRegion(String? region) {
    double? zoneMin;
    double? zoneMax;
    if (region != null && region.isNotEmpty) {
      for (final z in _zones) {
        if (z.isActive && z.region == region) {
          zoneMin = z.minPrice > 0 ? z.minPrice : null;
          zoneMax = z.maxPrice;
          break;
        }
      }
    }
    final mins = [
      if (zoneMin != null) zoneMin,
      if (_globalMinFee != null && _globalMinFee! > 0) _globalMinFee!,
    ];
    return (
      min: mins.isEmpty ? null : mins.reduce((a, b) => a > b ? a : b),
      max: zoneMax ?? _globalMaxFee,
    );
  }

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    _socketHandler = (data) {
      _applyPayload(Map<String, dynamic>.from(data));
      unawaited(refresh());
    };
    _socket.addPricingUpdatedListener(_socketHandler!);
    _socket.ensurePricingFeedConnected();
    await refresh();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 60),
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
    final minRaw = data['min_fee'];
    final maxRaw = data['max_fee'];
    final nextMin = minRaw == null
        ? null
        : double.tryParse(minRaw.toString());
    final nextMax = maxRaw == null
        ? null
        : double.tryParse(maxRaw.toString());

    final zonesRaw = data['zones'];
    final nextZones = zonesRaw is List
        ? zonesRaw
            .whereType<Map>()
            .map((e) => DeliveryZone.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <DeliveryZone>[];
    final servicesRaw = data['ride_services'];
    final nextServices = <RideServiceType, RideServiceOption>{};
    if (servicesRaw is List) {
      for (final row in servicesRaw.whereType<Map>()) {
        final option = RideServiceOption.fromJson(Map<String, dynamic>.from(row));
        nextServices[option.type] = option;
      }
    }

    final nextRate = rate > 0 ? rate : defaultDeliveryPricePerKm;
    final nextBase = base > 0 ? base : nextRate;
    final changed = nextRate != _pricePerKm ||
        nextBase != _basePricePerKm ||
        nextMin != _globalMinFee ||
        nextMax != _globalMaxFee ||
        surge != _surgeActive ||
        mult != _surgeMultiplier ||
        !_sameZones(nextZones) ||
        nextServices.length != _rideServices.length;

    _pricePerKm = nextRate;
    _basePricePerKm = nextBase;
    _globalMinFee = nextMin != null && nextMin > 0 ? nextMin : null;
    _globalMaxFee = nextMax != null && nextMax > 0 ? nextMax : null;
    _zones = nextZones;
    _rideServices
      ..clear()
      ..addAll(nextServices);
    _surgeActive = surge;
    _surgeMultiplier = mult > 0 ? mult : 1.5;

    if (changed) {
      debugPrint('[pricing] updated: ₵$_pricePerKm/km surge=$_surgeActive');
      notifyListeners();
    }
  }

  bool _sameZones(List<DeliveryZone> next) {
    if (next.length != _zones.length) return false;
    for (var i = 0; i < next.length; i++) {
      final a = next[i];
      final b = _zones[i];
      if (a.id != b.id ||
          a.minPrice != b.minPrice ||
          a.maxPrice != b.maxPrice ||
          a.isActive != b.isActive) {
        return false;
      }
    }
    return true;
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
