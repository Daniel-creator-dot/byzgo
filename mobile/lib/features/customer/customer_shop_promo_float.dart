import 'package:flutter/material.dart';

import '../../models/vendor.dart';
import '../../shared/theme.dart';

/// Floating strip of live vendor status + discounts on the Shops tab.
class CustomerShopPromoFloat extends StatelessWidget {
  const CustomerShopPromoFloat({
    super.key,
    required this.vendors,
    required this.onTapVendor,
  });

  final List<Vendor> vendors;
  final void Function(Vendor vendor) onTapVendor;

  List<Vendor> get _promoVendors {
    final list = vendors.where((v) => v.hasCustomerFacingPromo).toList();
    int rank(Vendor v) {
      if (v.shopDiscountLabel != null && v.shopDiscountLabel!.trim().isNotEmpty) {
        return 0;
      }
      if (v.shopOpenStatus == 'open' &&
          v.shopStatusMessage != null &&
          v.shopStatusMessage!.trim().isNotEmpty) {
        return 1;
      }
      if (v.shopOpenStatus == 'busy') return 2;
      if (v.shopOpenStatus == 'closed') return 4;
      return 3;
    }
    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final at = a.shopPromoUpdatedAt;
      final bt = b.shopPromoUpdatedAt;
      if (at != null && bt != null) return bt.compareTo(at);
      return a.name.compareTo(b.name);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final promos = _promoVendors;
    if (promos.isEmpty) return const SizedBox.shrink();

    return Material(
      elevation: 8,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      color: BytzGoTheme.sheetBg,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BytzGoTheme.accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  Icon(Icons.notifications_active_outlined,
                      size: 18, color: BytzGoTheme.accent),
                  const SizedBox(width: 6),
                  Text(
                    'Live from shops',
                    style: BytzGoTheme.sheetTitle(13).copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                itemCount: promos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final v = promos[i];
                  return _PromoChip(vendor: v, onTap: () => onTapVendor(v));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromoChip extends StatelessWidget {
  const _PromoChip({required this.vendor, required this.onTap});

  final Vendor vendor;
  final VoidCallback onTap;

  Color get _accent {
    if (vendor.shopDiscountLabel != null && vendor.shopDiscountLabel!.trim().isNotEmpty) {
      return const Color(0xFF16A34A);
    }
    switch (vendor.shopOpenStatus) {
      case 'busy':
        return const Color(0xFFF59E0B);
      case 'closed':
        return BytzGoTheme.danger;
      default:
        return BytzGoTheme.brandBlue;
    }
  }

  String get _headline {
    if (vendor.shopDiscountLabel != null && vendor.shopDiscountLabel!.trim().isNotEmpty) {
      return vendor.shopDiscountLabel!.trim();
    }
    if (vendor.shopStatusMessage != null && vendor.shopStatusMessage!.trim().isNotEmpty) {
      return vendor.shopStatusMessage!.trim();
    }
    return vendor.promo.openStatusLabel;
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              vendor.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: BytzGoTheme.sheetText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _headline,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent,
                height: 1.2,
              ),
            ),
            const Spacer(),
            Text(
              vendor.promo.openStatusLabel,
              style: TextStyle(fontSize: 10, color: BytzGoTheme.sheetMuted),
            ),
          ],
        ),
      ),
    );
  }
}
