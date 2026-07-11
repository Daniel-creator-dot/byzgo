import 'package:flutter/material.dart';

/// Pharmacy & health retail types for vendor listings.
class ShopCategory {
  const ShopCategory({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color accent;

  static const List<ShopCategory> ordered = [
    ShopCategory(
      id: 'pharmacy',
      label: 'Pharmacy',
      subtitle: 'Licensed pharmacies — medicines & OTC',
      icon: Icons.local_pharmacy_outlined,
      accent: Color(0xFF0EA5E9),
    ),
    ShopCategory(
      id: 'health',
      label: 'Health retail',
      subtitle: 'Supplements, medical supplies & wellness',
      icon: Icons.health_and_safety_outlined,
      accent: Color(0xFF10B981),
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

  static String labelFor(String? id) => byId(id)?.label ?? 'Pharmacy';

  static String normalizeVendorCategory(String? raw) {
    final c = byId(raw);
    return c?.id ?? 'pharmacy';
  }

  static bool isHealthMarketplace(String? id) {
    final c = byId(id);
    return c != null;
  }
}
