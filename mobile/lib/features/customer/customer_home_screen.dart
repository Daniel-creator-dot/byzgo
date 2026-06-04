import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/config_repository.dart';
import '../../core/directions_service.dart';
import '../../core/location_service.dart';
import '../../core/places_service.dart';
import '../../core/push_notification_service.dart';
import '../../core/session.dart';
import '../../core/socket_service.dart';
import '../../core/trip_chat_unread.dart';
import '../../models/trip_message.dart';
import '../../models/location_point.dart';
import '../../models/nearby_rider.dart';
import '../../models/order.dart';
import '../../shared/format.dart';
import '../../shared/delivery_pricing.dart';
import '../../shared/user_display.dart';
import '../../shared/ghana_location.dart';
import '../../shared/rider_trip.dart';
import '../../shared/customer_trip.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/live_trip_map_overlay.dart';
import '../../shared/widgets/ride_google_map.dart';
import '../../shared/widgets/bytz_scaffold.dart';
import '../../shared/widgets/ride_ui.dart';
import '../orders/orders_repository.dart';
import '../riders/riders_repository.dart';
import '../../shared/widgets/location_autocomplete_field.dart';
import 'customer_delivery_ui.dart';
import 'customer_trip_tracking.dart';

/// Customer home — map + book bike delivery + track active trips.
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({
    super.key,
    this.embedded = false,
    this.vendorMode = false,
    this.initialPickup,
    this.onOpenShops,
    this.onOpenWallet,
    this.onOpenActivity,
    this.onOpenProfile,
  });

  final bool embedded;
  /// Merchant sending a package (hide shops shortcut, store-oriented copy).
  final bool vendorMode;
  final LocationPoint? initialPickup;
  final VoidCallback? onOpenShops;
  final VoidCallback? onOpenWallet;
  final VoidCallback? onOpenActivity;
  final VoidCallback? onOpenProfile;

  @override
  State<CustomerHomeScreen> createState() => CustomerHomeScreenState();
}

class CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final _pickupCtrl = TextEditingController();
  final _dropoffCtrl = TextEditingController();
  final _itemCtrl = TextEditingController(text: 'Package');
  final _sheetScrollCtrl = ScrollController();

  LocationPoint? _pickup;
  LocationPoint? _destination;
  MapPickMode _pickMode = MapPickMode.destination;

  List<Order> _orders = [];
  bool _loading = true;
  bool _booking = false;
  bool _locatingPickup = false;
  bool _resolvingPickup = false;
  bool _resolvingDropoff = false;
  String? _error;
  double _pricePerKm = defaultDeliveryPricePerKm;
  double? _quotedFee;
  double? _quoteDistanceKm;
  bool _surgeActive = false;
  bool _quoteLoading = false;
  String? _quoteError;
  Timer? _quoteDebounce;
  LocationPoint? _riderPosition;
  List<NearbyRider> _nearbyRiderRecords = [];
  List<LocationPoint> _routePoints = [];
  String? _etaPhrase;
  int? _etaMinutes;
  String? _etaDistanceText;
  DateTime? _etaExpiresAt;
  int? _searchPickupMinutes;
  String? _searchPickupPhrase;
  DateTime? _searchPickupExpiresAt;
  String? _trackingPickupLabel;
  String? _trackingDropoffLabel;
  Timer? _nearbyPoll;
  Timer? _etaPoll;
  Timer? _riderLocationPoll;
  DateTime? _lastEtaFetch;
  LocationPoint? _lastEtaOrigin;
  SocketService? _socket;
  OrderMessageHandler? _chatNotifyHandler;
  final _mapKey = GlobalKey<RideGoogleMapState>();

  OrdersRepository get _ordersRepo => context.read<OrdersRepository>();
  RidersRepository get _ridersRepo => context.read<RidersRepository>();
  Session get _session => context.read<Session>();
  LocationService get _location => context.read<LocationService>();
  PlacesService get _places => context.read<PlacesService>();
  DirectionsService get _directions => context.read<DirectionsService>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _socket ??= context.read<SocketService>();
  }

  double get _deliveryFee {
    if (_quotedFee != null) return _quotedFee!;
    if (_quoteError != null) return 0;
    if (_pickup == null || _destination == null) return 0;
    if (!_pickup!.hasCoords || !_destination!.hasCoords) return 0;
    return courierFeeBetween(_pickup!, _destination!, _pricePerKm);
  }

  double get _routeDistanceKm {
    if (_quoteDistanceKm != null && _quoteDistanceKm! > 0) return _quoteDistanceKm!;
    if (_pickup == null || _destination == null) return 0;
    if (!_pickup!.hasCoords || !_destination!.hasCoords) return 0;
    return haversineDistanceKm(
      _pickup!.lat,
      _pickup!.lng,
      _destination!.lat,
      _destination!.lng,
    );
  }

  String get _packageType => _itemCtrl.text.trim().isEmpty ? 'Package' : _itemCtrl.text.trim();

  Order? get _activeCourier {
    final userId = _session.user?.id;
    if (userId == null) return null;
    Order? newest;
    for (final o in _orders) {
      if (o.customerId != userId) continue;
      if (['delivered', 'cancelled'].contains(o.status)) continue;
      final type = o.orderType ?? '';
      final active = type == 'courier' ||
          type == 'food' ||
          customerOrderHasShopPickup(o) ||
          (o.pickup != null && o.pickup!.trim().isNotEmpty);
      if (!active) continue;
      if (newest == null) {
        newest = o;
        continue;
      }
      try {
        final a = DateTime.parse(o.createdAt);
        final b = DateTime.parse(newest.createdAt);
        if (a.isAfter(b)) newest = o;
      } catch (_) {
        newest = o;
      }
    }
    return newest;
  }

  /// After marketplace checkout — show trip on map and in lists.
  void noteOrder(Order order) => _replaceOrder(order);

  void applyShopPickup(LocationPoint pickup) {
    final label = displayLocationLabel(pickup.address, pickup.lat, pickup.lng);
    setState(() {
      _pickup = pickup.copyWith(address: label);
      _pickupCtrl.text = label;
      _pickMode = MapPickMode.pickup;
    });
  }

  @override
  void initState() {
    super.initState();
    final seed = widget.initialPickup;
    if (seed != null) {
      final label = displayLocationLabel(seed.address, seed.lat, seed.lng);
      _pickup = seed.copyWith(address: label);
      _pickupCtrl.text = label;
      _pickMode = MapPickMode.pickup;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _init();
    });
  }

  Future<void> _init() async {
    _wireSocket();
    try {
      _pricePerKm = await context.read<ConfigRepository>().fetchPricePerKm();
    } catch (_) {}
    await _loadOrders();
    await _detectPickup();
    if (!mounted) return;
    final p = _pickup;
    if (p != null &&
        p.hasCoords &&
        (looksLikeCoordinates(p.address) || p.address.isEmpty)) {
      await _applyCoordsFromMap(
        isPickup: true,
        lat: p.lat,
        lng: p.lng,
        existing: p.address,
      );
    }
  }

  bool get _searchingBiker {
    final active = _activeCourier;
    return active != null && customerIsSearchingBiker(active);
  }

  LocationPoint? _pickupForOrder(Order order) {
    if (order.pickupLat != null &&
        order.pickupLng != null &&
        hasValidCoords(order.pickupLat!, order.pickupLng!)) {
      return LocationPoint(
        address: order.pickupAddress ?? order.pickup ?? '',
        lat: order.pickupLat!,
        lng: order.pickupLng!,
      );
    }
    return _pickup;
  }

  void _syncNearbyPoll() {
    if (_searchingBiker) {
      if (_nearbyPoll == null) {
        _fetchNearbyRiders();
        _nearbyPoll = Timer.periodic(
          const Duration(seconds: 10),
          (_) => _fetchNearbyRiders(),
        );
      }
    } else {
      _nearbyPoll?.cancel();
      _nearbyPoll = null;
      if (_nearbyRiderRecords.isNotEmpty && mounted) {
        setState(() => _nearbyRiderRecords = []);
      }
      _clearSearchPickupEta();
    }
  }

  void _clearSearchPickupEta() {
    if (_searchPickupMinutes == null &&
        _searchPickupPhrase == null &&
        _searchPickupExpiresAt == null) {
      return;
    }
    setState(() {
      _searchPickupMinutes = null;
      _searchPickupPhrase = null;
      _searchPickupExpiresAt = null;
    });
  }

  Future<void> _fetchNearbyRiders() async {
    final active = _activeCourier;
    if (active == null || !customerIsSearchingBiker(active)) return;
    final center = _pickupForOrder(active);
    if (center == null || !center.hasCoords) return;
    try {
      final riders = await _ridersRepo.fetchNearby(
        lat: center.lat,
        lng: center.lng,
      );
      if (!mounted) return;
      setState(() => _nearbyRiderRecords = riders);
      unawaited(_refreshSearchPickupEta(active, riders, center));
      unawaited(_refreshTripPreviewRoute(active));
    } catch (_) {}
  }

  Future<void> _refreshTripPreviewRoute(Order order) async {
    final pickup = _mapPickupForTracking(order);
    final dest = _mapDestinationForTracking(order);
    if (pickup == null ||
        dest == null ||
        !pickup.hasCoords ||
        !dest.hasCoords) {
      return;
    }
    final summary = await _directions.fetchRoute(
      origin: pickup,
      destination: dest,
    );
    if (!mounted || summary == null) return;
    setState(() => _routePoints = summary.points);
  }

  Future<void> _refreshSearchPickupEta(
    Order order,
    List<NearbyRider> riders,
    LocationPoint pickup,
  ) async {
    if (!customerIsSearchingBiker(order)) return;
    if (riders.isEmpty) {
      if (!mounted) return;
      setState(() {
        _searchPickupMinutes = null;
        _searchPickupPhrase = null;
        _searchPickupExpiresAt = null;
      });
      return;
    }
    final nearest = riders.first;
    final summary = await _directions.fetchRoute(
      origin: nearest.toLocationPoint(),
      destination: pickup,
    );
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      if (summary != null) {
        _searchPickupMinutes = summary.etaMinutes;
        _searchPickupPhrase = summary.arrivalPhrase;
        _searchPickupExpiresAt = summary.expiresAtFrom(now);
      } else {
        final km = nearest.distanceKm ?? 1;
        final mins = (km / 0.35).ceil().clamp(2, 25);
        _searchPickupMinutes = mins;
        _searchPickupPhrase = 'about $mins min';
        _searchPickupExpiresAt = now.add(Duration(minutes: mins));
      }
    });
  }

  Future<void> _hydrateRiderPosition(Order order) async {
    final riderId = order.riderId;
    if (riderId == null || riderId.isEmpty) return;
    try {
      final loc = await _ridersRepo.fetchRiderLocation(riderId);
      if (!mounted || loc == null) return;
      setState(() => _riderPosition = loc);
      final active = _activeCourier;
      if (active?.id == order.id) {
        _mapKey.currentState?.fitAllMarkers();
        unawaited(_refreshEta(active!));
      }
    } catch (_) {}
  }

  void _syncRiderLocationPoll(Order order) {
    _riderLocationPoll?.cancel();
    final hasRider = order.riderId != null &&
        !['delivered', 'cancelled'].contains(order.status);
    if (!hasRider) {
      _riderLocationPoll = null;
      return;
    }
    unawaited(_hydrateRiderPosition(order));
    _riderLocationPoll = Timer.periodic(const Duration(seconds: 8), (_) {
      final active = _activeCourier;
      if (active != null) unawaited(_hydrateRiderPosition(active));
    });
  }

  void _scheduleDeliveryQuote() {
    _quoteDebounce?.cancel();
    _quoteDebounce = Timer(const Duration(milliseconds: 450), _refreshDeliveryQuote);
  }

  Future<void> _refreshDeliveryQuote() async {
    if (_pickup == null || _destination == null) return;
    if (!_pickup!.hasCoords || !_destination!.hasCoords) {
      if (!mounted) return;
      setState(() {
        _quotedFee = null;
        _quoteDistanceKm = null;
        _surgeActive = false;
        _quoteLoading = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _quoteLoading = true;
      _quoteError = null;
    });
    try {
      final region = _session.user?.region;
      final q = await _ordersRepo.calculateRouteDelivery(
        pickupLat: _pickup!.lat,
        pickupLng: _pickup!.lng,
        destLat: _destination!.lat,
        destLng: _destination!.lng,
        pickupRegion: region,
        destinationRegion: region,
      );
      if (!mounted) return;
      setState(() {
        _quotedFee = q.deliveryFee;
        _quoteDistanceKm = q.distanceKm;
        _pricePerKm = q.pricePerKm;
        _surgeActive = q.surgeActive;
        _quoteLoading = false;
        _quoteError = null;
      });
      _revealQuoteInSheet();
    } catch (e) {
      if (!mounted) return;
      final msg = OrdersRepository.errorMessage(e);
      setState(() {
        _quotedFee = null;
        _quoteLoading = false;
        _quoteError = msg;
      });
      _snack(msg);
    }
  }

  @override
  void dispose() {
    _quoteDebounce?.cancel();
      _nearbyPoll?.cancel();
      _etaPoll?.cancel();
      _riderLocationPoll?.cancel();
    if (_chatNotifyHandler != null) {
      _socket?.removeOrderMessageListener(_chatNotifyHandler!);
    }
    _socket?.clearHandlers();
    _sheetScrollCtrl.dispose();
    _pickupCtrl.dispose();
    _dropoffCtrl.dispose();
    _itemCtrl.dispose();
    super.dispose();
  }

  void _revealQuoteInSheet() {
    if (!_sheetScrollCtrl.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_sheetScrollCtrl.hasClients) return;
      _sheetScrollCtrl.animateTo(
        _sheetScrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _wireSocket() {
    final socket = _socket;
    if (socket == null) return;
    socket.clearHandlers();
    if (_chatNotifyHandler != null) {
      socket.removeOrderMessageListener(_chatNotifyHandler!);
    }
    _chatNotifyHandler = (orderId, message) => _onTripChatMessage(orderId, message);
    socket.addOrderMessageListener(_chatNotifyHandler!);
    socket.onPulseGuide = ({
      required orderId,
      required lat,
      required lng,
      required phase,
      at,
    }) {
      if (!mounted) return;
      setState(() {
        _orders = _orders.map((o) {
          if (o.id != orderId) return o;
          return o.copyWithPulseGuide(lat: lat, lng: lng, phase: phase, at: at);
        }).toList();
      });
    };

    socket.onOrderNew = (order) {
      if (!mounted) return;
      if (order.customerId != _session.user?.id) return;
      _replaceOrder(order);
    };

    socket.onOrderUpdated = (order) {
      if (!mounted) return;
      final prev = _orders.where((o) => o.id == order.id).firstOrNull;
      setState(() {
        final i = _orders.indexWhere((o) => o.id == order.id);
        if (i >= 0) {
          _orders[i] = order;
        } else {
          _orders = [order, ..._orders];
        }
      });
      if (order.customerId == _session.user?.id) {
        if (order.status == 'delivered' && prev?.status != 'delivered') {
          unawaited(PushNotificationService.instance.showTripAlert(
            title: 'Delivered',
            body: 'Your delivery is complete',
            orderId: order.id,
          ));
        } else if (order.status == 'arrived' && prev?.status != 'arrived') {
          unawaited(PushNotificationService.instance.showTripAlert(
            title: 'Biker arrived',
            body: 'Complete payment to get your delivery PIN',
            orderId: order.id,
            highPriority: true,
          ));
        } else if (order.riderId != null && prev?.riderId == null) {
          final shop = customerOrderHasShopPickup(order);
          unawaited(PushNotificationService.instance.showTripAlert(
            title: shop ? 'Rider heading to shop' : 'Biker found',
            body: shop
                ? 'Going to ${customerShopLabel(order)} to pick up your order'
                : 'Your biker is on the way',
            orderId: order.id,
          ));
        } else if (order.status == 'picked_up' && prev?.status != 'picked_up') {
          final shop = customerOrderHasShopPickup(order);
          unawaited(PushNotificationService.instance.showTripAlert(
            title: shop ? 'Picked up from shop' : 'On the way',
            body: shop
                ? 'Collected at ${customerShopLabel(order)} — heading to you'
                : 'Your biker is heading to your address',
            orderId: order.id,
            highPriority: true,
          ));
        }
      }
      if (order.status == 'delivered' && prev?.status != 'delivered') {
        _snack('Delivered — thanks for using BytzGO!', success: true);
      } else if (order.status == 'arrived' && prev?.status != 'arrived') {
        _snack('Driver arrived — complete payment for your PIN', success: true);
      } else if (order.status == 'picked_up' && prev?.status != 'picked_up') {
        if (customerOrderHasShopPickup(order)) {
          _snack(
            'Picked up at ${customerShopLabel(order)} — rider is on the way to you',
            success: true,
          );
        } else {
          _snack('Picked up — heading to your address', success: true);
        }
      } else if (order.riderId != null && prev?.riderId == null) {
        if (customerOrderHasShopPickup(order)) {
          _snack(
            'Rider found — heading to ${customerShopLabel(order)} to collect your order',
            success: true,
          );
        } else {
          _snack('Biker found — they\'re on the way', success: true);
        }
      }
      _syncNearbyPoll();
      _syncEtaPoll(order);
      _syncRiderLocationPoll(order);
      if (order.riderId != null && prev?.riderId != order.riderId) {
        unawaited(_hydrateRiderPosition(order));
      }
      if (prev != null &&
          prev.status != order.status &&
          order.riderId != null &&
          !['delivered', 'cancelled'].contains(order.status)) {
        _lastEtaFetch = null;
        _lastEtaOrigin = null;
        unawaited(_refreshEta(order));
      }
      if (_activeCourier?.id == order.id) {
        unawaited(_resolveTrackingLabels(order));
      }
    };
    socket.onWalletUpdated = (balance) {
      if (!mounted) return;
      _session.patchBalance(balance);
    };
    socket.onLocationUpdated = (riderId, lat, lng) {
      final active = _activeCourier;
      if (active?.riderId != riderId) return;
      if (!mounted) return;
      setState(() {
        _riderPosition = LocationPoint(
          address: 'Your biker',
          lat: lat,
          lng: lng,
        );
      });
      _mapKey.currentState?.fitAllMarkers();
      if (active != null) unawaited(_refreshEta(active));
    };
  }

  void _onTripChatMessage(String orderId, TripMessage message) {
    final userId = _session.user?.id;
    if (userId == null || message.senderId == userId) return;
    context.read<TripChatUnread>().markUnread(orderId);
    final preview = message.body.length > 120
        ? '${message.body.substring(0, 117)}…'
        : message.body;
    unawaited(PushNotificationService.instance.showTripAlert(
      title: message.displaySenderName,
      body: preview,
      type: 'trip-message',
      orderId: orderId,
      highPriority: true,
    ));
  }

  Future<void> _resolveTrackingLabels(Order order) async {
    var pickupLabel = order.pickupAddress ?? order.pickup ?? '';
    if (order.pickupLat != null &&
        order.pickupLng != null &&
        hasValidCoords(order.pickupLat!, order.pickupLng!)) {
      pickupLabel = await _places.resolveAddressLabel(
        order.pickupLat!,
        order.pickupLng!,
        existing: pickupLabel,
      );
    } else {
      pickupLabel = displayLocationLabel(
        pickupLabel,
        order.pickupLat ?? 0,
        order.pickupLng ?? 0,
      );
    }

    var dropLabel = order.address;
    if (order.lat != null &&
        order.lng != null &&
        hasValidCoords(order.lat!, order.lng!)) {
      dropLabel = await _places.resolveAddressLabel(
        order.lat!,
        order.lng!,
        existing: dropLabel,
      );
    } else {
      dropLabel = displayLocationLabel(dropLabel, order.lat ?? 0, order.lng ?? 0);
    }

    if (!mounted) return;
    setState(() {
      _trackingPickupLabel = pickupLabel;
      _trackingDropoffLabel = dropLabel;
    });
  }

  void _syncEtaPoll(Order order) {
    final hasRider = order.riderId != null &&
        !['delivered', 'cancelled'].contains(order.status);
    if (hasRider) {
      _clearSearchPickupEta();
      final needsPoll = _etaPoll == null;
      if (needsPoll) {
        unawaited(_hydrateRiderPosition(order));
        unawaited(_refreshEta(order));
        _etaPoll = Timer.periodic(
          const Duration(seconds: 12),
          (_) {
            final active = _activeCourier;
            if (active != null) unawaited(_refreshEta(active));
          },
        );
      }
    } else {
      _etaPoll?.cancel();
      _etaPoll = null;
      if (_etaPhrase != null ||
          _routePoints.isNotEmpty ||
          _etaMinutes != null) {
        setState(() {
          _etaPhrase = null;
          _routePoints = [];
          _etaMinutes = null;
          _etaDistanceText = null;
          _etaExpiresAt = null;
        });
      }
    }
  }

  Future<void> _refreshEta(Order order) async {
    if (_riderPosition == null || !_riderPosition!.hasCoords) {
      if (order.riderId != null) {
        await _hydrateRiderPosition(order);
      }
      if (_riderPosition == null || !_riderPosition!.hasCoords) return;
    }
    final target = customerRiderNavTarget(order);
    if (target == null || !target.hasCoords) return;

    final origin = _riderPosition!;
    final now = DateTime.now();
    if (_lastEtaFetch != null &&
        _lastEtaOrigin != null &&
        now.difference(_lastEtaFetch!) < const Duration(seconds: 12)) {
      final moved = haversineDistanceKm(
        _lastEtaOrigin!.lat,
        _lastEtaOrigin!.lng,
        origin.lat,
        origin.lng,
      );
      if (moved < 0.03) return;
    }

    final summary = await _directions.fetchRoute(
      origin: origin,
      destination: target,
    );
    if (!mounted || summary == null) return;
    _lastEtaFetch = now;
    _lastEtaOrigin = origin;
    setState(() {
      _etaPhrase = summary.arrivalPhrase;
      _routePoints = summary.points;
      _etaMinutes = summary.etaMinutes;
      _etaDistanceText = summary.distanceText;
      _etaExpiresAt = summary.expiresAtFrom(now);
    });
  }

  LocationPoint? _mapPickupForTracking(Order? active) {
    if (active == null) return _pickup;
    if (active.pickupLat != null &&
        active.pickupLng != null &&
        hasValidCoords(active.pickupLat!, active.pickupLng!)) {
      return LocationPoint(
        address: _trackingPickupLabel ??
            displayLocationLabel(
              active.pickupAddress ?? active.pickup ?? '',
              active.pickupLat!,
              active.pickupLng!,
            ),
        lat: active.pickupLat!,
        lng: active.pickupLng!,
      );
    }
    return _pickup;
  }

  LocationPoint? _mapDestinationForTracking(Order? active) {
    if (active == null) return _destination;
    if (active.lat != null &&
        active.lng != null &&
        hasValidCoords(active.lat!, active.lng!)) {
      return LocationPoint(
        address: _trackingDropoffLabel ??
            displayLocationLabel(active.address, active.lat!, active.lng!),
        lat: active.lat!,
        lng: active.lng!,
      );
    }
    return _destination;
  }

  void _replaceOrder(Order order) {
    setState(() {
      final i = _orders.indexWhere((o) => o.id == order.id);
      if (i >= 0) {
        _orders[i] = order;
      } else {
        _orders = [order, ..._orders];
      }
      if (order.status == 'cancelled') {
        _riderPosition = null;
        _nearbyRiderRecords = [];
        _etaPhrase = null;
        _etaMinutes = null;
        _etaDistanceText = null;
        _etaExpiresAt = null;
        _searchPickupMinutes = null;
        _searchPickupPhrase = null;
        _searchPickupExpiresAt = null;
        _routePoints = [];
        _lastEtaFetch = null;
        _lastEtaOrigin = null;
      }
    });
    _syncNearbyPoll();
    _syncEtaPoll(order);
    _syncRiderLocationPoll(order);
    if (order.status == 'cancelled') {
      _nearbyPoll?.cancel();
      _nearbyPoll = null;
      _etaPoll?.cancel();
      _etaPoll = null;
      _riderLocationPoll?.cancel();
      _riderLocationPoll = null;
      _snack('Delivery request cancelled', success: true);
    }
  }

  Future<void> _detectPickup() async {
    await _applyCurrentLocation(toPickup: true);
  }

  Future<void> _applyCurrentLocation({required bool toPickup}) async {
    if (toPickup) {
      setState(() => _locatingPickup = true);
    }
    try {
      LocationPoint? loc = await _location.getCurrentLocation();
      final user = _session.user;
      if (loc == null &&
          user?.lat != null &&
          user?.lng != null &&
          hasValidCoords(user!.lat!, user.lng!)) {
        loc = LocationPoint(
          address: user.address ?? '',
          lat: user.lat!,
          lng: user.lng!,
        );
      }
      if (loc == null && kDebugMode) {
        loc = accraDefaultPoint();
      }
      if (loc == null) {
        if (mounted) {
          _snack(
            'Turn on location for Ghana, search an address, or tap the map to set pickup.',
          );
        }
        return;
      }
      if (!mounted) return;

      await _applyCoordsFromMap(
        isPickup: toPickup,
        lat: loc.lat,
        lng: loc.lng,
        existing: loc.address,
      );
    } finally {
      if (mounted && toPickup) setState(() => _locatingPickup = false);
    }
  }

  Future<void> _applyCoordsFromMap({
    required bool isPickup,
    required double lat,
    required double lng,
    String? existing,
  }) async {
    if (!mounted) return;
    setState(() {
      if (isPickup) {
        _resolvingPickup = true;
        _pickup = LocationPoint(address: '', lat: lat, lng: lng);
        _pickupCtrl.text = 'Finding address…';
        _pickMode = MapPickMode.pickup;
      } else {
        _resolvingDropoff = true;
        _destination = LocationPoint(address: '', lat: lat, lng: lng);
        _dropoffCtrl.text = 'Finding address…';
        _pickMode = MapPickMode.destination;
      }
    });

    final label = await _places.resolveAddressLabel(lat, lng, existing: existing);
    if (!mounted) return;
    final point = LocationPoint(address: label, lat: lat, lng: lng);
    setState(() {
      if (isPickup) {
        _pickup = point;
        _pickupCtrl.text = label;
        _resolvingPickup = false;
      } else {
        _destination = point;
        _dropoffCtrl.text = label;
        _resolvingDropoff = false;
      }
    });
    _scheduleDeliveryQuote();
  }

  Future<void> _loadOrders() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _ordersRepo.fetchOrders();
      if (!mounted) return;
      final userId = _session.user?.id;
      setState(() {
        _orders = userId == null
            ? list
            : list.where((o) => o.customerId == userId).toList();
        _loading = false;
      });
      _syncNearbyPoll();
      final active = _activeCourier;
      if (active != null) {
        unawaited(_resolveTrackingLabels(active));
        _syncEtaPoll(active);
        _syncRiderLocationPoll(active);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = OrdersRepository.errorMessage(e);
        _loading = false;
      });
    }
  }

  void _onMapTap(double lat, double lng) {
    final isPickup = _pickMode == MapPickMode.pickup;
    _applyCoordsFromMap(isPickup: isPickup, lat: lat, lng: lng);
  }

  Future<void> _onPickupLocation(LocationPoint point) async {
    if (!point.hasCoords) {
      setState(() {
        _pickup = point;
        _pickupCtrl.text = point.address;
        _pickMode = MapPickMode.pickup;
      });
      _scheduleDeliveryQuote();
      return;
    }
    setState(() {
      _resolvingPickup = true;
      _pickupCtrl.text = 'Finding address…';
      _pickMode = MapPickMode.pickup;
    });
    final label = await _places.resolveAddressLabel(
      point.lat,
      point.lng,
      existing: point.address,
    );
    if (!mounted) return;
    final resolved = LocationPoint(address: label, lat: point.lat, lng: point.lng);
    setState(() {
      _pickup = resolved;
      _pickupCtrl.text = label;
      _resolvingPickup = false;
    });
    _scheduleDeliveryQuote();
  }

  Future<void> _onDropoffLocation(LocationPoint point) async {
    if (!point.hasCoords) {
      setState(() {
        _destination = point;
        _dropoffCtrl.text = point.address;
        _pickMode = MapPickMode.destination;
      });
      _scheduleDeliveryQuote();
      return;
    }
    setState(() {
      _resolvingDropoff = true;
      _dropoffCtrl.text = 'Finding address…';
      _pickMode = MapPickMode.destination;
    });
    final label = await _places.resolveAddressLabel(
      point.lat,
      point.lng,
      existing: point.address,
    );
    if (!mounted) return;
    final resolved = LocationPoint(address: label, lat: point.lat, lng: point.lng);
    setState(() {
      _destination = resolved;
      _dropoffCtrl.text = label;
      _resolvingDropoff = false;
    });
    _scheduleDeliveryQuote();
  }

  void _onAddressEdited({required bool isPickup, required String text}) {
    final current = isPickup ? _pickup : _destination;
    if (current != null && text.trim() == current.address.trim()) return;
    final draft = LocationPoint(address: text, lat: 0, lng: 0);
    setState(() {
      if (isPickup) {
        _pickup = draft;
      } else {
        _destination = draft;
      }
    });
  }

  double? _expectedTotalFromOrderError(Object err) {
    if (err is! DioException || err.response?.statusCode != 400) return null;
    final data = err.response?.data;
    if (data is! Map) return null;
    final expected = data['expected_total'];
    if (expected is num && expected > 0) return expected.toDouble();
    return null;
  }

  Future<double?> _fetchFreshDeliveryQuote() async {
    if (_pickup == null ||
        _destination == null ||
        !_pickup!.hasCoords ||
        !_destination!.hasCoords) {
      return null;
    }
    final region = _session.user?.region;
    final q = await _ordersRepo.calculateRouteDelivery(
      pickupLat: _pickup!.lat,
      pickupLng: _pickup!.lng,
      destLat: _destination!.lat,
      destLng: _destination!.lng,
      pickupRegion: region,
      destinationRegion: region,
    );
    if (!mounted) return null;
    setState(() {
      _quotedFee = q.deliveryFee;
      _quoteDistanceKm = q.distanceKm;
      _pricePerKm = q.pricePerKm;
      _surgeActive = q.surgeActive;
      _quoteLoading = false;
      _quoteError = null;
    });
    return q.deliveryFee;
  }

  Future<void> _requestDelivery() async {
    if (_session.user == null) {
      _snack('Sign in to request a delivery');
      return;
    }
    final inProgress = _activeCourier;
    if (inProgress != null && customerIsSearchingBiker(inProgress)) {
      _snack('You already have a ride in progress — track it on the map');
      return;
    }
    if (inProgress != null && inProgress.riderId != null) {
      _snack('Finish or cancel your current trip before booking another');
      return;
    }
    if (_pickup == null || !_pickup!.hasCoords) {
      _snack('Set pickup — allow location, search, or pick a shop');
      return;
    }
    if (_destination == null || !_destination!.hasCoords) {
      _snack('Choose a drop-off from search or tap the map');
      return;
    }

    setState(() => _booking = true);
    HapticFeedback.mediumImpact();
    try {
      _quoteDebounce?.cancel();
      if (mounted) {
        setState(() {
          _quoteLoading = true;
          _quoteError = null;
        });
      }

      double? fee;
      try {
        fee = await _fetchFreshDeliveryQuote();
      } catch (e) {
        if (mounted) {
          final msg = OrdersRepository.errorMessage(e);
          setState(() {
            _quotedFee = null;
            _quoteLoading = false;
            _quoteError = msg;
          });
        }
        _snack(OrdersRepository.errorMessage(e));
        return;
      }

      if (fee == null || fee <= 0) {
        _snack('Could not calculate delivery fee. Check your connection and try again.');
        return;
      }

      final pickup = _pickup!.copyWith(
        address: _pickupCtrl.text.trim().isEmpty
            ? _pickup!.address
            : _pickupCtrl.text.trim(),
      );
      final dest = _destination!.copyWith(
        address: _dropoffCtrl.text.trim().isEmpty
            ? _destination!.address
            : _dropoffCtrl.text.trim(),
      );
      final itemDescription = _itemCtrl.text.trim().isEmpty
          ? 'Package'
          : _itemCtrl.text.trim();

      try {
        final order = await _ordersRepo.createCourierOrder(
          pickup: pickup,
          destination: dest,
          deliveryFee: fee,
          region: _session.user?.region,
          itemDescription: itemDescription,
        );
        if (!mounted) return;
        setState(() {
          _orders = [order, ..._orders];
        });
        _syncNearbyPoll();
        _snack('Bike requested — waiting for a rider', success: true);
      } catch (e) {
        final retryFee = _expectedTotalFromOrderError(e);
        if (retryFee != null) {
          try {
            final order = await _ordersRepo.createCourierOrder(
              pickup: pickup,
              destination: dest,
              deliveryFee: retryFee,
              region: _session.user?.region,
              itemDescription: itemDescription,
            );
            if (!mounted) return;
            setState(() {
              _quotedFee = retryFee;
              _orders = [order, ..._orders];
            });
            _syncNearbyPoll();
            _snack('Bike requested — waiting for a rider', success: true);
            return;
          } catch (e2) {
            _snack(OrdersRepository.errorMessage(e2));
            return;
          }
        }
        _snack(OrdersRepository.errorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _booking = false;
          _quoteLoading = false;
        });
      }
    }
  }

  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? BytzGoTheme.accentDark : BytzGoTheme.sheetText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeCourier;
    final tracking = active != null;
    final fee = _deliveryFee;
    final searching = tracking && customerIsSearchingBiker(active);
    final hasRider = tracking && active.riderId != null;
    final mapPickup = tracking ? _mapPickupForTracking(active) : _pickup;
    final mapDest = tracking ? _mapDestinationForTracking(active) : _destination;
    final navTarget = tracking ? customerRiderNavTarget(active) : null;
    final showRiderOnMap = hasRider && !searching;

    return RideShell(
      mapChild: RideGoogleMap(
        key: _mapKey,
        pickup: mapPickup,
        destination: mapDest,
        riderPosition: showRiderOnMap ? _riderPosition : null,
        riderNavTarget: navTarget,
        nearbyRiders: searching
            ? _nearbyRiderRecords.map((r) => r.toLocationPoint()).toList()
            : const [],
        showSearchRadar: searching,
        showRiderApproachRadar: showRiderOnMap && _riderPosition != null,
        showRoute: (searching && _routePoints.length >= 2) ||
            (!searching &&
                ((mapPickup != null &&
                        mapDest != null &&
                        mapPickup.hasCoords &&
                        mapDest.hasCoords) ||
                    _routePoints.length >= 2 ||
                    (showRiderOnMap && navTarget != null))),
        showLiveRiderRoute: showRiderOnMap && _routePoints.isEmpty,
        routePoints: _routePoints.length >= 2
            ? _routePoints
            : (showRiderOnMap &&
                    _riderPosition != null &&
                    navTarget != null
                ? [_riderPosition!, navTarget]
                : const []),
        followRider: showRiderOnMap,
        mapPickMode: _pickMode,
        onMapTap: tracking ? null : _onMapTap,
      ),
      floatingMapChild: tracking
          ? LiveTripMapHud(
              order: active,
              searching: searching,
              nearbyCount: searching ? _nearbyRiderRecords.length : null,
              etaPhrase: searching ? _searchPickupPhrase : _etaPhrase,
              etaMinutes: searching ? _searchPickupMinutes : _etaMinutes,
              etaDistanceText: _etaDistanceText,
              etaExpiresAt:
                  searching ? _searchPickupExpiresAt : _etaExpiresAt,
              riderPosition: _riderPosition,
              navTarget: navTarget,
              onRecenter: () => _mapKey.currentState?.fitAllMarkers(),
            )
          : null,
      sheet: RideSheet(
        scrollController: _sheetScrollCtrl,
        collapsible: tracking,
        collapsedHeight: 234,
        initiallyExpanded: active != null &&
            (active.status == 'arrived' || active.status == 'delivered'),
        maxHeightFraction: tracking
            ? (widget.embedded ? 0.72 : 0.8)
            : (widget.embedded ? (fee > 0 ? 0.64 : 0.58) : (fee > 0 ? 0.78 : 0.72)),
        bottomInset: widget.embedded ? 12 : 0,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        footerPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        scrollBottomPadding: !tracking && fee > 0 ? 12 : 0,
        footer: !tracking
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RideAnimatedReveal(
                    visible: fee > 0,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DeliveryQuoteCard(
                        key: ValueKey('fee-$fee-$_surgeActive'),
                        fee: fee,
                        distanceKm: _routeDistanceKm,
                        surgeActive: _surgeActive,
                        loading: _quoteLoading,
                      ),
                    ),
                  ),
                  RidePrimaryButton(
                    label: fee > 0
                        ? 'Request bike · ${formatCedis(fee)}'
                        : 'Request bike',
                    icon: Icons.two_wheeler,
                    loading: _booking,
                    onPressed: _requestDelivery,
                  ),
                ],
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!tracking && widget.embedded) ...[
              DeliveryBookingHeader(
                firstName: userFirstName(_session.user!),
                balance: _session.user?.balance ?? 0,
                vendorMode: widget.vendorMode,
                onShops: widget.vendorMode ? null : widget.onOpenShops,
                onWallet: widget.onOpenWallet,
                onTrips: widget.onOpenActivity,
                onProfile: widget.onOpenProfile,
              ),
              const SizedBox(height: 14),
            ],
            if (tracking) ...[
              CustomerDeliveryTracker(
                order: active,
                onOrderUpdated: _replaceOrder,
                etaPhrase: searching ? _searchPickupPhrase : _etaPhrase,
                etaMinutes: searching ? _searchPickupMinutes : _etaMinutes,
                etaDistanceText: _etaDistanceText,
                etaExpiresAt:
                    searching ? _searchPickupExpiresAt : _etaExpiresAt,
                pickupLabel: _trackingPickupLabel,
                dropoffLabel: _trackingDropoffLabel,
                riderPosition: _riderPosition,
                navTarget: navTarget,
                searching: searching,
                nearbyCount: _nearbyRiderRecords.length,
              ),
            ],
            if (!tracking) ...[
              if (!widget.embedded) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/branding/onboarding_delivery.png',
                    height: 72,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                'Plan your trip',
                style: BytzGoTheme.sheetTitle(18),
              ),
              const SizedBox(height: 4),
              Text(
                'Search and pick a suggestion, or tap the map to pin pickup & drop-off',
                style: BytzGoTheme.sheetBody(13),
              ),
              if ((_pickup != null && !_pickup!.hasCoords) ||
                  (_destination != null && !_destination!.hasCoords)) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: BytzGoTheme.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: BytzGoTheme.warning.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18, color: BytzGoTheme.warning),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Select an address from the list or tap the map — typed text alone is not enough.',
                          style: BytzGoTheme.sheetBody(12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              MapPickModeChips(
                mode: _pickMode,
                onMode: (m) => setState(() => _pickMode = m),
              ),
              const SizedBox(height: 12),
              VisualRouteCard(
                pickupChild: LocationAutocompleteField(
                  icon: pickupDot(),
                  hint: 'Pickup — your location or address',
                  controller: _pickupCtrl,
                  locating: _locatingPickup,
                  resolving: _resolvingPickup,
                  showUseMyLocation: true,
                  onUseMyLocation: () => _applyCurrentLocation(toPickup: true),
                  onTap: () => setState(() => _pickMode = MapPickMode.pickup),
                  onLocation: _onPickupLocation,
                  onAddressEdited: (text) =>
                      _onAddressEdited(isPickup: true, text: text),
                ),
                dropoffChild: LocationAutocompleteField(
                  icon: dropoffSquare(),
                  hint: 'Drop-off — where to?',
                  controller: _dropoffCtrl,
                  resolving: _resolvingDropoff,
                  onTap: () => setState(() => _pickMode = MapPickMode.destination),
                  onLocation: _onDropoffLocation,
                  onAddressEdited: (text) =>
                      _onAddressEdited(isPickup: false, text: text),
                ),
              ),
              const SizedBox(height: 14),
              PackageTypeSelector(
                selected: _packageType,
                onSelected: (v) => setState(() => _itemCtrl.text = v),
              ),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: BytzErrorPanel(
                  title: 'Could not load trip',
                  message: _error!,
                  onRetry: _loadOrders,
                  light: true,
                ),
              ),
          ],
        ),
      ),
    );
  }

}
