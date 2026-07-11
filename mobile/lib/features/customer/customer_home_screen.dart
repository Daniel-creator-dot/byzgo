import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config_repository.dart';
import '../../core/delivery_pricing_config.dart';
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
import '../../models/ride_service.dart';
import '../orders/orders_repository.dart';
import '../riders/riders_repository.dart';
import '../../shared/widgets/location_autocomplete_field.dart';
import 'customer_delivery_ui.dart';
import 'customer_trip_tracking.dart';
import 'ride_service_picker.dart';

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
  DeliveryPricingConfig? _pricingConfig;
  Session? _watchedSession;
  String? _sessionUserId;
  String? _focusedTripId;
  String? _pendingRatingTripId;
  final Set<String> _dismissedTripIds = {};
  double? _quotedFee;
  double? _quoteDistanceKm;
  bool _surgeActive = false;
  double _promotionDiscount = 0;
  String? _promotionName;
  bool _quoteLoading = false;
  String? _quoteError;
  bool _scheduleLater = false;
  DateTime _scheduledAt = DateTime.now().add(const Duration(hours: 2));
  RideServiceType _rideService =
      RideServiceType.okada;
  int _passengerCount = 1;
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
  Timer? _orderStatusPoll;
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
    final pricing = context.read<DeliveryPricingConfig>();
    if (!identical(pricing, _pricingConfig)) {
      _pricingConfig?.removeListener(_onLivePricingUpdated);
      _pricingConfig = pricing..addListener(_onLivePricingUpdated);
      _pricePerKm = pricing.pricePerKm;
    }
    final session = context.read<Session>();
    if (!identical(session, _watchedSession)) {
      _watchedSession?.removeListener(_onSessionChanged);
      _watchedSession = session..addListener(_onSessionChanged);
    }
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final userId = _session.user?.id;
    if (!_session.isAuthenticated) {
      _sessionUserId = null;
      setState(() {
        _orders = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    // Wallet/profile patches notify Session too — only refetch on login or user switch.
    if (userId != _sessionUserId) {
      _sessionUserId = userId;
      unawaited(_loadOrders());
    }
  }

  bool _isAuthErrorMessage(String? message) {
    if (message == null || message.isEmpty) return false;
    final lower = message.toLowerCase();
    return lower.contains('sign in') ||
        lower.contains('session') ||
        lower.contains('unauthorized') ||
        lower.contains('401') ||
        lower.contains('403');
  }

  void _onLivePricingUpdated() {
    if (!mounted) return;
    setState(() {
      _pricePerKm = _pricingConfig?.pricePerKm ?? defaultDeliveryPricePerKm;
      _quotedFee = null;
      _quoteDistanceKm = null;
      _quoteError = null;
      _promotionDiscount = 0;
      _promotionName = null;
      _surgeActive = _pricingConfig?.surgeActive ?? false;
    });
    if (_hasRoutableCoords) {
      _beginQuoteRefresh();
    }
  }

  bool get _hasRoutableCoords =>
      _pickup != null &&
      _destination != null &&
      _pickup!.hasCoords &&
      _destination!.hasCoords;

  bool get _quoteReady => _quotedFee != null && _quotedFee! > 0;

  bool get _showQuoteCard => _hasRoutableCoords && (_quoteLoading || _quoteReady);

  VoidCallback? get _requestButtonHandler {
    if (_booking || _quoteLoading) return null;
    if (_hasRoutableCoords && !_quoteReady) return null;
    return _requestDelivery;
  }

  String _requestButtonLabel() {
    final service =
        rideServiceRequestLabel(widget.vendorMode ? RideServiceType.package : _rideService);
    final fee = _quotedFee;
    if (fee != null && fee > 0) {
      final price = formatCedis(fee);
      return _scheduleLater ? 'Schedule $service · $price' : '$service · $price';
    }
    if (_quoteLoading && _hasRoutableCoords) return 'Calculating…';
    return _scheduleLater ? 'Schedule $service' : service;
  }

  void _beginQuoteRefresh() {
    setState(() {
      _quotedFee = null;
      _quoteDistanceKm = null;
      _quoteError = null;
      _promotionDiscount = 0;
      _promotionName = null;
      _quoteLoading = true;
    });
    _scheduleDeliveryQuote();
  }

  double get _deliveryFee => _quotedFee ?? 0;

  double get _routeDistanceKm {
    if (_quoteDistanceKm != null && _quoteDistanceKm! > 0) return _quoteDistanceKm!;
    return 0;
  }

  String get _packageType => _itemCtrl.text.trim().isEmpty ? 'Package' : _itemCtrl.text.trim();

  bool _isRideTabTrip(Order o, String userId) {
    if (o.customerId != userId) return false;
    final type = o.orderType ?? '';
    return type == 'courier' ||
        type == 'food' ||
        customerOrderHasShopPickup(o) ||
        (o.pickup != null && o.pickup!.trim().isNotEmpty);
  }

  bool _isTerminalRideTrip(Order order) {
    if (order.status == 'cancelled') return true;
    if (order.status == 'delivered' && (order.rating ?? 0) >= 1) return true;
    return false;
  }

  bool _isRecentDelivery(Order o) {
    try {
      final created = DateTime.parse(o.createdAt).toUtc();
      return DateTime.now().toUtc().difference(created).inHours < 6;
    } catch (_) {
      return false;
    }
  }

  bool _rideTabTripVisible(Order o, String userId) {
    if (!_isRideTabTrip(o, userId)) return false;
    if (_dismissedTripIds.contains(o.id)) return false;
    if (o.status == 'cancelled') return false;
    if (o.status == 'delivered') {
      if ((o.rating ?? 0) >= 1) return false;
      return _pendingRatingTripId == o.id;
    }
    if (o.status == 'scheduled') return false;
    return true;
  }

  void _noteDeliveryCompleted(Order order) {
    if (order.status != 'delivered' || (order.rating ?? 0) >= 1) return;
    setState(() => _pendingRatingTripId = order.id);
  }

  void _restorePendingRatingTrip() {
    final userId = _session.user?.id;
    if (userId == null || _pendingRatingTripId != null) return;
    final pending = _newestRideTabOrder(
      _orders,
      include: (o) =>
          _isRideTabTrip(o, userId) &&
          o.status == 'delivered' &&
          (o.rating ?? 0) < 1 &&
          !_dismissedTripIds.contains(o.id) &&
          _isRecentDelivery(o),
    );
    if (pending != null) {
      _pendingRatingTripId = pending.id;
    }
  }

  Order? _newestRideTabOrder(
    Iterable<Order> source, {
    required bool Function(Order o) include,
  }) {
    Order? newest;
    for (final o in source) {
      if (!include(o)) continue;
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

  /// In-progress courier trip — stale trips do not block new bookings.
  Order? get _activeCourier {
    final userId = _session.user?.id;
    if (userId == null) return null;
    return _newestRideTabOrder(
      _orders,
      include: (o) =>
          _isRideTabTrip(o, userId) &&
          !_dismissedTripIds.contains(o.id) &&
          !['delivered', 'cancelled', 'scheduled'].contains(o.status) &&
          customerTripBlocksNewBooking(o),
    );
  }

  /// Shown on Ride tab: active trip or just-finished trip until the customer rates.
  Order? get _rideTabTrip {
    final userId = _session.user?.id;
    if (userId == null) return null;
    if (_focusedTripId != null) {
      for (final o in _orders) {
        if (o.id == _focusedTripId && _rideTabTripVisible(o, userId)) {
          return o;
        }
      }
    }
    final active = _activeCourier;
    if (active != null) return active;
    return _newestRideTabOrder(
      _orders,
      include: (o) => _rideTabTripVisible(o, userId) && o.status == 'delivered',
    );
  }

  /// After marketplace checkout — show trip on map and in lists.
  void noteOrder(Order order) => _replaceOrder(order);

  /// Open a specific trip from Activity (live, scheduled, or recent history).
  void focusOrder(Order order) {
    setState(() {
      _focusedTripId = order.id;
      _dismissedTripIds.remove(order.id);
      if (order.status == 'delivered' && (order.rating ?? 0) < 1) {
        _pendingRatingTripId = order.id;
      }
    });
    _replaceOrder(order);
    final trip = _rideTabTrip;
    if (trip != null) {
      unawaited(_resolveTrackingLabels(trip));
      _syncEtaPoll(trip);
      _syncRiderLocationPoll(trip);
      _syncOrderStatusPoll();
      _syncNearbyPoll();
    }
  }

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
      final pricing = context.read<DeliveryPricingConfig>();
      _pricePerKm = pricing.pricePerKm;
      _surgeActive = pricing.surgeActive;
    } catch (_) {
      try {
        _pricePerKm = await context.read<ConfigRepository>().fetchPricePerKm();
      } catch (_) {}
    }
    if (_session.isAuthenticated) {
      await _loadOrders();
    } else if (mounted) {
      setState(() => _loading = false);
    }
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
      _syncOrderStatusPoll();
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
    final hasRider = customerOrderHasActiveRider(order);
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

  /// Poll API while searching for a biker or waiting at drop-off if socket lags.
  void _syncOrderStatusPoll() {
    _orderStatusPoll?.cancel();
    final active = _activeCourier;
    if (active == null) {
      _orderStatusPoll = null;
      return;
    }
    final searching = customerIsSearchingBiker(active);
    if (!searching && active.status != 'arrived') {
      _orderStatusPoll = null;
      return;
    }
    unawaited(_pollOrderStatusOnce());
    _orderStatusPoll = Timer.periodic(
      Duration(seconds: searching ? 5 : 10),
      (_) => unawaited(_pollOrderStatusOnce()),
    );
  }

  Future<void> _pollOrderStatusOnce() async {
    final track = _activeCourier;
    if (track == null) return;
    final searching = customerIsSearchingBiker(track);
    if (!searching && track.status != 'arrived') return;
    try {
      final list = await _ordersRepo.fetchOrders();
      final updated = list.where((o) => o.id == track.id).firstOrNull;
      if (updated == null || !mounted) return;
      final hadRider = customerOrderHasActiveRider(track);
      final hasRiderNow = customerOrderHasActiveRider(updated);
      if (updated.status == track.status &&
          updated.riderId == track.riderId &&
          !searching) {
        return;
      }
      if (searching && !hasRiderNow) return;
      final prevStatus = track.status;
      _onOrderUpdated(updated);
      if (hasRiderNow && !hadRider) {
        if (customerOrderHasShopPickup(updated)) {
          _snack(
            'Rider found — heading to ${customerShopLabel(updated)} to collect your order',
            success: true,
          );
        } else {
          _snack('Biker found — they\'re on the way', success: true);
        }
      } else if (updated.status == 'delivered' && prevStatus != 'delivered') {
        _noteDeliveryCompleted(updated);
        _snack('Delivered — thanks for using BytzGO!', success: true);
      }
      _syncOrderStatusPoll();
      _syncEtaPoll(updated);
      _syncRiderLocationPoll(updated);
      _syncNearbyPoll();
    } catch (_) {}
  }

  void _onRouteChanged() {
    if (_hasRoutableCoords) {
      _beginQuoteRefresh();
    } else if (mounted) {
      setState(() {
        _quotedFee = null;
        _quoteDistanceKm = null;
        _quoteError = null;
        _quoteLoading = false;
      });
    }
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
        serviceType: widget.vendorMode ? RideServiceType.package : _rideService,
      );
      if (!mounted) return;
      setState(() {
        _quotedFee = q.deliveryFee;
        _quoteDistanceKm = q.distanceKm;
        _pricePerKm = q.pricePerKm;
        _surgeActive = q.surgeActive;
        _promotionDiscount = q.promotionDiscount;
        _promotionName = q.promotionName;
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
    _watchedSession?.removeListener(_onSessionChanged);
    _quoteDebounce?.cancel();
    _pricingConfig?.removeListener(_onLivePricingUpdated);
      _nearbyPoll?.cancel();
      _etaPoll?.cancel();
      _riderLocationPoll?.cancel();
      _orderStatusPoll?.cancel();
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

    socket.onOrderUpdated = (raw) {
      if (!mounted) return;
      final prev = _orders.where((o) => o.id == raw.id).firstOrNull;
      if (!_shouldAcceptOrderUpdate(raw.normalizedForCustomerTrip(), prev)) return;
      final order = _prepareIncomingOrder(raw);
      setState(() {
        final i = _orders.indexWhere((o) => o.id == order.id);
        if (i >= 0) {
          _orders[i] = order;
        } else {
          _orders = [order, ..._orders];
        }
        if (order.status == 'cancelled') {
          _clearLiveTrackingState();
        }
      });
      if (order.customerId == _session.user?.id) {
        if (order.status == 'cancelled' && prev?.status != 'cancelled') {
          _snack('Delivery request cancelled', success: true);
        } else if (order.status == 'delivered' && prev?.status != 'delivered') {
          _noteDeliveryCompleted(order);
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
        } else if (customerOrderHasActiveRider(order) && prev?.riderId == null) {
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
      if (order.status == 'cancelled') {
        _nearbyPoll?.cancel();
        _nearbyPoll = null;
        _etaPoll?.cancel();
        _etaPoll = null;
        _riderLocationPoll?.cancel();
        _riderLocationPoll = null;
        _orderStatusPoll?.cancel();
        _orderStatusPoll = null;
        if (prev?.status != 'cancelled') {
          _dismissRideTabTrip(order.id);
          _mapKey.currentState?.fitAllMarkers();
        }
      } else if (order.status == 'delivered' && prev?.status != 'delivered') {
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
      } else if (customerOrderHasActiveRider(order) && prev?.riderId == null) {
        if (customerOrderHasShopPickup(order)) {
          _snack(
            'Rider found — heading to ${customerShopLabel(order)} to collect your order',
            success: true,
          );
        } else {
          _snack('Biker found — they\'re on the way', success: true);
        }
      }
      if (order.status != 'cancelled') {
        _syncNearbyPoll();
        _syncEtaPoll(order);
        _syncRiderLocationPoll(order);
        _syncOrderStatusPoll();
        if (customerOrderHasActiveRider(order) &&
            prev?.riderId != order.riderId) {
          unawaited(_hydrateRiderPosition(order));
        }
        if (prev != null &&
            prev.status != order.status &&
            customerOrderHasActiveRider(order)) {
          _lastEtaFetch = null;
          _lastEtaOrigin = null;
          unawaited(_refreshEta(order));
        }
        if (_activeCourier?.id == order.id) {
          unawaited(_resolveTrackingLabels(order));
        }
      }
      final current =
          _orders.where((o) => o.id == order.id).firstOrNull ?? order;
      if (current.customerId == _session.user?.id &&
          _isTerminalRideTrip(current)) {
        _dismissRideTabTrip(current.id);
      }
    };
    socket.onWalletUpdated = (balance) {
      if (!mounted) return;
      _session.patchBalance(balance);
    };
    socket.onLocationUpdated = (riderId, lat, lng) {
      final active = _activeCourier;
      if (active == null || _dismissedTripIds.contains(active.id)) return;
      if (customerIsSearchingBiker(active)) {
        unawaited(_pollOrderStatusOnce());
        return;
      }
      if (active.riderId != riderId) return;
      if (!mounted) return;
      setState(() {
        _riderPosition = LocationPoint(
          address: 'Your biker',
          lat: lat,
          lng: lng,
        );
      });
      _mapKey.currentState?.fitAllMarkers();
      unawaited(_refreshEta(active));
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
    final hasRider = customerOrderHasActiveRider(order);
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

  bool _shouldAcceptOrderUpdate(Order order, Order? prev) {
    if (prev == null) return true;
    if (prev.status == 'cancelled' && order.status != 'cancelled') return false;
    if (_dismissedTripIds.contains(order.id) &&
        order.status != 'cancelled' &&
        !_isTerminalRideTrip(order)) {
      return false;
    }
    return true;
  }

  void _clearLiveTrackingState() {
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
    _trackingPickupLabel = null;
    _trackingDropoffLabel = null;
  }

  Order _prepareIncomingOrder(Order raw) {
    final prev = _orders.where((o) => o.id == raw.id).firstOrNull;
    final merged = prev == null ? raw.normalizedForCustomerTrip() : raw.mergeWithPrevious(prev);
    return merged.normalizedForCustomerTrip();
  }

  void _replaceOrder(Order raw) {
    final prev = _orders.where((o) => o.id == raw.id).firstOrNull;
    if (!_shouldAcceptOrderUpdate(raw.normalizedForCustomerTrip(), prev)) return;
    final order = _prepareIncomingOrder(raw);
    final cancelled = order.status == 'cancelled';
    setState(() {
      final i = _orders.indexWhere((o) => o.id == order.id);
      if (i >= 0) {
        _orders[i] = order;
      } else {
        _orders = [order, ..._orders];
      }
      if (cancelled) {
        _clearLiveTrackingState();
      }
    });
    if (cancelled) {
      _nearbyPoll?.cancel();
      _nearbyPoll = null;
      _etaPoll?.cancel();
      _etaPoll = null;
      _riderLocationPoll?.cancel();
      _riderLocationPoll = null;
      _orderStatusPoll?.cancel();
      _orderStatusPoll = null;
      _dismissRideTabTrip(order.id);
      if (prev?.status != 'cancelled') {
        _snack('Delivery request cancelled', success: true);
      }
      _mapKey.currentState?.fitAllMarkers();
      return;
    }
    _syncNearbyPoll();
    _syncEtaPoll(order);
    _syncRiderLocationPoll(order);
  }

  void _dismissRideTabTrip(String orderId) {
    if (!mounted) return;
    setState(() {
      _dismissedTripIds.add(orderId);
      if (_focusedTripId == orderId) _focusedTripId = null;
      if (_pendingRatingTripId == orderId) _pendingRatingTripId = null;
      _clearLiveTrackingState();
    });
    _nearbyPoll?.cancel();
    _nearbyPoll = null;
    _etaPoll?.cancel();
    _etaPoll = null;
    _riderLocationPoll?.cancel();
    _riderLocationPoll = null;
    _orderStatusPoll?.cancel();
    _orderStatusPoll = null;
    if (_sheetScrollCtrl.hasClients) {
      _sheetScrollCtrl.jumpTo(0);
    }
    _mapKey.currentState?.fitAllMarkers();
  }

  void _onOrderUpdated(Order order) {
    final prev = _orders.where((o) => o.id == order.id).firstOrNull;
    _replaceOrder(order);
    final current = _orders.where((o) => o.id == order.id).firstOrNull ?? order;
    if (current.status == 'delivered' && prev?.status != 'delivered') {
      _noteDeliveryCompleted(current);
    }
    if (_isTerminalRideTrip(current)) {
      _dismissRideTabTrip(current.id);
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
    if (_hasRoutableCoords) {
      _beginQuoteRefresh();
    } else {
      setState(() {
        _quotedFee = null;
        _quoteDistanceKm = null;
        _quoteLoading = false;
      });
    }
  }

  Future<void> _loadOrders() async {
    if (!mounted) return;
    if (!_session.isAuthenticated) {
      setState(() {
        _loading = false;
        _error = null;
        _orders = [];
      });
      return;
    }
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
        _restorePendingRatingTrip();
      });
      _syncNearbyPoll();
      final active = _activeCourier;
      if (active != null) {
        unawaited(_resolveTrackingLabels(active));
        _syncEtaPoll(active);
        _syncRiderLocationPoll(active);
        _syncOrderStatusPoll();
      }
    } catch (e) {
      if (!mounted) return;
      final msg = OrdersRepository.errorMessage(e);
      final offline = _isOfflineError(msg);
      setState(() {
        _loading = false;
        if (offline && _orders.isNotEmpty) {
          _error = null;
        } else {
          _error = msg;
        }
      });
    }
  }

  bool _isOfflineError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('cannot reach') ||
        lower.contains('connection') ||
        lower.contains('internet') ||
        lower.contains('network');
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
      _onRouteChanged();
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
    _onRouteChanged();
  }

  Future<void> _onDropoffLocation(LocationPoint point) async {
    if (!point.hasCoords) {
      setState(() {
        _destination = point;
        _dropoffCtrl.text = point.address;
        _pickMode = MapPickMode.destination;
      });
      _onRouteChanged();
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
    _onRouteChanged();
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
    _onRouteChanged();
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
      serviceType: widget.vendorMode ? RideServiceType.package : _rideService,
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
    if (!_session.isAuthenticated) {
      _snack('Sign in to request a delivery');
      context.push('/login');
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
      final serviceType =
          widget.vendorMode ? RideServiceType.package : _rideService;
      final itemDescription = _itemCtrl.text.trim().isEmpty
          ? 'Package'
          : _itemCtrl.text.trim();
      String? scheduledTime;
      if (_scheduleLater) {
        scheduledTime = _scheduledAt.toUtc().toIso8601String();
      }

      try {
        final order = await _ordersRepo.createCourierOrder(
          pickup: pickup,
          destination: dest,
          deliveryFee: fee,
          region: _session.user?.region,
          itemDescription: itemDescription,
          scheduledTime: scheduledTime,
          serviceType: serviceType,
          passengerCount: _passengerCount,
        );
        if (!mounted) return;
        setState(() {
          _orders = [order, ..._orders];
        });
        _syncNearbyPoll();
        final bookedLabel = serviceType.isPassengerRide
            ? '${serviceType.label} requested — finding a driver'
            : (order.status == 'scheduled'
                ? 'Delivery scheduled — we will find a rider at the chosen time'
                : 'Bike requested — waiting for a rider');
        _snack(
          order.status == 'scheduled' && !serviceType.isPassengerRide
              ? 'Delivery scheduled — we will find a rider at the chosen time'
              : bookedLabel,
          success: true,
        );
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
              scheduledTime: scheduledTime,
              serviceType: serviceType,
              passengerCount: _passengerCount,
            );
            if (!mounted) return;
            setState(() {
              _quotedFee = retryFee;
              _orders = [order, ..._orders];
            });
            _syncNearbyPoll();
            _snack(
              serviceType.isPassengerRide
                  ? '${serviceType.label} requested — finding a driver'
                  : (order.status == 'scheduled'
                      ? 'Delivery scheduled — we will find a rider at the chosen time'
                      : 'Bike requested — waiting for a rider'),
              success: true,
            );
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
    final Order? trip = _rideTabTrip;
    final tracking = trip != null;
    final tripComplete = trip?.status == 'delivered';
    final awaitingRating =
        tripComplete && trip != null && (trip.rating ?? 0) < 1;
    final activeTracking =
        tracking && !tripComplete && trip?.status != 'cancelled';
    final sheetModeKey = tracking
        ? (awaitingRating ? 'rate-${trip.id}' : 'track-${trip.id}')
        : 'book';
    final fee = _deliveryFee;
    final searching = trip != null &&
        !tripComplete &&
        !customerOrderHasActiveRider(trip) &&
        customerIsSearchingBiker(trip);
    final hasRider =
        trip != null && !tripComplete && customerOrderHasActiveRider(trip);
    final mapPickup = tracking ? _mapPickupForTracking(trip) : _pickup;
    final mapDest = tracking ? _mapDestinationForTracking(trip) : _destination;
    final navTarget =
        trip != null ? customerRiderNavTarget(trip) : null;
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
      floatingMapChild: activeTracking
          ? LiveTripMapHud(
              order: trip,
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
        key: ValueKey('ride-sheet-$sheetModeKey'),
        scrollController: _sheetScrollCtrl,
        collapsible: activeTracking,
        collapsedHeight: 234,
        initiallyExpanded: trip != null &&
            (trip.status == 'arrived' || awaitingRating),
        maxHeightFraction: tracking
            ? (awaitingRating
                ? (widget.embedded ? 0.52 : 0.56)
                : activeTracking
                    ? (widget.embedded ? 0.72 : 0.8)
                    : customerTrackingSheetFraction(
                        trip,
                        embedded: widget.embedded,
                      ))
            : (widget.embedded ? (_showQuoteCard ? 0.64 : 0.58) : (_showQuoteCard ? 0.78 : 0.72)),
        bottomInset: widget.embedded ? 12 : 0,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        footerPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        scrollBottomPadding: !tracking && _showQuoteCard ? 12 : 0,
        footer: tracking
            ? null
            : Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RideAnimatedReveal(
              visible: _showQuoteCard,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DeliveryQuoteCard(
                  key: ValueKey(
                    'fee-${_quotedFee ?? 0}-$_surgeActive-$_promotionDiscount-$_quoteLoading',
                  ),
                  fee: _deliveryFee,
                  distanceKm: _routeDistanceKm,
                  surgeActive: _surgeActive,
                  loading: _quoteLoading,
                  promotionDiscount: _promotionDiscount,
                  promotionName: _promotionName,
                ),
              ),
            ),
            RidePrimaryButton(
              label: _requestButtonLabel(),
              icon: (widget.vendorMode ? RideServiceType.package : _rideService).icon,
              loading: _booking || (_quoteLoading && _hasRoutableCoords),
              onPressed: _requestButtonHandler,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!tracking && widget.embedded) ...[
              DeliveryBookingHeader(
                firstName: _session.user != null
                    ? userFirstName(_session.user!)
                    : 'there',
                balance: _session.user?.balance ?? 0,
                selectedService: widget.vendorMode ? RideServiceType.package : _rideService,
                vendorMode: widget.vendorMode,
                onShops: widget.vendorMode ? null : widget.onOpenShops,
                onWallet: widget.onOpenWallet,
                onTrips: widget.onOpenActivity,
                onProfile: widget.onOpenProfile,
              ),
              const SizedBox(height: 14),
            ],
            if (tracking && awaitingRating) ...[
              RateDriverCard(
                order: trip,
                onOrderUpdated: _onOrderUpdated,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _dismissRideTabTrip(trip.id),
                child: const Text('Continue booking'),
              ),
            ] else if (tracking) ...[
              CustomerDeliveryTracker(
                order: trip,
                onOrderUpdated: _onOrderUpdated,
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    widget.vendorMode ? 'Plan your dispatch' : 'Book a ride or send a package',
                    style: BytzGoTheme.sheetTitle(20),
                  ),
                ),
                Text(
                  widget.vendorMode
                      ? 'Pin pickup and drop-off, then request a bike courier.'
                      : 'Package courier · Okada rides · Keke (Pragia) for groups',
                  style: BytzGoTheme.sheetBody(13),
                ),
                const SizedBox(height: 14),
              ] else ...[
                Text(
                  widget.vendorMode ? 'Plan your delivery' : 'Where are you going?',
                  style: BytzGoTheme.sheetTitle(18),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.vendorMode
                      ? 'Search and pick a suggestion, or tap the map to pin pickup & drop-off'
                      : _rideService.subtitle,
                  style: BytzGoTheme.sheetBody(13),
                ),
              ],
              if (!widget.vendorMode) ...[
                const SizedBox(height: 12),
                RideServicePicker(
                  selected: _rideService,
                  onSelected: (type) {
                    setState(() {
                      _rideService = type;
                      if (type == RideServiceType.okada && _passengerCount > 2) {
                        _passengerCount = 2;
                      }
                      if (type == RideServiceType.keke && _passengerCount > 4) {
                        _passengerCount = 4;
                      }
                    });
                    if (_hasRoutableCoords) {
                      _beginQuoteRefresh();
                    }
                  },
                ),
                if (_rideService.isPassengerRide) ...[
                  const SizedBox(height: 10),
                  PassengerCountStepper(
                    count: _passengerCount,
                    max: _rideService.maxPassengers,
                    serviceLabel: _rideService == RideServiceType.keke
                        ? 'Pragia passengers'
                        : 'Okada passengers',
                    onChanged: (n) => setState(() => _passengerCount = n),
                  ),
                ],
              ],
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
              if (widget.vendorMode ||
                  _rideService == RideServiceType.package) ...[
                PackageTypeSelector(
                  selected: _packageType,
                  onSelected: (v) => setState(() => _itemCtrl.text = v),
                ),
                const SizedBox(height: 12),
              ],
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Deliver now')),
                  ButtonSegment(value: true, label: Text('Schedule')),
                ],
                selected: {_scheduleLater},
                onSelectionChanged: (s) => setState(() => _scheduleLater = s.first),
              ),
              if (_scheduleLater) ...[
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule, color: BytzGoTheme.brandBlue),
                  title: Text(
                    '${_scheduledAt.day}/${_scheduledAt.month}/${_scheduledAt.year} '
                    '${_scheduledAt.hour.toString().padLeft(2, '0')}:'
                    '${_scheduledAt.minute.toString().padLeft(2, '0')}',
                    style: BytzGoTheme.sheetBody(14),
                  ),
                  subtitle: const Text('Tap to change date & time'),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 14)),
                      initialDate: _scheduledAt,
                    );
                    if (date == null || !mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
                    );
                    if (time == null || !mounted) return;
                    setState(() {
                      _scheduledAt = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  },
                ),
              ],
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
            if (_error != null && !tracking)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: BytzErrorPanel(
                  title: _isAuthErrorMessage(_error)
                      ? 'Sign in required'
                      : 'Could not reach server',
                  message: _error!,
                  onRetry: _isAuthErrorMessage(_error)
                      ? () => context.push('/login')
                      : _loadOrders,
                  retryLabel:
                      _isAuthErrorMessage(_error) ? 'Sign in' : 'Try again',
                  light: true,
                ),
              ),
          ],
        ),
      ),
    );
  }

}
