import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/places_service.dart';
import '../../models/location_point.dart';
import '../../models/product.dart';
import '../../models/vendor.dart';
import '../../shared/format.dart';
import '../../shared/pharmacy_display.dart';
import '../../shared/theme.dart';
import '../../shared/vendor_pickup.dart';
import '../../shared/widgets/product_tile_image.dart';
import '../../shared/widgets/sheet_theme_scope.dart';
import '../orders/orders_repository.dart';
import 'customer_shop_checkout_screen.dart';

/// Menu items for a single shop/vendor — add to cart and checkout with km billing.
class CustomerVendorMenuScreen extends StatefulWidget {
  const CustomerVendorMenuScreen({
    super.key,
    required this.vendor,
    this.onBookPickup,
  });

  final Vendor vendor;
  final void Function(LocationPoint pickup)? onBookPickup;

  @override
  State<CustomerVendorMenuScreen> createState() =>
      _CustomerVendorMenuScreenState();
}

class _CustomerVendorMenuScreenState extends State<CustomerVendorMenuScreen> {
  List<Product> _products = [];
  final Map<String, int> _cart = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int get _cartCount => _cart.values.fold(0, (a, b) => a + b);

  double get _cartSubtotal {
    var sum = 0.0;
    for (final p in _products) {
      final q = _cart[p.id] ?? 0;
      if (q > 0) sum += p.price * q;
    }
    return sum;
  }

  Map<Product, int> get _cartProducts {
    final map = <Product, int>{};
    for (final p in _products) {
      final q = _cart[p.id] ?? 0;
      if (q > 0) map[p] = q;
    }
    return map;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<OrdersRepository>().fetchProducts(
            vendorId: widget.vendor.id,
          );
      if (!mounted) return;
      setState(() {
        _products = list;
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

  void _changeQty(Product p, int delta) {
    setState(() {
      final next = (_cart[p.id] ?? 0) + delta;
      if (next <= 0) {
        _cart.remove(p.id);
      } else {
        _cart[p.id] = next;
      }
    });
  }

  Future<LocationPoint?> _resolveShopPickup() async {
    return resolveVendorPickup(widget.vendor, context.read<PlacesService>());
  }

  Future<void> _bookPickupFromShop() async {
    final point = await _resolveShopPickup();
    if (!mounted) return;
    if (point == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not find this shop on the map — try another store.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).pop();
    widget.onBookPickup?.call(point);
  }

  Future<void> _openCheckout() async {
    if (_cartCount == 0) return;
    final pickup = await _resolveShopPickup();
    if (!mounted) return;
    if (pickup == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not find this shop on the map — try another store.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerShopCheckoutScreen(
          vendor: widget.vendor,
          pickup: pickup,
          cart: _cartProducts,
        ),
      ),
    );
  }

  Map<String, List<Product>> get _byCategory {
    final map = <String, List<Product>>{};
    for (final p in _products) {
      final key = (p.category?.trim().isNotEmpty == true)
          ? p.category!.trim()
          : 'Menu';
      map.putIfAbsent(key, () => []).add(p);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vendor;
    final hasCart = _cartCount > 0;

    return SheetThemeScope(
      child: Scaffold(
      backgroundColor: BytzGoTheme.sheetBg,
      appBar: AppBar(
        backgroundColor: BytzGoTheme.sheetBg,
        foregroundColor: BytzGoTheme.sheetText,
        elevation: 0,
        title: Row(
          children: [
            if (ProductTileImage.isPrimeCareVendor(v)) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/branding/primecare_logo.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                v.name,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ),
          ],
        ),
        actions: [
          if (hasCart)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '$_cartCount',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (v.address != null && v.address!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 18,
                    color: BytzGoTheme.brandBlue,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(v.address!, style: BytzGoTheme.sheetBody(13))),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: BytzGoTheme.danger),
                              ),
                              const SizedBox(height: 16),
                              TextButton(onPressed: _load, child: const Text('Try again')),
                            ],
                          ),
                        ),
                      )
                    : _products.isEmpty
                        ? Center(
                            child: Text(
                              'No items listed for this shop yet.',
                              style: BytzGoTheme.sheetBody(14),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                              children: [
                                for (final entry in _byCategory.entries) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8, bottom: 10),
                                    child: Text(
                                      formatPharmacyCategory(entry.key),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        color: BytzGoTheme.sheetText,
                                      ),
                                    ),
                                  ),
                                  ...entry.value.map(
                                    (p) => _ProductTile(
                                      vendor: v,
                                      product: p,
                                      quantity: _cart[p.id] ?? 0,
                                      onAdd: () => _changeQty(p, 1),
                                      onRemove: () => _changeQty(p, -1),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
          ),
        ],
      ),
      bottomNavigationBar: widget.onBookPickup == null && !hasCart
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasCart)
                      FilledButton(
                        onPressed: _openCheckout,
                        style: FilledButton.styleFrom(
                          backgroundColor: BytzGoTheme.brandBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Checkout ($_cartCount) · ${formatCedis(_cartSubtotal)} + delivery',
                        ),
                      ),
                    if (hasCart && widget.onBookPickup != null)
                      const SizedBox(height: 8),
                    if (widget.onBookPickup != null)
                      OutlinedButton.icon(
                        onPressed: _bookPickupFromShop,
                        icon: const Icon(Icons.delivery_dining),
                        label: Text(
                          hasCart
                              ? 'Courier only (no items)'
                              : 'Book delivery from this shop',
                        ),
                      ),
                  ],
                ),
              ),
            ),
    ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.vendor,
    required this.product,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final Vendor vendor;
  final Product product;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final outOfStock = !product.canAddToCart;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductTileImage(vendor: vendor, product: product),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: BytzGoTheme.sheetText,
                      ),
                    ),
                    if (outOfStock) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Out of stock',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: BytzGoTheme.danger.withValues(alpha: 0.9),
                        ),
                      ),
                    ] else if (product.description != null &&
                        product.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        product.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: BytzGoTheme.sheetBody(12),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      formatCedis(product.price),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: BytzGoTheme.brandBlue,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    onPressed: outOfStock ? null : onAdd,
                    icon: Icon(
                      Icons.add_circle,
                      color: outOfStock
                          ? BytzGoTheme.sheetMuted.withValues(alpha: 0.4)
                          : BytzGoTheme.brandBlue,
                    ),
                  ),
                  if (quantity > 0) ...[
                    Text('$quantity', style: const TextStyle(fontWeight: FontWeight.w800)),
                    IconButton(
                      onPressed: onRemove,
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        color: BytzGoTheme.sheetMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
