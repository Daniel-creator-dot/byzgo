import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/config_repository.dart';
import '../../core/location_service.dart';
import '../../core/places_service.dart';
import '../../core/session.dart';
import '../../core/socket_service.dart';
import '../../models/location_point.dart';
import '../../models/order.dart';
import '../../shared/format.dart';
import '../../shared/delivery_pricing.dart';
import '../../shared/ghana_location.dart';
import '../../shared/rider_trip.dart';
import '../../shared/customer_trip.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/bytz_brand.dart';
import '../../shared/widgets/ride_google_map.dart';
import '../../shared/widgets/ride_ui.dart';
import '../orders/orders_repository.dart';
import '../../shared/widgets/location_autocomplete_field.dart';
import 'customer_trip_tracking.dart';

/// Customer home — map + book bike delivery + track active trips.
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({
    super.key,
    this.embedded = false,
    this.initialPickup,
    this.onOpenShops,
    this.onOpenWallet,
    this.onOpenActivity,
    this.onOpenProfile,
  });

  final bool embedded;
  final LocationPoint? initialPickup;
  final VoidCallback? onOpenShops;
  final VoidCallback? onOpenWallet;
  final VoidCallback? onOpenActivity;
  final VoidCallback? onOpenProfile;

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
  bool _resolvingPickup = false;
  bool _resolvingDropoff = false;
  String? _error;
  double _pricePerKm = defaultDeliveryPricePerKm;
  LocationPoint? _riderPosition;
  SocketService? _socket;

  OrdersRepository get _ordersRepo => context.read<OrdersRepository>();
  Session get _session => context.read<Session>();
  LocationService get _location => context.read<LocationService>();
  PlacesService get _places => context.read<PlacesService>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _socket ??= context.read<SocketService>();
  }

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

  @override
  void dispose() {
    _socket?.clearHandlers();
    _pickupCtrl.dispose();
    _dropoffCtrl.dispose();
    _itemCtrl.dispose();
    super.dispose();
  }

  void _wireSocket() {
    final socket = _socket;
    if (socket == null) return;
    socket.clearHandlers();
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
      if (order.status == 'delivered' && prev?.status != 'delivered') {
        _snack('Delivered — thanks for using BytzGO!', success: true);
      } else if (order.status == 'arrived' && prev?.status != 'arrived') {
        _snack('Driver arrived — complete payment for your PIN', success: true);
      } else if (order.riderId != null && prev?.riderId == null) {
        _snack('Biker found — they\'re on the way', success: true);
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
          address: 'Rider',
          lat: lat,
          lng: lng,
        );
      });
    };
  }

  void _replaceOrder(Order order) {
    setState(() {
      final i = _orders.indexWhere((o) => o.id == order.id);
      if (i >= 0) {
        _orders[i] = order;
      } else {
        _orders = [order, ..._orders];
      }
    });
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
      if (loc == null || !mounted) return;

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
    final isPickup = _pickMode == MapPickMode.pickup;
    _applyCoordsFromMap(isPickup: isPickup, lat: lat, lng: lng);
  }

  void _onPickupLocation(LocationPoint point) {
    final label = displayLocationLabel(point.address, point.lat, point.lng);
    setState(() {
      _pickup = point.copyWith(address: label);
      _pickupCtrl.text = label;
      _pickMode = MapPickMode.pickup;
    });
  }

  void _onDropoffLocation(LocationPoint point) {
    final label = displayLocationLabel(point.address, point.lat, point.lng);
    setState(() {
      _destination = point.copyWith(address: label);
      _dropoffCtrl.text = label;
      _pickMode = MapPickMode.destination;
    });
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

  Future<void> _requestDelivery() async {
    if (_pickup == null || !_pickup!.hasCoords) {
      _snack('Set pickup — allow location, search, or pick a shop');
      return;
    }
    if (_destination == null || !_destination!.hasCoords) {
      _snack('Choose a drop-off from search or tap the map');
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

  @override
  Widget build(BuildContext context) {
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
      floatingMapChild: tracking
          ? SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 64),
                  child: TripStatusChip(
                    label: customerTripHeadline(active),
                  ),
                ),
              ),
            )
          : null,
      sheet: RideSheet(
        maxHeightFraction: widget.embedded ? 0.52 : 0.68,
        bottomInset: widget.embedded ? 4 : 0,
        footer: !tracking
            ? RidePrimaryButton(
                label: 'Request bike',
                icon: Icons.two_wheeler,
                loading: _booking,
                onPressed: _requestDelivery,
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!tracking && !widget.embedded) ...[
              _quickActions(),
              const SizedBox(height: 10),
            ],
            Text(
              tracking ? 'Track delivery' : 'Bike delivery',
              style: BytzGoTheme.sheetTitle(),
            ),
            const SizedBox(height: 4),
            if (!tracking)
              Text(
                'Search an address or tap the map',
                style: BytzGoTheme.sheetBody(14),
              ),
            if (tracking) ...[
              const SizedBox(height: 12),
              CustomerDeliveryTracker(
                order: active,
                onOrderUpdated: _replaceOrder,
              ),
            ],
            if (!tracking) ...[
              if (!widget.embedded) ...[
                const SizedBox(height: 10),
                const BrandPromoBanner(
                  title: 'Trusted handoffs',
                  subtitle: 'Real riders. Live tracking. Pay on delivery.',
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _pickChip('Pickup', MapPickMode.pickup),
                  const SizedBox(width: 8),
                  _pickChip('Drop-off', MapPickMode.destination),
                ],
              ),
              const SizedBox(height: 10),
              _locationCard(),
              const SizedBox(height: 10),
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
              const SizedBox(height: 10),
              RideAnimatedReveal(
                visible: fee > 0,
                child: ServiceTypeTile(
                  key: ValueKey('fee-$fee'),
                  title: 'Bike courier',
                  subtitle: 'Pay when rider arrives',
                  price: formatCedis(fee),
                ),
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
                child: Text(_error!, style: const TextStyle(color: BytzGoTheme.danger)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _quickActions() {
    return SizedBox(
      height: 76,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _quickAction(Icons.storefront_outlined, 'Shops', widget.onOpenShops),
          _quickAction(Icons.add_card, 'Top up', widget.onOpenWallet),
          _quickAction(Icons.route_outlined, 'Trips', widget.onOpenActivity),
          _quickAction(Icons.person_outline, 'Profile', widget.onOpenProfile),
          _quickAction(Icons.headset_mic_outlined, 'Help', () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Support: support@bytzgo.com'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _quickAction(IconData icon, String label, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: PressableScale(
        onTap: onTap,
        child: Container(
          width: 72,
          decoration: BoxDecoration(
            color: BytzGoTheme.sheetBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: BytzGoTheme.sheetDivider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: BytzGoTheme.brandBlue, size: 22),
              const SizedBox(height: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: BytzGoTheme.sheetText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickChip(String label, MapPickMode mode) {
    final selected = _pickMode == mode;
    return Expanded(
      child: PressableScale(
        onTap: () => setState(() => _pickMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected
                ? BytzGoTheme.accent.withValues(alpha: 0.18)
                : BytzGoTheme.sheetDivider.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? BytzGoTheme.accent : Colors.transparent,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: selected ? BytzGoTheme.accentDark : BytzGoTheme.sheetMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _locationCard() {
    return Container(
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetBg,
        border: Border.all(color: BytzGoTheme.sheetDivider),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          LocationAutocompleteField(
            icon: pickupDot(),
            hint: 'Current location or address',
            controller: _pickupCtrl,
            locating: _locatingPickup,
            resolving: _resolvingPickup,
            showUseMyLocation: true,
            onUseMyLocation: () => _applyCurrentLocation(toPickup: true),
            onTap: () => setState(() => _pickMode = MapPickMode.pickup),
            onLocation: _onPickupLocation,
            onAddressEdited: (text) => _onAddressEdited(isPickup: true, text: text),
          ),
          Divider(height: 1, color: BytzGoTheme.sheetDivider.withValues(alpha: 0.8)),
          LocationAutocompleteField(
            icon: dropoffSquare(),
            hint: 'Where to?',
            controller: _dropoffCtrl,
            resolving: _resolvingDropoff,
            onTap: () => setState(() => _pickMode = MapPickMode.destination),
            onLocation: _onDropoffLocation,
            onAddressEdited: (text) => _onAddressEdited(isPickup: false, text: text),
          ),
        ],
      ),
    );
  }

}
