import 'package:flutter/material.dart';

import '../theme.dart';

/// Classy pharmacy hub hero — trusted care, drug search, confirm-then-deliver.
class PharmacyHubWelcome extends StatelessWidget {
  const PharmacyHubWelcome({
    super.key,
    required this.categoryLabel,
    required this.openCount,
    required this.listedCount,
    this.onSearchTap,
  });

  final String categoryLabel;
  final int openCount;
  final int listedCount;
  final VoidCallback? onSearchTap;

  static const _imagePath = 'assets/branding/pharmacy_hub_welcome.png';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Image.asset(
                  _imagePath,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFF0F766E),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.local_pharmacy_rounded,
                      size: 64,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.55),
                        const Color(0xFF0F172A).withValues(alpha: 0.92),
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_rounded, size: 14, color: Color(0xFF6EE7B7)),
                          SizedBox(width: 6),
                          Text(
                            'Licensed pharmacies · Chat before you buy',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      categoryLabel,
                      style: const TextStyle(
                        color: Color(0xFF99F6E4),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Your health,\ndelivered with care',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1.08,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Search medicines, chat with a pharmacist, and get confirmed orders delivered by a trusted rider.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _StatPill(
              icon: Icons.storefront_rounded,
              label: '$openCount open',
              accent: const Color(0xFF14B8A6),
            ),
            const SizedBox(width: 8),
            _StatPill(
              icon: Icons.medication_liquid_rounded,
              label: '$listedCount listed',
              accent: BytzGoTheme.brandBlue,
            ),
            const Spacer(),
            if (onSearchTap != null)
              TextButton.icon(
                onPressed: onSearchTap,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Find medicine'),
                style: TextButton.styleFrom(
                  foregroundColor: BytzGoTheme.brandBlue,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        _FlowStrip(),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: accent.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.search_rounded, 'Search'),
      (Icons.chat_bubble_outline_rounded, 'Chat'),
      (Icons.check_circle_outline_rounded, 'Confirm'),
      (Icons.two_wheeler_rounded, 'Deliver'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            BytzGoTheme.brandBlue.withValues(alpha: 0.06),
            BytzGoTheme.accent.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BytzGoTheme.sheetDivider.withValues(alpha: 0.8)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        BytzGoTheme.brandBlue.withValues(alpha: 0.25),
                        BytzGoTheme.accent.withValues(alpha: 0.35),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: BytzGoTheme.brandBlue.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(steps[i].$1, size: 16, color: BytzGoTheme.brandBlue),
                ),
                const SizedBox(height: 4),
                Text(
                  steps[i].$2,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: BytzGoTheme.sheetMuted,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
