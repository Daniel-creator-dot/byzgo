import 'package:flutter/material.dart';

import '../theme.dart';

/// Official BytzGO wordmark (`assets/branding/app_logo.png`).
class BytzGoLogo extends StatelessWidget {
  const BytzGoLogo({
    super.key,
    this.fontSize = 36,
    this.alignment = Alignment.centerLeft,
  });

  final double fontSize;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Image.asset(
        'assets/branding/app_logo.png',
        height: fontSize * 1.35,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

/// Full-bleed branded photo with legibility gradient.
class BrandHeroBackground extends StatelessWidget {
  const BrandHeroBackground({
    super.key,
    this.asset = 'assets/branding/hero_login.png',
    this.child,
    this.bottomFade = 0.72,
  });

  final String asset;
  final Widget? child;
  final double bottomFade;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.medium,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.35),
                Colors.black.withValues(alpha: 0.5),
                Colors.black.withValues(alpha: bottomFade),
                BytzGoTheme.background,
              ],
              stops: const [0.0, 0.35, 0.62, 1.0],
            ),
          ),
        ),
        const _BrandGridOverlay(),
        if (child != null) child!,
      ],
    );
  }
}

/// Subtle tech grid from brand artwork.
class _BrandGridOverlay extends StatelessWidget {
  const _BrandGridOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GridPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()
      ..color = BytzGoTheme.brandBlue.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    final line = Paint()
      ..color = BytzGoTheme.brandBlue.withValues(alpha: 0.12)
      ..strokeWidth = 1;

    const step = 36.0;
    for (var x = 0.0; x < size.width; x += step) {
      for (var y = 0.0; y < size.height * 0.55; y += step) {
        canvas.drawCircle(Offset(x, y), 1.2, dot);
      }
    }
    for (var x = 0.0; x < size.width; x += step * 3) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height * 0.5), line);
    }
    for (var y = 0.0; y < size.height * 0.5; y += step * 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Compact promo strip for empty / onboarding states.
class BrandPromoBanner extends StatelessWidget {
  const BrandPromoBanner({
    super.key,
    this.asset = 'assets/branding/hero_delivery.png',
    this.title,
    this.subtitle,
  });

  final String asset;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 120,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(asset, fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: 0.75),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
