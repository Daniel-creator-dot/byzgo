import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/location_service.dart';
import '../../core/places_service.dart';
import '../../core/session.dart';
import '../../models/delivery_quote.dart';
import '../../models/location_point.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../models/vendor.dart';
import '../../shared/format.dart';
import '../../shared/ghana_location.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/bytz_scaffold.dart';
import '../../shared/widgets/bytz_state_panels.dart';
import '../../shared/widgets/location_autocomplete_field.dart';
import '../../shared/widgets/ride_ui.dart';
import '../../shared/widgets/sheet_theme_scope.dart';
import '../orders/orders_repository.dart';

/// Checkout after selecting items — bills shop → customer kilometers.
class CustomerShopCheckoutScreen extends StatefulWidget {
  const CustomerShopCheckoutScreen({
    super.key,
    required this.vendor,
    required this.pickup,
    required this.cart,
    this.onOrderPlaced,
  });

  final Vendor vendor;
  final LocationPoint pickup;
  final Map<Product, int> cart;
  final void Function(Order order)? onOrderPlaced;

  @override
  State<CustomerShopCheckoutScreen> createState() =>
      _CustomerShopCheckoutScreenState();
}

class _CustomerShopCheckoutScreenState extends State<CustomerShopCheckoutScreen> {
  final _dropoffCtrl = TextEditingController();
  LocationPoint? _destination;
  DeliveryQuote? _quote;
  bool _quoting = false;
  bool _placing = false;
  String? _error;

  double get _itemsSubtotal {
    var sum = 0.0;
    widget.cart.forEach((p, qty) => sum += p.price * qty);
    return sum;
  }

  int get _itemCount =>
      widget.cart.values.fold<int>(0, (a, b) => a + b);

