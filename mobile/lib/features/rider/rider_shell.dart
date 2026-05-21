import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/location_service.dart';
import '../../core/push_notification_service.dart';
import '../../core/session.dart';
import '../../core/socket_service.dart';
import '../../features/auth/auth_repository.dart';
import '../../features/orders/orders_repository.dart';
import '../../features/wallet/wallet_repository.dart';
import '../../models/auth_user.dart';
import '../../models/location_point.dart';
import '../../models/order.dart';
import '../../models/vendor.dart';
import '../../shared/format.dart';
import '../../shared/ghana_regions.dart';
import '../../shared/rider_trip.dart';
import '../../shared/trip_chat_sheet.dart';
import '../../shared/trip_contact.dart';
import '../../shared/theme.dart';
import '../../models/rider_map_offer.dart';
import '../../shared/widgets/biker_search_radar.dart';
import '../../shared/widgets/delete_account_button.dart';
import '../../shared/widgets/profile_avatar_upload.dart';
import '../../shared/widgets/legal_links.dart';
import '../../shared/widgets/bytz_scaffold.dart';
import '../../shared/widgets/ride_ui.dart';
import 'delivery_pin_dialog.dart';
import 'incoming_ride_alert.dart';
import 'incoming_ride_overlay.dart';
import 'rider_drive_hud.dart';
import 'rider_drive_map_layer.dart';
import 'rider_verification_section.dart';

enum _RiderTab { drive, trips, wallet, profile }

enum _DriveSheet { requests, active }

/// Native Flutter rider / driver console (not a WebView).
class RiderShell extends StatefulWidget {
  const RiderShell({super.key});

  @override
  State<RiderShell> createState() => _RiderShellState();
}

class _RiderShellState extends State<RiderShell> with WidgetsBindingObserver {
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  _RiderTab _tab = _RiderTab.drive;
  _DriveSheet _driveSheet = _DriveSheet.requests;

  List<Order> _orders = [];
  List<Vendor> _vendors = [];
  Order? _incoming;
  final Set<String> _alertedOfferIds = {};
  String? _focusedOrderId;
  String? _previewOrderId;
  bool _isOnline = false;
  bool _driveListExpanded = false;
  final _driveMapKey = GlobalKey<RiderDriveMapLayerState>();
  bool _statusLoading = false;
  bool _accepting = false;
  bool _refreshing = false;
  int _offerTick = 0;

  final _myPositionNotifier = ValueNotifier<LocationPoint?>(null);
  StreamSubscription<Position>? _posSub;
  Timer? _pollTimer;
  Timer? _offerTimer;
  DateTime? _lastGpsUiUpdate;

  final _withdrawAmount = TextEditingController();
  final _withdrawPhone = TextEditingController();
  final _withdrawBank = TextEditingController();
  final _withdrawAccName = TextEditingController();
  final _withdrawAccNum = TextEditingController();
  final _profilePhone = TextEditingController();
  String _withdrawMethod = 'momo';
  String _withdrawNetwork = 'mtn';
  String? _profileRegion;
  bool _withdrawing = false;
  bool _profileSaving = false;
  String? _walletMsg;
  bool _walletOk = false;
  String? _profileMsg;

  SocketService get _socket => context.read<SocketService>();
  Session get _session => context.read<Session>();
  AuthRepository get _auth => context.read<AuthRepository>();
  OrdersRepository get _ordersRepo => context.read<OrdersRepository>();
  WalletRepository get _wallet => context.read<WalletRepository>();
  LocationService get _location => context.read<LocationService>();

  AuthUser get _user => _session.user!;
  bool get _pendingApproval =>
      _user.status == 'pending' || _user.status == 'rejected';

  List<Order> get _availableOrders {
    _offerTick;
    return _orders.where(isOfferableOrder).toList();
  }

  List<Order> get _activeOrders =>
      _orders.where((o) => o.riderId == _user.id && o.status != 'delivered').toList();

  List<Order> get _completedTrips =>
      _orders.where((o) => o.riderId == _user.id && o.status == 'delivered').toList();

  Order? get _primaryActive {
    if (_focusedOrderId != null) {
      for (final o in _activeOrders) {
        if (o.id == _focusedOrderId) return o;
      }
    }
    return _activeOrders.isNotEmpty ? _activeOrders.first : null;
  }

  int get _tripsToday {
    final now = DateTime.now();
    return _completedTrips.where((o) {
      try {
        final d = DateTime.parse(o.createdAt);
        return d.year == now.year && d.month == now.month && d.day == now.day;
      } catch (_) {
        return false;
      }
    }).length;
  }

  double get _earningsToday {
    final now = DateTime.now();
    return _completedTrips.where((o) {
      try {
        final d = DateTime.parse(o.createdAt);
        return d.year == now.year && d.month == now.month && d.day == now.day;
      } catch (_) {
        return false;
      }
    }).fold<double>(0, (sum, o) => sum + (o.deliveryFee ?? o.total));
  }

