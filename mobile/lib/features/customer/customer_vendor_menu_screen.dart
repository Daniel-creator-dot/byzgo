import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/location_point.dart';
import '../../models/product.dart';
import '../../models/vendor.dart';
import '../../shared/format.dart';
import '../../shared/rider_trip.dart';
import '../../shared/theme.dart';
import '../orders/orders_repository.dart';

/// Menu items for a single shop/vendor.
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
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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

  void _bookPickupFromShop() {
    final v = widget.vendor;
    if (v.lat == null ||
        v.lng == null ||
        !hasValidCoords(v.lat!, v.lng!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This shop has no map location yet'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final point = LocationPoint(
      address: v.address?.trim().isNotEmpty == true
          ? v.address!.trim()
          : v.name,
      lat: v.lat!,
      lng: v.lng!,
    );
    Navigator.of(context).pop();
    widget.onBookPickup?.call(point);
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

    return Scaffold(
      backgroundColor: BytzGoTheme.sheetBg,
      appBar: AppBar(
        backgroundColor: BytzGoTheme.sheetBg,
        foregroundColor: BytzGoTheme.sheetText,
        elevation: 0,
        title: Text(
          v.name,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
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
                  Expanded(
                    child: Text(
                      v.address!,
                      style: BytzGoTheme.sheetBody(13),
                    ),
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
                                style: const TextStyle(
                                  color: BytzGoTheme.danger,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: _load,
                                child: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _products.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No items listed for this shop yet.',
                                textAlign: TextAlign.center,
                                style: BytzGoTheme.sheetBody(14),
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                8,
                                16,
                                100,
                              ),
                              children: [
                                for (final entry in _byCategory.entries) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 8,
                                      bottom: 10,
                                    ),
                                    child: Text(
                                      entry.key,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        color: BytzGoTheme.sheetText,
                                      ),
                                    ),
                                  ),
                                  ...entry.value.map(
                                    (p) => _ProductTile(product: p),
                                  ),
                                ],
                              ],
                            ),
                          ),
          ),
        ],
      ),
      bottomNavigationBar: widget.onBookPickup == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _bookPickupFromShop,
                  icon: const Icon(Icons.delivery_dining),
                  label: const Text('Book delivery from this shop'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BytzGoTheme.brandBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
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
              _ProductImage(imageUrl: product.imageUrl),
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
                    if (product.description != null &&
                        product.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        product.description!,
                        maxLines: 3,
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
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 72,
        height: 72,
        color: BytzGoTheme.accent.withValues(alpha: 0.12),
        child: url != null && url.isNotEmpty
            ? Image.network(
                url,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _PlaceholderIcon(),
              )
            : const _PlaceholderIcon(),
      ),
    );
  }
}

class _PlaceholderIcon extends StatelessWidget {
  const _PlaceholderIcon();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.restaurant,
        color: BytzGoTheme.accentDark,
        size: 32,
      ),
    );
  }
}
