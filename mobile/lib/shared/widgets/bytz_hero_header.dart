import 'package:flutter/material.dart';

import '../theme.dart';

/// Branded hero banner (admin-style) for customer, rider, vendor tabs.
class BytzHeroHeader extends StatelessWidget {
  const BytzHeroHeader({
    super.key,
    required this.kicker,
    required this.title,
    required this.assetPath,
    this.trailing,
    this.height = 128,
    this.dark = true,
  });

  final String kicker;
  final String title;
  final String assetPath;
  final Widget? trailing;
  final double height;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final overlay = dark
        ? [
            const Color(0xFF020617).withValues(alpha: 0.95),
            const Color(0xFF020617).withValues(alpha: 0.55),
            const Color(0xFF020617).withValues(alpha: 0.15),
          ]
        : [
            Colors.white.withValues(alpha: 0.92),
            Colors.white.withValues(alpha: 0.72),
            Colors.white.withValues(alpha: 0.35),
          ];

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: BytzGoTheme.brandBlue.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(assetPath, fit: BoxFit.cover, alignment: Alignment.centerRight),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: overlay,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          kicker.toUpperCase(),
                          style: TextStyle(
                            color: dark ? BytzGoTheme.accent : BytzGoTheme.brandBlue,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          style: TextStyle(
                            color: dark ? Colors.white : BytzGoTheme.sheetText,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
