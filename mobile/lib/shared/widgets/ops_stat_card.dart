import 'package:flutter/material.dart';

import '../theme.dart';

/// KPI tile — dark (admin) or light (customer/vendor) variant.
class OpsStatCard extends StatelessWidget {
  const OpsStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent = BytzGoTheme.accent,
    this.subtitle,
    this.light = false,
    this.width,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final String? subtitle;
  final bool light;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final bg = light
        ? [
            BytzGoTheme.sheetBg,
            accent.withValues(alpha: 0.06),
          ]
        : [
            const Color(0xFF0F172A),
            accent.withValues(alpha: 0.08),
          ];
    final valueColor = light ? BytzGoTheme.sheetText : Colors.white;
    final labelColor = light
        ? BytzGoTheme.sheetMuted
        : Colors.white.withValues(alpha: 0.45);

    return SizedBox(
      width: width ?? 118,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: bg,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: light ? 0.35 : 0.25)),
          boxShadow: light
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: labelColor,
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: TextStyle(
                  color: accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
