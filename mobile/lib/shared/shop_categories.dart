import 'package:flutter/material.dart';

/// Marketplace shop types for vendor listings (matches server SHOP_CATEGORIES).
class ShopCategory {
  const ShopCategory({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.accent,
    this.markerHue = 210,
  });

  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final double markerHue;

  static const all = ShopCategory(
    id: 'all',
    label: 'All shops',
    subtitle: 'Every approved store on BytzGo',
    icon: Icons.storefront_outlined,
    accent: Color(0xFFD4AF37),
    markerHue: 45,
  );

  static const List<ShopCategory> marketplace = [
    ShopCategory(
      id: 'pharmacy',
      label: 'Pharmacy',
      subtitle: 'Licensed pharmacies — medicines & OTC',
      icon: Icons.local_pharmacy_outlined,
      accent: Color(0xFF0EA5E9),
      markerHue: 210,
    ),
    ShopCategory(
      id: 'health',
      label: 'Health',
      subtitle: 'Supplements, medical supplies & wellness',
      icon: Icons.health_and_safety_outlined,
      accent: Color(0xFF10B981),
      markerHue: 120,
    ),
    ShopCategory(
      id: 'food',
      label: 'Food',
      subtitle: 'Kitchens, bakeries & packaged meals',
      icon: Icons.restaurant_outlined,
      accent: Color(0xFFF97316),
      markerHue: 30,
    ),
    ShopCategory(
      id: 'restaurant',
      label: 'Restaurant',
      subtitle: 'Sit-down and takeaway restaurants',
      icon: Icons.dinner_dining_outlined,
      accent: Color(0xFFEF4444),
      markerHue: 0,
    ),
    ShopCategory(
      id: 'groceries',
      label: 'Groceries',
      subtitle: 'Markets, provisions & daily items',
      icon: Icons.shopping_basket_outlined,
      accent: Color(0xFF22C55E),
      markerHue: 90,
    ),
    ShopCategory(
      id: 'fashion',
      label: 'Fashion',
      subtitle: 'Clothes, shoes & accessories',
      icon: Icons.checkroom_outlined,
      accent: Color(0xFFA855F7),
      markerHue: 270,
    ),
  ];

  /// Browse chips: All + each marketplace type.
  static List<ShopCategory> get ordered => [all, ...marketplace];

  /// Admin / vendor pickers (no All).
  static List<ShopCategory> get assignable => marketplace;

  static ShopCategory? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    final key = id.trim().toLowerCase();
    if (key == all.id) return all;
    for (final c in marketplace) {
      if (c.id == key) return c;
    }
    return null;
  }

  static String labelFor(String? id) => byId(id)?.label ?? 'Shop';

  static String normalizeVendorCategory(String? raw) {
    final c = byId(raw);
    if (c == null || c.id == all.id) return 'pharmacy';
    return c.id;
  }

  static bool isHealthMarketplace(String? id) {
    final key = (id ?? '').trim().toLowerCase();
    return key == 'pharmacy' || key == 'health';
  }

  static double hueFor(String? id) => byId(id)?.markerHue ?? 45;
}