  double? get _avgRating {
    final rated = _completedTrips.where((o) => o.rating != null && o.rating! > 0);
    if (rated.isEmpty) return null;
    return rated.map((o) => o.rating!).reduce((a, b) => a + b) / rated.length;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PushNotificationService.instance.onIncomingRidePush = (_) {
      if (_isOnline && mounted) _refreshAll(silent: true);
    };
    _isOnline = _user.isOnline == true;
    _profilePhone.text = _user.phone ?? '';
    _profileRegion = _user.region;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _wireSocket();
      _refreshAll();
      _startLocationStream();
      if (_isOnline) {
        _startPolling();
        unawaited(PushNotificationService.instance.ensureRegistered(
          api: context.read<ApiClient>(),
          session: context.read<Session>(),
        ));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    final order = _incoming;
    if (order == null) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(
        PushNotificationService.instance.cancelIncomingRide(order.id),
      );
      unawaited(IncomingRideAlert.raise(order, useNotificationSound: false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PushNotificationService.instance.onIncomingRidePush = null;
    _posSub?.cancel();
    _pollTimer?.cancel();
    _offerTimer?.cancel();
    _myPositionNotifier.dispose();
    _withdrawAmount.dispose();
    _withdrawPhone.dispose();
    _withdrawBank.dispose();
    _withdrawAccName.dispose();
    _withdrawAccNum.dispose();
    _profilePhone.dispose();
    unawaited(IncomingRideAlert.dismiss());
    _socket.clearHandlers();
    super.dispose();
  }

  void _presentIncoming(Order order) {
    if (!mounted || !_isOnline || !isOfferableOrder(order)) return;
    setState(() {
      _incoming = order;
      _tab = _RiderTab.drive;
      _driveSheet = _DriveSheet.requests;
    });
    final bg = _lifecycle != AppLifecycleState.resumed;
    unawaited(IncomingRideAlert.raise(order, useNotificationSound: bg));
  }

  void _trackOffers(List<Order> orders) {
    if (!_isOnline || _incoming != null) return;
    final offers = orders.where(isOfferableOrder).toList();
    for (final o in offers) {
      if (_alertedOfferIds.contains(o.id)) continue;
      _alertedOfferIds.add(o.id);
      _presentIncoming(o);
      return;
    }
  }

  void _wireSocket() {
    _socket.clearHandlers();
    _socket.onStatusUpdated = ({required status, isOnline, reason}) {
      if (!mounted) return;
      final u = _session.user;
      if (u == null) return;
      _session.patchUser(u.copyWith(
        status: status.isNotEmpty ? status : u.status,
        isOnline: isOnline ?? u.isOnline,
      ));
      setState(() {
        _isOnline = _session.user!.isOnline == true;
        if (!_isOnline) {
          _incoming = null;
          _alertedOfferIds.clear();
          _stopPolling();
          unawaited(IncomingRideAlert.dismiss());
        }
      });
      if (reason != null && reason.isNotEmpty && status == 'rejected') {
        _snack(reason);
      }
    };
    _socket.onRideIncoming = (order) {
      if (!mounted || !_isOnline || !isOfferableOrder(order)) return;
      _alertedOfferIds.add(order.id);
      _presentIncoming(order);
    };
    _socket.onRideTaken = (orderId) {
      if (!mounted) return;
      final wasIncoming = _incoming?.id == orderId;
      if (wasIncoming) unawaited(IncomingRideAlert.dismiss(orderId: orderId));
      setState(() {
        if (wasIncoming) _incoming = null;
        _orders = _orders
            .where((o) => o.id != orderId || o.riderId == _user.id)
            .toList();
      });
      if (wasIncoming) _snack('Another rider took this job');
    };
    _socket.onOrderUpdated = (order) {
      if (!mounted) return;
      setState(() {
        _orders = [
          for (final o in _orders)
            if (o.id != order.id) o,
          order,
        ];
        if (_incoming?.id == order.id && !isOfferableOrder(order)) {
          unawaited(IncomingRideAlert.dismiss(orderId: order.id));
          _incoming = null;
        }
        if (order.riderId == _user.id && order.status != 'delivered') {
          _focusedOrderId = order.id;
          _driveSheet = _DriveSheet.active;
          _tab = _RiderTab.drive;
        }
      });
    };
    _socket.onWalletUpdated = (balance) {
      if (!mounted) return;
      _session.patchBalance(balance);
    };
  }

  Future<void> _refreshAll({bool silent = false}) async {
    if (!silent) setState(() => _refreshing = true);
    try {
      final orders = await _ordersRepo.fetchOrders();
      final vendors = await _ordersRepo.fetchVendors(region: _user.region);
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _vendors = vendors;
      });
      _driveMapKey.currentState?.fitAllMarkers();
      _trackOffers(orders);
      _syncOfferTimer();
    } catch (e) {
      if (!silent) _snack(OrdersRepository.errorMessage(e));
    } finally {
      if (mounted && !silent) setState(() => _refreshing = false);
    }
  }

  void _syncOfferTimer() {
    _offerTimer?.cancel();
    if (_tab != _RiderTab.drive) return;
    final hasExpiring = _orders.any(
      (o) => o.status == 'ready' && o.riderId == null && o.expiresAt != null,
    );
    if (!hasExpiring) return;
    _offerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _tab != _RiderTab.drive) return;
      setState(() => _offerTick++);
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isOnline && mounted) _refreshAll(silent: true);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _startLocationStream() async {
    await _posSub?.cancel();
    final ok = await _location.ensurePermission();
    if (!ok) return;
    final userId = _user.id;
    _posSub = _location.positionStream().listen((pos) {
      final point = LocationPoint(
        address: 'You',
        lat: pos.latitude,
        lng: pos.longitude,
      );
      if (_isOnline) {
        _socket.emitLocationUpdate(
          userId: userId,
          lat: pos.latitude,
          lng: pos.longitude,
        );
      }
      final now = DateTime.now();
      final throttle = _tab == _RiderTab.drive
          ? const Duration(seconds: 2)
          : const Duration(seconds: 8);
      if (_lastGpsUiUpdate == null ||
          now.difference(_lastGpsUiUpdate!) >= throttle) {
        _lastGpsUiUpdate = now;
        _myPositionNotifier.value = point;
      }
    });
  }

