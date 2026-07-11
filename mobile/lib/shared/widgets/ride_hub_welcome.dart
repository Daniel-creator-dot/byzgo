import 'package:flutter/material.dart';

import '../../models/ride_service.dart';
import '../format.dart';
import '../theme.dart';

/// Premium ride hub header — Package, Okada, Keke (Pragia).
class RideHubWelcome extends StatelessWidget {
  const RideHubWelcome({
    super.key,
    required this.firstName,
    required this.balance,
    required this.selectedService,
    this.vendorMode = false,
    this.onWallet,
  });

  final String firstName;
  final double balance;
  final RideServiceType selectedService;
  final bool vendorMode;
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
                Color(0xFF0F172A),
                Color(0xFF1E3A5F),
                Color(0xFF0C4A6E),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: BytzGoTheme.brandBlue.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                right: -24,
                top: -20,
                child: Icon(
                  selectedService.icon,
                  size: 140,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
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
                                vendorMode ? 'STORE DISPATCH' : 'BYTZGO RIDE',
                                style: TextStyle(
                                  color: BytzGoTheme.accent.withValues(alpha: 0.95),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.6,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                vendorMode
                                    ? 'Send packages\nfrom your shop'
                                    : 'Move smarter,\n${firstName.trim().isEmpty ? 'rider' : firstName}',
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
                            color: BytzGoTheme.accent,
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
                                        color: BytzGoTheme.sheetText.withValues(alpha: 0.7),
                                      ),
                                    ),
                                    Text(
                                      formatCedisCompact(balance),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        color: BytzGoTheme.sheetText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      vendorMode
                          ? 'Book a bike courier for shop-to-door deliveries.'
                          : selectedService.subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
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
        const _RideModeStrip(),
      ],
    );
  }
}

class _RideModeStrip extends StatelessWidget {
  const _RideModeStrip();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ModeChip(
          icon: RideServiceType.package.icon,
          label: 'Package',
          sub: 'Courier',
          color: const Color(0xFF38BDF8),
        ),
        const SizedBox(width: 8),
        _ModeChip(
          icon: RideServiceType.okada.icon,
          label: 'Okada',
          sub: 'Quick ride',
          color: const Color(0xFF22C55E),
        ),
        const SizedBox(width: 8),
        _ModeChip(
          icon: RideServiceType.keke.icon,
          label: 'Keke',
          sub: 'Pragia',
          color: const Color(0xFFF59E0B),
        ),
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
  });

  final IconData icon;
  final String label;
  final String sub;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
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
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: BytzGoTheme.sheetText,
                    ),
                  ),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: BytzGoTheme.sheetMuted,
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
