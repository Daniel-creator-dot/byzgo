import 'package:flutter/material.dart';

import '../../models/ride_service.dart';
import '../format.dart';
import '../theme.dart';

/// Gold-plated ride hub — Delivery, Okada, Keke (Pragia).
class RideHubWelcome extends StatelessWidget {
  const RideHubWelcome({
    super.key,
    required this.firstName,
    required this.balance,
    required this.selectedService,
    this.vendorMode = false,
    this.recommendedService,
    this.popularHere = false,
    this.onWallet,
  });

  final String firstName;
  final double balance;
  final RideServiceType selectedService;
  final bool vendorMode;
  final RideServiceType? recommendedService;
  final bool popularHere;
  final VoidCallback? onWallet;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0B0A07),
                Color(0xFF1A1408),
                Color(0xFF2A210C),
              ],
            ),
            border: Border.all(color: BytzGoTheme.gold.withValues(alpha: 0.55), width: 1.4),
            boxShadow: [
              BoxShadow(
                color: BytzGoTheme.gold.withValues(alpha: 0.28),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                right: -18,
                top: -28,
                child: Icon(
                  selectedService.icon,
                  size: 150,
                  color: BytzGoTheme.gold.withValues(alpha: 0.12),
                ),
              ),
              Positioned(
                left: -40,
                bottom: -50,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: BytzGoTheme.gold.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                vendorMode ? 'STORE DISPATCH' : 'BYTZGO DELIVERY',
                                style: const TextStyle(
                                  color: BytzGoTheme.goldBright,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.8,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                vendorMode
                                    ? 'Send packages\nfrom your shop'
                                    : 'Gold service,\n${firstName.trim().isEmpty ? 'welcome' : firstName}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  height: 1.05,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (onWallet != null)
                          Material(
                            color: BytzGoTheme.gold,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              onTap: onWallet,
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'WALLET',
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.8,
                                        color: Colors.black.withValues(alpha: 0.7),
                                      ),
                                    ),
                                    Text(
                                      formatCedisCompact(balance),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      vendorMode
                          ? 'Book a bike courier for shop-to-door deliveries.'
                          : selectedService.subtitle,
                      style: TextStyle(
                        color: BytzGoTheme.goldBright.withValues(alpha: 0.88),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _RideModeStrip(
          recommended: recommendedService ?? RideServiceType.package,
          popularHere: popularHere && !vendorMode,
        ),
      ],
    );
  }
}

class _RideModeStrip extends StatelessWidget {
  const _RideModeStrip({
    required this.recommended,
    required this.popularHere,
  });

  final RideServiceType recommended;
  final bool popularHere;

  @override
  Widget build(BuildContext context) {
    final order = [
      recommended,
      ...RideServiceType.values.where((t) => t != recommended),
    ];
    return Row(
      children: [
        for (var i = 0; i < order.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _ModeChip(
            icon: order[i].icon,
            label: order[i] == RideServiceType.package
                ? 'Delivery'
                : order[i] == RideServiceType.okada
                    ? 'Okada'
                    : 'Keke',
            sub: order[i] == RideServiceType.package
                ? 'Packages'
                : order[i] == RideServiceType.okada
                    ? 'Quick ride'
                    : 'Pragia',
            color: order[i] == RideServiceType.package
                ? BytzGoTheme.gold
                : order[i] == RideServiceType.okada
                    ? const Color(0xFF22C55E)
                    : const Color(0xFFF59E0B),
            popularHere: popularHere && order[i] == recommended,
          ),
        ],
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    this.popularHere = false,
  });

  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final bool popularHere;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: BytzGoTheme.sheetText,
                    ),
                  ),
                  Text(
                    popularHere ? 'Popular here' : sub,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: popularHere ? color : BytzGoTheme.sheetMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