  Future<void> _setOnline(bool online) async {
    if (_pendingApproval && online) {
      _snack(_user.status == 'rejected'
          ? 'Application rejected — update documents in Account and resubmit.'
          : 'Account pending approval — upload documents in Account first.');
      return;
    }
    setState(() => _statusLoading = true);
    try {
      final result = await _auth.updateStatus(online ? 'active' : 'offline');
      await _session.applyAuthResult(token: result.token, user: result.user);
      if (!mounted) return;
      setState(() {
        _isOnline = result.user.isOnline == true;
        if (!_isOnline) {
          _incoming = null;
          _alertedOfferIds.clear();
          unawaited(IncomingRideAlert.dismiss());
        }
      });
      if (online) {
        _alertedOfferIds.clear();
        await _socket.connect(userId: _user.id);
        await PushNotificationService.instance.ensureRegistered(
          api: context.read<ApiClient>(),
          session: context.read<Session>(),
        );
        _startPolling();
        await _refreshAll();
        _snack('You\'re online — waiting for jobs', success: true);
      } else {
        _stopPolling();
        _snack('You\'re offline');
      }
    } catch (e) {
      _snack(AuthRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _statusLoading = false);
    }
  }

  Future<void> _acceptOrder(Order order, {bool navigate = true}) async {
    setState(() => _accepting = true);
    try {
      final updated = await _ordersRepo.acceptOrder(
        orderId: order.id,
        riderId: _user.id,
        currentStatus: order.status,
      );
      if (!mounted) return;
      unawaited(IncomingRideAlert.dismiss(orderId: order.id));
      setState(() {
        _incoming = null;
        _orders = [
          for (final o in _orders)
            if (o.id != updated.id) o,
          updated,
        ];
        _focusedOrderId = updated.id;
        _driveSheet = _DriveSheet.active;
        _tab = _RiderTab.drive;
      });
      _snack('Ride accepted', success: true);
      if (navigate) await _openNavigation(updated);
    } catch (e) {
      _snack(OrdersRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _declineRide() async {
    final order = _incoming;
    if (order == null) return;
    unawaited(IncomingRideAlert.dismiss(orderId: order.id));
    try {
      await _ordersRepo.declineOrder(order.id);
      if (!mounted) return;
      setState(() => _incoming = null);
    } catch (e) {
      _snack(OrdersRepository.errorMessage(e));
    }
  }

  Future<void> _markPickedUp(Order order) async {
    try {
      final updated = await _ordersRepo.updateOrderStatus(
        orderId: order.id,
        status: 'picked_up',
      );
      if (!mounted) return;
      _mergeOrder(updated);
      _snack('Marked picked up', success: true);
      await _openNavigation(updated);
    } catch (e) {
      _snack(OrdersRepository.errorMessage(e));
    }
  }

  Future<void> _markArrived(Order order) async {
    try {
      final updated = await _ordersRepo.markArrived(order.id);
      if (!mounted) return;
      _mergeOrder(updated);
      _snack('Marked arrived — ask customer for PIN', success: true);
    } catch (e) {
      _snack(OrdersRepository.errorMessage(e));
    }
  }

  void _mergeOrder(Order order) {
    setState(() {
      _orders = [
        for (final o in _orders)
          if (o.id != order.id) o,
        order,
      ];
      _focusedOrderId = order.id;
    });
  }

  Future<void> _openNavigation(Order order) async {
    final target = navigationTarget(order, _vendors);
    if (target == null) {
      _snack('No navigation target for this trip');
      return;
    }
    final ok = await openTurnByTurnNavigation(
      target,
      origin: _myPositionNotifier.value,
    );
    if (!ok) _snack('Could not open maps');
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

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
        builder: (ctx) => Theme(
        data: BytzGoTheme.sheetTheme(),
        child: AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
      ),
    );
    if (ok != true) return;
    await _posSub?.cancel();
    _stopPolling();
    await _session.clear();
    if (mounted) context.go('/login');
  }

  Vendor? _vendorFor(Order order) {
    for (final v in _vendors) {
      if (v.id == order.vendorId) return v;
    }
    return null;
  }

  LocationPoint? _mapPickup() {
    final active = _primaryActive;
    if (active != null) {
      final stop = pickupCoordsForOrder(active, _vendors);
      if (stop != null && hasValidCoords(stop.lat, stop.lng)) {
        return LocationPoint(address: stop.label, lat: stop.lat, lng: stop.lng);
      }
    }
    return _incomingPickupPoint();
  }

  LocationPoint? _mapDestination() {
    final active = _primaryActive;
    if (active != null) {
      final stop = dropoffCoords(active);
      if (stop != null && hasValidCoords(stop.lat, stop.lng)) {
        return LocationPoint(address: stop.label, lat: stop.lat, lng: stop.lng);
      }
    }
    return _incomingDestinationPoint();
  }

  LocationPoint? _incomingPickupPoint() {
    final o = _incoming;
    if (o == null) return null;
    if (o.pickupLat != null && o.pickupLng != null) {
      return LocationPoint(
        address: o.pickup ?? 'Pickup',
        lat: o.pickupLat!,
        lng: o.pickupLng!,
      );
    }
    return null;
  }

  LocationPoint? _incomingDestinationPoint() {
    final o = _incoming;
    if (o == null) return null;
    if (o.lat != null && o.lng != null) {
      return LocationPoint(address: o.address, lat: o.lat!, lng: o.lng!);
    }
    return null;
  }

  Widget _buildCurrentTab(AuthUser user) {
    switch (_tab) {
      case _RiderTab.drive:
        return _buildDriveTab();
      case _RiderTab.trips:
        return _buildTripsTab();
      case _RiderTab.wallet:
        return _buildWalletTab(user);
      case _RiderTab.profile:
        return _buildProfileTab(user);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select<Session, AuthUser?>((s) => s.user)!;

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                _buildHeader(user),
                Expanded(child: _buildCurrentTab(user)),
                _buildBottomNav(),
              ],
            ),
            if (_incoming != null)
              IncomingRideOverlay(
                order: _incoming!,
                vendors: _vendors,
                accepting: _accepting,
                onAccept: () => _acceptOrder(_incoming!),
                onDecline: _declineRide,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AuthUser user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: BytzGoTheme.accent,
                child: Text(
                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RIDER',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withValues(alpha: 0.45),
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              if (_statusLoading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                OnlineToggle(isOnline: _isOnline, onChanged: _setOnline),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _confirmLogout,
                icon: Icon(Icons.logout, color: Colors.white.withValues(alpha: 0.7)),
              ),
            ],
          ),
          if (_pendingApproval)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BytzGoTheme.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: BytzGoTheme.warning.withValues(alpha: 0.35)),
              ),
              child: Text(
                _user.status == 'rejected'
                    ? 'Application rejected — update documents in Account and resubmit.'
                    : 'Pending admin approval — upload documents in Account, then wait for review.',
                style: const TextStyle(
                  color: BytzGoTheme.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              _headerStat(
                'Balance',
                formatCedis(context.select<Session, double>((s) => s.user?.balance ?? 0)),
              ),
              const SizedBox(width: 8),
              _headerStat('Active', '${_activeOrders.length}'),
              const SizedBox(width: 8),
              _headerStat('Trips today', '$_tripsToday'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.4),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: label == 'Balance' ? 16 : 18,
                color: label == 'Balance' ? BytzGoTheme.accent : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Order? get _previewOrder {
    final id = _previewOrderId;
    if (id == null) return null;
    for (final o in _availableOrders) {
      if (o.id == id) return o;
    }
    return null;
  }

  double get _driveSheetFraction {
    if (!_isOnline) return 0.36;
    if (_primaryActive != null || _incoming != null) return 0.40;
    if (_availableOrders.isEmpty) return _driveListExpanded ? 0.32 : 0.24;
    return _driveListExpanded ? 0.42 : 0.30;
  }

  Widget _buildDriveTab() {
    final showRoute = (_incoming != null || _primaryActive != null) &&
        (_mapPickup() != null || _mapDestination() != null);

    return Stack(
      fit: StackFit.expand,
      children: [
        RiderDriveMapLayer(
          key: _driveMapKey,
          riderPosition: _myPositionNotifier,
          isOnline: _isOnline,
          availableOrders: _availableOrders,
          vendors: _vendors,
          activeOrder: _primaryActive,
          incomingOrder: _incoming,
          previewOrderId: _previewOrderId,
          showRoute: showRoute,
        ),
        if (!_isOnline)
          Container(
            color: const Color(0xFF020617).withValues(alpha: 0.75),
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.two_wheeler, size: 56, color: Color(0xFF475569)),
                  const SizedBox(height: 12),
                  const Text(
                    'You\'re offline',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Go online to see the map and receive jobs.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                  ),
                  const SizedBox(height: 20),
                  RidePrimaryButton(
                    label: 'Go online',
                    icon: Icons.power_settings_new,
                    onPressed: _pendingApproval ? null : () => _setOnline(true),
                  ),
                ],
              ),
            ),
          ),
        if (_isOnline)
          RiderDriveHud(
            isOnline: _isOnline,
            offerCount: _availableOrders.length,
            mappedOfferCount: riderMapOffersFromOrders(
              _availableOrders,
              _vendors,
            ).length,
            previewOrder: _previewOrder ?? _incoming,
            earningsToday: _earningsToday,
            tripsToday: _tripsToday,
            onRecenter: () => _driveMapKey.currentState?.fitAllMarkers(),
          ),
        if (_primaryActive != null && _incoming == null)
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              bottom: false,
              child: _activeTripHud(_primaryActive!),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _driveBottomSheet(),
        ),
      ],
    );
  }

  Widget _activeTripHud(Order order) {
    final nav = navigationTarget(order, _vendors);
    final phase = tripPhase(order);
    final label = phase == TripPhase.toPickup ? 'Head to pickup' : 'Head to drop-off';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: const Color(0xFF0F172A).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: BytzGoTheme.accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                        if (nav != null)
                          Text(
                            nav.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: nav == null ? null : () => _openNavigation(order),
                    icon: const Icon(Icons.navigation, size: 16),
                    label: const Text('Navigate'),
                    style: FilledButton.styleFrom(
                      backgroundColor: BytzGoTheme.accent,
                      foregroundColor: const Color(0xFF020617),
                    ),
                  ),
                ],
              ),
              if (tripAllowsContact(order)) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (order.customerPhone != null) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => launchPhoneCall(order.customerPhone),
                          icon: const Icon(Icons.phone, size: 16),
                          label: const Text('Call'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => launchSms(order.customerPhone),
                          icon: const Icon(Icons.sms_outlined, size: 16),
                          label: const Text('SMS'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => showTripChatSheet(
                          context,
                          order: order,
                          title: 'Chat with ${order.customerName.isNotEmpty ? order.customerName : 'customer'}',
                        ),
                        icon: const Icon(Icons.chat_bubble_outline, size: 16),
                        label: const Text('Chat'),
                        style: FilledButton.styleFrom(
                          backgroundColor: BytzGoTheme.accent,
                          foregroundColor: const Color(0xFF020617),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _driveBottomSheet() {
    return RideSheet(
      maxHeightFraction: _driveSheetFraction,
      minSheetHeight: 128,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _sheetTabBtn('Requests', _DriveSheet.requests, _availableOrders.length),
              const SizedBox(width: 8),
              _sheetTabBtn('Active', _DriveSheet.active, _activeOrders.length),
              const Spacer(),
              if (_availableOrders.isNotEmpty)
                TextButton(
                  onPressed: () =>
                      setState(() => _driveListExpanded = !_driveListExpanded),
                  child: Text(
                    _driveListExpanded ? 'Map focus' : 'List',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (_refreshing)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  onPressed: _refreshAll,
                  icon: const Icon(Icons.refresh, size: 20),
                  color: BytzGoTheme.sheetMuted,
                ),
            ],
          ),
          if (_isOnline && _driveSheet == _DriveSheet.requests) ...[
            const SizedBox(height: 6),
            _mapOfferChips(),
          ],
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: _driveListExpanded
                  ? MediaQuery.sizeOf(context).height * 0.28
                  : MediaQuery.sizeOf(context).height * 0.18,
            ),
            child: SingleChildScrollView(
              child: _driveSheet == _DriveSheet.requests
                  ? _requestsList()
                  : _activeList(),
            ),
          ),
          if (!_isOnline) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _statCard('Earnings', formatCedis(_earningsToday)),
                const SizedBox(width: 10),
                _statCard('Trips', '$_tripsToday'),
                const SizedBox(width: 10),
                _statCard(
                  'Rating',
                  _avgRating != null ? _avgRating!.toStringAsFixed(1) : '—',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sheetTabBtn(String label, _DriveSheet tab, int count) {
    final selected = _driveSheet == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _driveSheet = tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? BytzGoTheme.sheetDivider.withValues(alpha: 0.7)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            count > 0 ? '$label ($count)' : label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: selected ? BytzGoTheme.sheetText : BytzGoTheme.sheetMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _mapOfferChips() {
    final offers = _availableOrders;
    if (offers.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: offers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final o = offers[i];
          final selected = _previewOrderId == o.id;
          final short =
              '#${o.id.length > 4 ? o.id.substring(o.id.length - 4) : o.id}';
          return FilterChip(
            selected: selected,
            label: Text('$short · ${formatCedis(o.total)}'),
            avatar: Icon(
              o.isCourier ? Icons.local_shipping : Icons.store,
              size: 16,
              color: selected ? BytzGoTheme.accentDark : BytzGoTheme.sheetMuted,
            ),
            onSelected: (_) {
              setState(() {
                _previewOrderId = selected ? null : o.id;
              });
              _driveMapKey.currentState?.fitAllMarkers();
            },
            selectedColor: BytzGoTheme.accent.withValues(alpha: 0.35),
            checkmarkColor: BytzGoTheme.accentDark,
          );
        },
      ),
    );
  }

  Widget _requestsList() {
    if (!_isOnline) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Go online to receive requests',
          style: BytzGoTheme.sheetBody(),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_availableOrders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const BikerSearchRadar(size: 32, color: BytzGoTheme.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Radar scanning', style: BytzGoTheme.sheetTitle(14)),
                  Text(
                    'Map stays visible — customer pickups appear as green & blue pins',
                    style: BytzGoTheme.sheetBody(12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: _availableOrders.map(_requestCard).toList(),
    );
  }

  Widget _requestCard(Order order) {
    final vendor = _vendorFor(order);
    final secs = offerSecondsRemaining(order);
    final selected = _previewOrderId == order.id;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _previewOrderId = selected ? null : order.id;
          });
          _driveMapKey.currentState?.fitAllMarkers();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected
            ? BytzGoTheme.accent.withValues(alpha: 0.12)
            : BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: selected
            ? Border.all(color: BytzGoTheme.accent.withValues(alpha: 0.55), width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('#${order.id.length > 4 ? order.id.substring(order.id.length - 4) : order.id}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: BytzGoTheme.sheetText,
                  )),
              if (order.isCourier) ...[
                const SizedBox(width: 8),
                _chip('Courier', const Color(0xFF38BDF8)),
              ],
              if (order.paymentStatus != null) ...[
                const SizedBox(width: 6),
                _chip(
                  order.paymentStatus == 'paid' ? 'Paid' : 'COD',
                  order.paymentStatus == 'paid' ? BytzGoTheme.accentDark : BytzGoTheme.warning,
                ),
              ],
              const Spacer(),
              Text(
                formatCedis(order.total),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: BytzGoTheme.sheetText,
                ),
              ),
            ],
          ),
          if (order.isCourier && order.pickup != null)
            Text('Pickup: ${order.pickup}', style: BytzGoTheme.sheetBody(12)),
          if (!order.isCourier && vendor != null)
            Text('Pickup: ${vendor.name}', style: BytzGoTheme.sheetBody(12)),
          Text('Drop-off: ${order.address}', style: BytzGoTheme.sheetBody(13)),
          if (secs != null) ...[
            const SizedBox(height: 6),
            Text(
              'Expires in ${secs}s${order.dispatchWave != null ? ' · wave ${order.dispatchWave}' : ''}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: BytzGoTheme.warning,
              ),
            ),
          ],
          const SizedBox(height: 10),
          RideAccentButton(
            label: 'Accept & navigate',
            loading: _accepting,
            onPressed: () => _acceptOrder(order),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _activeList() {
    if (_activeOrders.isEmpty) {
      return const BytzEmptyState(
        light: true,
        icon: Icons.delivery_dining_outlined,
        title: 'No active trips',
        subtitle: 'Go online on the Drive tab to receive delivery offers.',
      );
    }
    return Column(children: _activeOrders.map(_activeCard).toList());
  }

  Widget _activeCard(Order order) {
    final nav = navigationTarget(order, _vendors);
    final step = activeTripStep(order);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BytzGoTheme.accent.withValues(alpha: 0.35)),
        gradient: LinearGradient(
          colors: [
            BytzGoTheme.sheetDivider.withValues(alpha: 0.5),
            BytzGoTheme.sheetBg,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '#${order.id.length > 4 ? order.id.substring(order.id.length - 4) : order.id}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  color: BytzGoTheme.sheetText,
                ),
              ),
              const Spacer(),
              Text(
                order.status.replaceAll('_', ' ').toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: BytzGoTheme.accentDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(4, (i) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: i < step ? BytzGoTheme.accent : BytzGoTheme.sheetDivider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          if (nav != null) ...[
            const SizedBox(height: 10),
            Text(nav.label, style: BytzGoTheme.sheetBody(13), maxLines: 2),
          ],
          if (tripAllowsContact(order)) ...[
            const SizedBox(height: 12),
            TripContactActions(
              order: order,
              phone: order.customerPhone,
              label: 'Contact customer',
              chatTitle: order.customerName.isNotEmpty
                  ? 'Chat with ${order.customerName}'
                  : 'Chat with customer',
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: nav == null ? null : () => _openNavigation(order),
                  icon: const Icon(Icons.map, size: 16),
                  label: const Text('Maps'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BytzGoTheme.sheetText,
                    side: const BorderSide(color: BytzGoTheme.sheetDivider),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _activeActionButton(order),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activeActionButton(Order order) {
    if (order.status == 'ready') {
      return FilledButton(
        onPressed: () => _markPickedUp(order),
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF38BDF8)),
        child: const Text('Picked up', style: TextStyle(fontSize: 12)),
      );
    }
    if (order.status == 'picked_up') {
      return FilledButton(
        onPressed: () => _markArrived(order),
        style: FilledButton.styleFrom(backgroundColor: BytzGoTheme.warning),
        child: const Text('Arrived', style: TextStyle(fontSize: 12)),
      );
    }
    if (order.status == 'arrived') {
      return FilledButton(
        onPressed: () => DeliveryPinDialog.show(
          context,
          order: order,
          orders: _ordersRepo,
          onCompleted: () {
            _snack('Delivery completed', success: true);
            _refreshAll();
          },
        ),
        style: FilledButton.styleFrom(backgroundColor: BytzGoTheme.accent),
        child: const Text('Complete', style: TextStyle(fontSize: 12)),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildTripsTab() {
    final trips = _completedTrips;
    return RefreshIndicator(
      onRefresh: _refreshAll,
      color: BytzGoTheme.accent,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Trip history',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            '${trips.length} completed',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 16),
          if (trips.isEmpty)
            const BytzEmptyState(
              icon: Icons.history,
              title: 'No completed trips yet',
              subtitle: 'Finished deliveries will appear here.',
            )
          else
            ...trips.map((o) {
              final vendor = _vendorFor(o);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '#${o.id.length > 4 ? o.id.substring(o.id.length - 4) : o.id}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${vendor?.name ?? 'Delivery'} → ${o.address}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                          if (o.rating != null && o.rating! > 0)
                            Row(
                              children: List.generate(5, (i) {
                                return Icon(
                                  Icons.star,
                                  size: 12,
                                  color: i < o.rating!
                                      ? Colors.amber
                                      : const Color(0xFF334155),
                                );
                              }),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      formatCedis(o.total),
                      style: const TextStyle(
                        color: BytzGoTheme.accent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildWalletTab(AuthUser user) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: BytzGoTheme.accent.withValues(alpha: 0.3)),
            gradient: LinearGradient(
              colors: [
                BytzGoTheme.accent.withValues(alpha: 0.15),
                Colors.transparent,
              ],
            ),
          ),
          child: Column(
            children: [
              const Icon(Icons.account_balance_wallet, color: BytzGoTheme.accent, size: 36),
              const SizedBox(height: 8),
              Text(
                'AVAILABLE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
              Text(
                formatCedis(user.balance),
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: BytzGoTheme.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            _withdrawMethodBtn('momo', 'MoMo'),
            const SizedBox(width: 8),
            _withdrawMethodBtn('bank', 'Bank'),
          ],
        ),
        const SizedBox(height: 12),
        if (_withdrawMethod == 'momo') ...[
          DropdownButtonFormField<String>(
            value: _withdrawNetwork,
            dropdownColor: const Color(0xFF0F172A),
            style: const TextStyle(color: Colors.white),
            decoration: _darkInputDeco(),
            items: const [
              DropdownMenuItem(value: 'mtn', child: Text('MTN')),
              DropdownMenuItem(value: 'vodafone', child: Text('Vodafone')),
              DropdownMenuItem(value: 'airteltigo', child: Text('AirtelTigo')),
            ],
            onChanged: (v) => setState(() => _withdrawNetwork = v ?? 'mtn'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _withdrawPhone,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.white),
            decoration: _darkInputDeco(hint: 'Phone number'),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _withdrawAmount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: _darkInputDeco(hint: 'Amount (₵)'),
        ),
        if (_walletMsg != null) ...[
          const SizedBox(height: 10),
          Text(
            _walletMsg!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _walletOk ? BytzGoTheme.accent : Colors.redAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 16),
        RidePrimaryButton(
          label: _withdrawing ? 'Processing…' : 'Withdraw',
          onPressed: _withdrawing ? null : _handleWithdraw,
        ),
      ],
    );
  }

  InputDecoration _darkInputDeco({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
      filled: true,
      fillColor: const Color(0xFF0F172A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
    );
  }

  Widget _withdrawMethodBtn(String id, String label) {
    final selected = _withdrawMethod == id;
    return Expanded(
      child: OutlinedButton(
        onPressed: () => setState(() => _withdrawMethod = id),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? BytzGoTheme.accent : Colors.transparent,
          foregroundColor: selected ? const Color(0xFF020617) : Colors.white54,
          side: BorderSide(
            color: selected ? BytzGoTheme.accent : const Color(0xFF334155),
          ),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
      ),
    );
  }

  Future<void> _handleWithdraw() async {
    final amount = double.tryParse(_withdrawAmount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() {
        _walletMsg = 'Enter a valid amount';
        _walletOk = false;
      });
      return;
    }
    final payoutPhone = _withdrawMethod == 'momo'
        ? _withdrawPhone.text.trim()
        : '${_withdrawBank.text.trim()} | ${_withdrawAccName.text.trim()} | ${_withdrawAccNum.text.trim()}';
    if (payoutPhone.isEmpty) {
      setState(() {
        _walletMsg = _withdrawMethod == 'momo'
            ? 'Enter MoMo phone number'
            : 'Enter bank details';
        _walletOk = false;
      });
      return;
    }
    setState(() => _withdrawing = true);
    try {
      final balance = await _wallet.withdraw(
        amount: amount,
        phone: payoutPhone,
        method: _withdrawMethod,
        network: _withdrawNetwork,
      );
      _session.patchBalance(balance);
      if (!mounted) return;
      setState(() {
        _walletMsg = 'Withdrawal successful';
        _walletOk = true;
        _withdrawAmount.clear();
      });
    } catch (e) {
      setState(() {
        _walletMsg = WalletRepository.errorMessage(e);
        _walletOk = false;
      });
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  Widget _buildProfileTab(AuthUser user) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            ProfileAvatarUpload(user: user, radius: 32, dark: true),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    user.email,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        RiderVerificationSection(user: user),
        const SizedBox(height: 24),
        TextField(
          controller: _profilePhone,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white),
          decoration: _darkInputDeco(hint: 'Phone'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _profileRegion != null && ghanaRegions.contains(_profileRegion)
              ? _profileRegion
              : ghanaRegions.first,
          dropdownColor: const Color(0xFF0F172A),
          style: const TextStyle(color: Colors.white),
          decoration: _darkInputDeco(hint: 'Region'),
          items: ghanaRegions
              .map((r) => DropdownMenuItem(value: r, child: Text(r)))
              .toList(),
          onChanged: (v) => setState(() => _profileRegion = v),
        ),
        if (_profileMsg != null) ...[
          const SizedBox(height: 10),
          Text(_profileMsg!, style: const TextStyle(color: BytzGoTheme.accent)),
        ],
        const SizedBox(height: 16),
        RidePrimaryButton(
          label: _profileSaving ? 'Saving…' : 'Save profile',
          onPressed: _profileSaving ? null : _saveProfile,
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 20),
        const ProfileLegalSection(),
        const SizedBox(height: 12),
        const Center(child: DeleteAccountButton(dark: true)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _confirmLogout,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: const BorderSide(color: Color(0xFF334155)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  Future<void> _saveProfile() async {
    setState(() {
      _profileSaving = true;
      _profileMsg = null;
    });
    try {
      final result = await _auth.updateProfile(
        phone: _profilePhone.text.trim(),
        region: _profileRegion,
      );
      await _session.applyAuthResult(token: result.token, user: result.user);
      if (!mounted) return;
      setState(() => _profileMsg = 'Saved');
      await _refreshAll();
    } catch (e) {
      setState(() => _profileMsg = AuthRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _profileSaving = false);
    }
  }

  Widget _buildBottomNav() {
    const tabs = [
      (Icons.navigation, 'Drive'),
      (Icons.history, 'Trips'),
      (Icons.account_balance_wallet, 'Wallet'),
      (Icons.person, 'Account'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(tabs.length, (i) {
            final tab = _RiderTab.values[i];
            final selected = _tab == tab;
            return Expanded(
              child: InkWell(
                onTap: () {
          setState(() => _tab = tab);
          _syncOfferTimer();
        },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tabs[i].$1,
                        size: 22,
                        color: selected ? BytzGoTheme.accent : Colors.white38,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tabs[i].$2,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: selected ? BytzGoTheme.accent : Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: BytzGoTheme.sheetDivider.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            Text(label, style: BytzGoTheme.sheetBody(11)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
