import 'package:flutter/material.dart';

/// Shop types for vendor listings (order = browse tabs).
class ShopCategory {
  const ShopCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color accent;

  static const List<ShopCategory> ordered = [
    ShopCategory(
      id: 'pharmacy',
      label: 'Pharmacy',
      icon: Icons.medical_services_outlined,
      accent: Color(0xFF0EA5E9),
    ),
    ShopCategory(
      id: 'food',
      label: 'Food & Drinks',
      icon: Icons.local_cafe_outlined,
      accent: Color(0xFFF59E0B),
    ),
    ShopCategory(
      id: 'restaurant',
      label: 'Restaurants',
      icon: Icons.restaurant_outlined,
      accent: Color(0xFFEF4444),
    ),
    ShopCategory(
      id: 'fashion',
      label: 'Fashion',
      icon: Icons.checkroom_outlined,
      accent: Color(0xFFA855F7),
    ),
    ShopCategory(
      id: 'groceries',
      label: 'Groceries',
      icon: Icons.shopping_basket_outlined,
      accent: Color(0xFF22C55E),
    ),
  ];

  static ShopCategory? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    final key = id.trim().toLowerCase();
    for (final c in ordered) {
      if (c.id == key) return c;
    }
    return null;
  }

  static String labelFor(String? id) => byId(id)?.label ?? 'Food & Drinks';

  static String normalizeVendorCategory(String? raw) {
    final c = byId(raw);
    return c?.id ?? 'food';
  }
}
