import 'package:flutter/material.dart';

import '../../models/vendor.dart';
import '../../shared/shop_categories.dart';
import '../theme.dart';
import 'app_network_image.dart';

/// WhatsApp-style story ring around a shop avatar.
class VendorStoryRing extends StatelessWidget {
  const VendorStoryRing({
    super.key,
    required this.vendor,
    required this.unseen,
    this.size = 72,
    this.onTap,
  });

  final Vendor vendor;
  final bool unseen;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cat = ShopCategory.byId(
          ShopCategory.normalizeVendorCategory(vendor.shopCategory),
        ) ??
        ShopCategory.ordered.first;
    final ringColors = unseen
        ? [BytzGoTheme.accent, const Color(0xFFA855F7), const Color(0xFF38BDF8)]
        : [Colors.white38, Colors.white24];

    final child = Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: ringColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: BytzGoTheme.sheetBg,
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.all(2),
        child: ClipOval(
          child: _thumb(cat),
        ),
      ),
    );

    if (onTap == null) return child;
    return GestureDetector(onTap: onTap, child: child);
  }

  Widget _thumb(ShopCategory cat) {
    final story = vendor.shopStoryImage?.trim();
    if (story != null && story.isNotEmpty) {
      return AppNetworkImage(
        url: story,
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: '${vendor.name} shop drop',
      );
    }
    final cover = vendor.coverImage?.trim();
    if (cover != null && cover.isNotEmpty) {
      return AppNetworkImage(
        url: cover,
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: vendor.name,
      );
    }
    return Container(
      color: cat.accent.withValues(alpha: 0.15),
      child: Icon(cat.icon, color: cat.accent, size: size * 0.4),
    );
  }
}
