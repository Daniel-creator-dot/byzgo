import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../models/vendor.dart';
import '../shop_categories.dart';
import '../theme.dart';

/// Product thumbnail — shop-aware placeholder (no food icon on medicine).
class ProductTileImage extends StatelessWidget {
  const ProductTileImage({
    super.key,
    required this.vendor,
    required this.product,
    this.size = 72,
  });

  final Vendor vendor;
  final Product product;
  final double size;

  static bool isPrimeCareVendor(Vendor vendor) {
    final n = vendor.name.trim().toLowerCase();
    return n.contains('primecare') || n.contains('prime care');
  }

  static bool isPharmacyContext(Vendor vendor, Product product) {
    final shop = ShopCategory.normalizeVendorCategory(vendor.shopCategory);
    if (shop == 'pharmacy') return true;
    if (isPrimeCareVendor(vendor)) return true;
    final cat = '${product.category ?? ''} ${product.name}'.toLowerCase();
    const keys = [
      'pharm',
      'medic',
      'drug',
      'capsule',
      'tablet',
      'syrup',
      'injection',
      'analges',
      'antibiotic',
      'antidiarr',
      'vitamin',
      'mg',
      'ml ',
    ];
    return keys.any(cat.contains);
  }

  static IconData placeholderIcon(Vendor vendor, Product product) {
    if (isPharmacyContext(vendor, product)) {
      return Icons.medication_liquid_outlined;
    }
    final shop = ShopCategory.normalizeVendorCategory(vendor.shopCategory);
    switch (shop) {
      case 'groceries':
        return Icons.shopping_basket_outlined;
      case 'fashion':
        return Icons.checkroom_outlined;
      case 'food':
        return Icons.restaurant_outlined;
      default:
        final cat = (product.category ?? '').toLowerCase();
        if (cat.contains('drink')) return Icons.local_drink_outlined;
        return Icons.inventory_2_outlined;
    }
  }

  static Color placeholderTint(Vendor vendor, Product product) {
    if (isPharmacyContext(vendor, product)) {
      return const Color(0xFF0EA5E9);
    }
    return ShopCategory.byId(ShopCategory.normalizeVendorCategory(vendor.shopCategory))
            ?.accent ??
        BytzGoTheme.accentDark;
  }

  @override
  Widget build(BuildContext context) {
    final url = product.imageUrl?.trim();
    final useLogo = isPrimeCareVendor(vendor) &&
        (url == null || url.isEmpty);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: size,
        height: size,
        color: placeholderTint(vendor, product).withValues(alpha: 0.1),
        child: url != null && url.isNotEmpty
            ? Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(useLogo: useLogo),
              )
            : _placeholder(useLogo: useLogo),
      ),
    );
  }

  Widget _placeholder({required bool useLogo}) {
    if (useLogo) {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: Image.asset(
          'assets/branding/primecare_logo.png',
          fit: BoxFit.contain,
        ),
      );
    }
    final tint = placeholderTint(vendor, product);
    return Center(
      child: Icon(
        placeholderIcon(vendor, product),
        color: tint,
        size: size * 0.42,
      ),
    );
  }
}
