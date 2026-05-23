import 'package:flutter/material.dart';

import '../../models/vendor.dart';
import '../../models/vendor_shop_promo.dart';
import '../theme.dart';

/// Status + discount chips on vendor cards and menus.
class VendorPromoBadgeRow extends StatelessWidget {
  const VendorPromoBadgeRow({
    super.key,
    required this.promo,
    this.compact = false,
  });

  final VendorShopPromo promo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    final statusColor = _statusColor(promo.shopOpenStatus);
    chips.add(_chip(
      promo.openStatusLabel,
      statusColor,
      Icons.circle,
      compact: compact,
    ));
    if (promo.shopDiscountLabel != null && promo.shopDiscountLabel!.trim().isNotEmpty) {
      chips.add(_chip(
        promo.shopDiscountLabel!.trim(),
        const Color(0xFF16A34A),
        Icons.local_offer_outlined,
        compact: compact,
      ));
    } else if (promo.shopDiscountPercent != null && promo.shopDiscountPercent! > 0) {
      chips.add(_chip(
        '${promo.shopDiscountPercent!.toStringAsFixed(promo.shopDiscountPercent! % 1 == 0 ? 0 : 1)}% off',
        const Color(0xFF16A34A),
        Icons.local_offer_outlined,
        compact: compact,
      ));
    }
    if (promo.shopStatusMessage != null && promo.shopStatusMessage!.trim().isNotEmpty) {
      chips.add(_chip(
        promo.shopStatusMessage!.trim(),
        BytzGoTheme.brandBlue,
        Icons.campaign_outlined,
        compact: compact,
        maxWidth: compact ? 140 : 200,
      ));
    }
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'busy':
        return const Color(0xFFF59E0B);
      case 'closed':
        return BytzGoTheme.danger;
      default:
        return const Color(0xFF16A34A);
    }
  }

  Widget _chip(
    String label,
    Color color,
    IconData icon, {
    bool compact = false,
    double? maxWidth,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 9,
          vertical: compact ? 3 : 4,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 11 : 13, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension VendorPromoBadge on Vendor {
  Widget promoBadgeRow({bool compact = false}) =>
      VendorPromoBadgeRow(promo: promo, compact: compact);
}
