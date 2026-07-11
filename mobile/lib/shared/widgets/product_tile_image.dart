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
    if (shop == 'pharmacy' || shop == 'health') return true;
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

  static const String pharmacyPillAsset = 'assets/branding/pharmacy_pill.png';

  static IconData placeholderIcon(Vendor vendor, Product product) {
    if (isPharmacyContext(vendor, product)) {
      return Icons.medication_outlined;
    }
    final shop = ShopCategory.normalizeVendorCategory(vendor.shopCategory);
    if (shop == 'health') {
      return Icons.health_and_safety_outlined;
    }
    return Icons.local_pharmacy_outlined;
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
    final pharmacy = isPharmacyContext(vendor, product);

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
                errorBuilder: (_, __, ___) => _placeholder(pharmacy: pharmacy),
              )
            : _placeholder(pharmacy: pharmacy),
      ),
    );
  }

  Widget _placeholder({required bool pharmacy}) {
    if (pharmacy) {
      return Padding(
        padding: EdgeInsets.all(size * 0.12),
        child: Image.asset(
          pharmacyPillAsset,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _pharmacyIconFallback(),
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

  Widget _pharmacyIconFallback() {
    final tint = placeholderTint(vendor, product);
    return Center(
      child: Icon(
        Icons.medication_outlined,
        color: tint,
        size: size * 0.44,
      ),
    );
  }
}
