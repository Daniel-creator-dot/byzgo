import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/places_service.dart';
import '../../core/socket_service.dart';
import '../../core/json_parse.dart';
import '../../models/location_point.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../models/vendor.dart';
import '../../shared/format.dart';
import '../../shared/pharmacy_display.dart';
import '../../shared/theme.dart';
import '../../shared/external_navigation.dart';
import '../../shared/shop_chat_sheet.dart';
import '../../shared/vendor_contact.dart';
import '../../shared/vendor_pickup.dart';
import '../../shared/widgets/product_tile_image.dart';
import '../../shared/widgets/sheet_theme_scope.dart';
import '../../shared/shop_story_views.dart';
import '../../shared/widgets/app_network_image.dart';
import '../../shared/widgets/vendor_shop_avatar.dart';
import '../../shared/widgets/vendor_promo_badge.dart';
import 'vendor_story_viewer.dart';
import '../auth/auth_gate.dart';
import '../orders/orders_repository.dart';
import 'customer_shop_checkout_screen.dart';

/// Menu items for a single shop/vendor — add to cart and checkout with km billing.
class CustomerVendorMenuScreen extends StatefulWidget {
  const CustomerVendorMenuScreen({
    super.key,
    required this.vendor,
    this.onBookPickup,
    this.onShopOrderPlaced,
  });

  final Vendor vendor;
  final void Function(LocationPoint pickup)? onBookPickup;
  final void Function(Order order)? onShopOrderPlaced;

  @override
  State<CustomerVendorMenuScreen> createState() =>
      _CustomerVendorMenuScreenState();
}

class _CustomerVendorMenuScreenState extends State<CustomerVendorMenuScreen>
    with WidgetsBindingObserver {
  List<Product> _products = [];
  final Map<String, int> _cart = {};
  bool _loading = true;
  String? _error;
  ProductUpdatedHandler? _productHandler;
  VendorPromoHandler? _promoHandler;
  late final SocketService _socket;
  late Vendor _vendor;
  Map<String, int> _seenPostedAt = {};

  @override
  void initState() {
    super.initState();
    _vendor = widget.vendor;
    WidgetsBinding.instance.addObserver(this);
    _loadSeen();
    _load();
    _socket = context.read<SocketService>();
    _productHandler = (vendorId, product) {
      if (vendorId != _vendor.id || !mounted) return;
      final id = product['id']?.toString();
      if (id == null) return;
      final idx = _products.indexWhere((p) => p.id == id);
      if (idx < 0) {
        _load();
        return;
      }
      setState(() {
        final prev = _products[idx];
        _products[idx] = Product(
          id: prev.id,
          vendorId: prev.vendorId,
          name: product['name']?.toString() ?? prev.name,
          price: parseJsonDoubleOrZero(product['price']),
          description: prev.description,
          category: prev.category,
          imageUrl: prev.imageUrl,
          isAvailable: product['is_available'] != false,
          isApproved: prev.isApproved,
        );
      });
    };
    _socket.onProductUpdated = _productHandler;
    _promoHandler = (data) {
      final id = data['vendorId']?.toString() ?? data['id']?.toString();
      if (id != _vendor.id || !mounted) return;
      setState(() => _vendor = _vendor.copyWithPromo(data));
    };
    _socket.addVendorPromoListener(_promoHandler!);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_socket.onProductUpdated == _productHandler) {
      _socket.onProductUpdated = null;
    }
    if (_promoHandler != null) {
      _socket.removeVendorPromoListener(_promoHandler!);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
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

  Future<void> _loadSeen() async {
    final seen = await ShopStoryViews.loadSeenPostedAt();
    if (!mounted) return;
    setState(() => _seenPostedAt = seen);
  }

  Future<void> _openShopDrop() async {
    if (!_vendor.hasActiveStory) return;
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, __, ___) => VendorStoryViewer(
          vendors: [_vendor],
          initialIndex: 0,
          seenPostedAt: _seenPostedAt,
          onSeen: (v) async {
            await ShopStoryViews.markSeen(v);
            final posted = v.shopStoryPostedAt?.millisecondsSinceEpoch;
            if (posted != null && mounted) {
              setState(() => _seenPostedAt = {..._seenPostedAt, v.id: posted});
            }
          },
          onOrder: (_) {},
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<OrdersRepository>().fetchProducts(
            vendorId: _vendor.id,
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
    return resolveVendorPickup(_vendor, context.read<PlacesService>());
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
    if (!requireCustomerAuth(context, message: 'Sign in to checkout')) return;
    if (_vendor.shopOpenStatus == 'closed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This shop is closed — check back when they reopen.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
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
          vendor: _vendor,
          pickup: pickup,
          cart: _cartProducts,
          onOrderPlaced: widget.onShopOrderPlaced,
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
    final v = _vendor;
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
          if (v.hasActiveStory && (v.shopStoryImage?.trim().isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _openShopDrop,
                  borderRadius: BorderRadius.circular(16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 9 / 16,
                          child: AppNetworkImage(
                            url: v.shopStoryImage!,
                            fit: BoxFit.cover,
                            semanticLabel: '${v.name} shop drop',
                          ),
                        ),
                        Positioned(
                          left: 12,
                          top: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'Shop Drop · tap to watch',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: VendorShopAvatar(
                    vendor: v,
                    size: 120,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          if (v.hasCustomerFacingPromo)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BytzGoTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: BytzGoTheme.accent.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.shopOpenStatus == 'closed'
                          ? 'This shop is closed right now'
                          : 'Update from ${v.name}',
                      style: BytzGoTheme.sheetTitle(13),
                    ),
                    const SizedBox(height: 8),
                    v.promoBadgeRow(),
                  ],
                ),
              ),
            ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (v.phone != null && v.phone!.trim().isNotEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.phone, size: 18, color: BytzGoTheme.brandBlue),
                    label: Text(formatVendorPhone(v.phone)),
                    onPressed: () => callVendorPhone(v.phone),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.chat_bubble_outline, size: 18, color: BytzGoTheme.accent),
                  label: const Text('Chat'),
                  onPressed: () => openShopChatWithVendor(context, vendor: v),
                ),
                ActionChip(
                  avatar: const Icon(Icons.map, size: 18, color: BytzGoTheme.accentDark),
                  label: const Text('Open in Maps'),
                  onPressed: () => showVendorMapPicker(context, v),
                ),
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
