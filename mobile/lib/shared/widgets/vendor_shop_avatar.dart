import 'package:flutter/material.dart';

import '../../models/vendor.dart';
import '../shop_categories.dart';
import 'app_network_image.dart';

/// Shop list / header image — Google photo URL or category icon fallback.
class VendorShopAvatar extends StatelessWidget {
  const VendorShopAvatar({
    super.key,
    required this.vendor,
    this.size = 56,
    this.categoryId,
    this.borderRadius,
  });

  final Vendor vendor;
  final double size;
  final String? categoryId;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final cat = ShopCategory.byId(
          ShopCategory.normalizeVendorCategory(
            categoryId ?? vendor.shopCategory,
          ),
        ) ??
        ShopCategory.ordered.first;
    final radius = borderRadius ?? BorderRadius.circular(size * 0.25);
    final cover = vendor.coverImage?.trim();

    if (cover != null && cover.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: AppNetworkImage(
          url: cover,
          width: size,
          height: size,
          fit: BoxFit.cover,
          semanticLabel: '${vendor.name} photo',
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          colors: [
            cat.accent.withValues(alpha: 0.22),
            cat.accent.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Icon(cat.icon, color: cat.accent, size: size * 0.5),
    );
  }
}
