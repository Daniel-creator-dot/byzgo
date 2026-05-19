import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config_repository.dart';
import '../../core/location_service.dart';
import '../../core/session.dart';
import '../../core/socket_service.dart';
import '../../models/location_point.dart';
import '../../models/order.dart';
import '../../shared/format.dart';
import '../../shared/delivery_pricing.dart';
import '../../shared/ghana_location.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/ride_google_map.dart';
import '../../shared/widgets/ride_ui.dart';
import '../orders/orders_repository.dart';

/// Customer home — map + book bike delivery + track active trips.
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final _pickupCtrl = TextEditingController();
  final _dropoffCtrl = TextEditingController();
  final _itemCtrl = TextEditingController(text: 'Package');

  LocationPoint? _pickup;
  LocationPoint? _destination;
  MapPickMode _pickMode = MapPickMode.destination;

  List<Order> _orders = [];
  bool _loading = true;
  bool _booking = false;
  bool _locatingPickup = false;
  String? _error;
  String? _socketHint;
  double _pricePerKm = defaultDeliveryPricePerKm;
  LocationPoint? _riderPosition;

  OrdersRepository get _ordersRepo => context.read<OrdersRepository>();
  SocketService get _socket => context.read<SocketService>();
  Session get _session => context.read<Session>();
  LocationService get _location => context.read<LocationService>();

  double get _deliveryFee {
    if (_pickup == null || _destination == null) return 0;
    if (!_pickup!.hasCoords || !_destination!.hasCoords) return 0;
    return courierFeeBetween(_pickup!, _destination!, _pricePerKm);
  }

  Order? get _activeCourier {
    final userId = _session.user?.id;
    if (userId == null) return null;
    final list = _orders.where((o) {
      if (o.customerId != userId) return false;
      if (['delivered', 'cancelled'].contains(o.status)) return false;
      final type = o.orderType ?? '';
      return type == 'courier' || o.pickup != null;
    });
    return list.isEmpty ? null : list.first;
  }

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _socket.clearHandlers();
    _pickupCtrl.dispose();
    _dropoffCtrl.dispose();
    _itemCtrl.dispose();
    super.dispose();
  }

  void _wireSocket() {
    _socket.clearHandlers();
    _socket.onOrderUpdated = (order) {
      if (!mounted) return;
      setState(() {
        final i = _orders.indexWhere((o) => o.id == order.id);
        if (i >= 0) {
          _orders[i] = order;
        } else {
          _orders = [order, ..._orders];
        }
        _socketHint = _statusMessage(order.status, order.riderId != null);
      });
    };
    _socket.onWalletUpdated = (balance) {
      if (!mounted) return;
      _session.patchBalance(balance);
    };
    _socket.onLocationUpdated = (riderId, lat, lng) {
      final active = _activeCourier;
      if (active?.riderId != riderId) return;
      if (!mounted) return;
      setState(() {
        _riderPosition = LocationPoint(
          address: 'Rider',
          lat: lat,
          lng: lng,
        );
      });
    };
  }

  String _statusMessage(String status, bool hasRider) {
    if (hasRider && status != 'delivered') {
      return 'Your rider is on the way — track on map';
    }
    switch (status) {
      case 'pending':
      case 'ready':
        return 'Finding a bike rider nearby…';
      case 'picked_up':
        return 'Package picked up — on the way';
      case 'arrived':
        return 'Rider has arrived';
      case 'delivered':
        return 'Delivered';
      default:
        return 'Trip updated';
    }
  }

  Future<void> _detectPickup() async {
    setState(() => _locatingPickup = true);
    try {
      final loc = await _location.getCurrentLocation();
      if (loc != null && mounted) {
        setState(() {
          _pickup = loc;
          _pickupCtrl.text = loc.address;
        });
      }
    } finally {
      if (mounted) setState(() => _locatingPickup = false);
    }
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = OrdersRepository.errorMessage(e);
        _loading = false;
      });
    }
  }

  void _onMapTap(double lat, double lng) {
    final point = LocationPoint(
      address: formatCoordAddress(lat, lng),
      lat: lat,
      lng: lng,
    );
    setState(() {
      if (_pickMode == MapPickMode.pickup) {
        _pickup = point;
        _pickupCtrl.text = point.address;
      } else {
        _destination = point;
        _dropoffCtrl.text = point.address;
      }
    });
  }

  Future<void> _requestDelivery() async {
    if (_pickup == null || !_pickup!.hasCoords) {
      _snack('Set a pickup location (GPS or tap map)');
      return;
    }
    if (_destination == null || !_destination!.hasCoords) {
      _snack('Set a drop-off — tap map or enter address');
      return;
    }
    final fee = _deliveryFee;
    if (fee <= 0) {
      _snack('Could not calculate delivery fee');
      return;
    }

    setState(() => _booking = true);
    HapticFeedback.mediumImpact();
    try {
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
      final order = await _ordersRepo.createCourierOrder(
        pickup: pickup,
        destination: dest,
        deliveryFee: fee,
        itemDescription: _itemCtrl.text.trim().isEmpty
            ? 'Package'
            : _itemCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _orders = [order, ..._orders];
        _socketHint = 'Finding a bike rider nearby…';
      });
      _snack('Bike requested — waiting for a rider', success: true);
    } catch (e) {
      _snack(OrdersRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _booking = false);
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

  Future<void> _logout() async {
    await _session.clear();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user!;
    final active = _activeCourier;
    final tracking = active != null;
    final fee = _deliveryFee;

    return RideShell(
      mapChild: RideGoogleMap(
        pickup: _pickup,
        destination: _destination,
        riderPosition: _riderPosition,
        showRoute: _pickup != null && _destination != null,
        mapPickMode: _pickMode,
        onMapTap: tracking ? null : _onMapTap,
      ),
      topBar: Row(
        children: [
          _circleIcon(Icons.menu, onTap: _logout),
          const Spacer(),
          TripStatusChip(
            label: formatCedisCompact(user.balance),
            icon: Icons.account_balance_wallet_outlined,
          ),
        ],
      ),
      floatingMapChild: tracking
          ? SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 64),
                  child: TripStatusChip(
                    label: _statusMessage(
                      active.status,
                      active.riderId != null,
                    ),
                  ),
                ),
              ),
            )
          : null,
      sheet: RideSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tracking ? 'Track delivery' : 'Bike delivery',
              style: BytzGoTheme.sheetTitle(),
            ),
            const SizedBox(height: 4),
            Text(
              tracking
                  ? active.address
                  : 'Tap map to set pickup & drop-off',
              style: BytzGoTheme.sheetBody(14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (_socketHint != null) ...[
              const SizedBox(height: 10),
              _hintBanner(_socketHint!),
            ],
            if (!tracking) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  _pickChip('Pickup', MapPickMode.pickup),
                  const SizedBox(width: 8),
                  _pickChip('Drop-off', MapPickMode.destination),
                ],
              ),
              const SizedBox(height: 12),
              _locationCard(),
              const SizedBox(height: 12),
              TextField(
                controller: _itemCtrl,
                style: const TextStyle(
                  color: BytzGoTheme.sheetText,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  labelText: 'What are you sending?',
                  labelStyle: BytzGoTheme.sheetBody(),
                  filled: true,
                  fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (fee > 0)
                ServiceTypeTile(
                  title: 'Bike courier',
                  subtitle: 'Pay when rider arrives',
                  price: formatCedis(fee),
                ),
              const SizedBox(height: 16),
              RidePrimaryButton(
                label: 'Request bike',
                icon: Icons.two_wheeler,
                loading: _booking,
                onPressed: _requestDelivery,
              ),
            ] else ...[
              const SizedBox(height: 16),
              ActiveTripTile(
                address: active.address,
                status: active.status,
                price: formatCedis(active.total),
                onTap: () {},
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loadOrders,
                child: const Text(
                  'Refresh status',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: BytzGoTheme.accentDark,
                  ),
                ),
              ),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 16),
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
                child: Text(_error!, style: const TextStyle(color: BytzGoTheme.danger)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pickChip(String label, MapPickMode mode) {
    final selected = _pickMode == mode;
    return Expanded(
      child: Material(
        color: selected
            ? BytzGoTheme.accent.withValues(alpha: 0.15)
            : BytzGoTheme.sheetDivider.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => setState(() => _pickMode = mode),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? BytzGoTheme.accentDark : BytzGoTheme.sheetMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _locationCard() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: BytzGoTheme.sheetDivider),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          LocationRow(
            icon: pickupDot(),
            iconColor: BytzGoTheme.accent,
            hint: _locatingPickup ? 'Getting location…' : 'Pickup',
            controller: _pickupCtrl,
            onTap: () => setState(() => _pickMode = MapPickMode.pickup),
          ),
          Divider(height: 1, color: BytzGoTheme.sheetDivider.withValues(alpha: 0.8)),
          LocationRow(
            icon: dropoffSquare(),
            iconColor: BytzGoTheme.sheetText,
            hint: 'Where to?',
            controller: _dropoffCtrl,
            onTap: () => setState(() => _pickMode = MapPickMode.destination),
          ),
        ],
      ),
    );
  }

  Widget _hintBanner(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: BytzGoTheme.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.two_wheeler, size: 18, color: BytzGoTheme.accentDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: BytzGoTheme.accentDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleIcon(IconData icon, {VoidCallback? onTap}) {
    return Material(
      color: BytzGoTheme.sheetBg,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: BytzGoTheme.sheetText, size: 22),
        ),
      ),
    );
  }
}