  @override
  void dispose() {
    _dropoffCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshQuote() async {
    final dest = _destination;
    if (dest == null || !dest.hasCoords || !widget.pickup.hasCoords) {
      setState(() => _quote = null);
      return;
    }
    setState(() {
      _quoting = true;
      _error = null;
    });
    try {
      final region = context.read<Session>().user?.region;
      final quote = await context.read<OrdersRepository>().calculateRouteDelivery(
            pickupLat: widget.pickup.lat,
            pickupLng: widget.pickup.lng,
            destLat: dest.lat,
            destLng: dest.lng,
            pickupRegion: region,
            destinationRegion: region,
          );
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _quoting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = OrdersRepository.errorMessage(e);
        _quoting = false;
      });
    }
  }

  Future<void> _useMyLocation() async {
    final loc = context.read<LocationService>();
    final places = context.read<PlacesService>();
    final point = await loc.getCurrentLocation();
    if (!mounted) return;
    if (point == null) {
      _snack('Enable location in Ghana, or search your delivery address.');
      return;
    }
    await _applyDropoffPoint(point, places);
  }

  Future<void> _applyDropoffPoint(LocationPoint point, PlacesService places) async {
    if (!point.hasCoords) return;
    if (!isUsableGhanaLocation(point.lat, point.lng)) {
      _snack('Delivery must be within Ghana — choose another address.');
      return;
    }
    setState(() => _dropoffCtrl.text = 'Finding address…');
    final label = await places.resolveAddressLabel(
      point.lat,
      point.lng,
      existing: point.address,
    );
    if (!mounted) return;
    setState(() {
      _destination = LocationPoint(address: label, lat: point.lat, lng: point.lng);
      _dropoffCtrl.text = label;
    });
    await _refreshQuote();
  }

  Future<void> _placeOrder() async {
    final dest = _destination;
    final quote = _quote;
    if (dest == null || !dest.hasCoords) {
      _snack('Choose your delivery address');
      return;
    }
    if (quote == null) {
      _snack('Waiting for delivery price…');
      return;
    }

    setState(() => _placing = true);
    try {
      final lines = widget.cart.entries
          .map(
            (e) => ShopCartLine(
              productId: e.key.id,
              name: e.key.name,
              price: e.key.price,
              quantity: e.value,
            ),
          )
          .toList();

      final order = await context.read<OrdersRepository>().createShopCourierOrder(
            vendorId: widget.vendor.id,
            pickup: widget.pickup,
            destination: dest,
            lines: lines,
            deliveryFee: quote.deliveryFee,
            itemDescription: '${widget.vendor.name} order ($_itemCount items)',
          );
      if (!mounted) return;
      widget.onOrderPlaced?.call(order);
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Order placed — see Activity tab (${widget.vendor.name}, ${quote.distanceKm.toStringAsFixed(1)} km)',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: BytzGoTheme.accentDark,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _snack(OrdersRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deliveryFee = _quote?.deliveryFee ?? 0;
    final total = _itemsSubtotal + deliveryFee;

    return SheetThemeScope(
      child: Scaffold(
      backgroundColor: BytzGoTheme.sheetBg,
      appBar: AppBar(
        backgroundColor: BytzGoTheme.sheetBg,
        foregroundColor: BytzGoTheme.sheetText,
        elevation: 0,
        title: const Text('Checkout', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _RouteCard(
            shopName: widget.vendor.name,
            pickup: widget.pickup,
            destination: _destination,
          ),
          const SizedBox(height: 16),
          Text('Deliver to', style: BytzGoTheme.sheetBody(12).copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          LocationAutocompleteField(
            icon: dropoffSquare(),
            controller: _dropoffCtrl,
            hint: 'Your address',
            showUseMyLocation: true,
            onUseMyLocation: _useMyLocation,
            onLocation: (point) async {
              await _applyDropoffPoint(point, context.read<PlacesService>());
            },
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _useMyLocation,
            icon: const Icon(Icons.my_location, size: 18),
            label: const Text('Use my location'),
          ),
          if (_quoting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (_quote != null) ...[
            const SizedBox(height: 12),
            _FeeBreakdown(
              itemsSubtotal: _itemsSubtotal,
              itemCount: _itemCount,
              distanceKm: _quote!.distanceKm,
              deliveryFee: deliveryFee,
              total: total,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            BytzErrorPanel(
              message: _error!,
              onRetry: _refreshQuote,
              light: true,
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: (_placing || _quoting || _quote == null) ? null : _placeOrder,
            style: FilledButton.styleFrom(
              backgroundColor: BytzGoTheme.brandBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              _placing
                  ? 'Placing order…'
                  : 'Place order · ${formatCedis(total)}',
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.shopName,
    required this.pickup,
    this.destination,
  });

  final String shopName;
  final LocationPoint pickup;
  final LocationPoint? destination;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rider route',
              style: TextStyle(fontWeight: FontWeight.w800, color: BytzGoTheme.sheetText),
            ),
            const SizedBox(height: 10),
            _LegRow(
              icon: Icons.storefront,
              label: '1. Shop',
              address: pickup.address,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 11),
              child: Container(width: 2, height: 16, color: BytzGoTheme.brandBlue.withValues(alpha: 0.4)),
            ),
            _LegRow(
              icon: Icons.home_outlined,
              label: '2. You',
              address: destination?.address ?? 'Select delivery address',
              muted: destination == null,
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.delivery_dining_outlined,
                  size: 20,
                  color: BytzGoTheme.brandBlue.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'When your request goes through, a rider heads to $shopName first to pick up your order, then delivers to you.',
                    style: BytzGoTheme.sheetBody(12).copyWith(
                      color: BytzGoTheme.sheetText,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegRow extends StatelessWidget {
  const _LegRow({
    required this.icon,
    required this.label,
    required this.address,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final String address;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: BytzGoTheme.brandBlue),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text(
                address,
                style: TextStyle(
                  fontSize: 12,
                  color: muted ? BytzGoTheme.sheetMuted : BytzGoTheme.sheetText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeeBreakdown extends StatelessWidget {
  const _FeeBreakdown({
    required this.itemsSubtotal,
    required this.itemCount,
    required this.distanceKm,
    required this.deliveryFee,
    required this.total,
  });

  final double itemsSubtotal;
  final int itemCount;
  final double distanceKm;
  final double deliveryFee;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BytzGoTheme.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _row('Items ($itemCount)', formatCedis(itemsSubtotal)),
            _row('Delivery (${distanceKm.toStringAsFixed(1)} km, shop → you)', formatCedis(deliveryFee)),
            const Divider(height: 20),
            _row('Total', formatCedis(total), bold: true),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: BytzGoTheme.sheetBody(bold ? 14 : 13))),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: bold ? BytzGoTheme.brandBlue : BytzGoTheme.sheetText,
            ),
          ),
        ],
      ),
    );
  }
}
