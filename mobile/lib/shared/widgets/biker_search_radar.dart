import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/location_point.dart';
import '../theme.dart';

/// Pulsing search radar — status card icon or map overlay center.
class BikerSearchRadar extends StatefulWidget {
  const BikerSearchRadar({
    super.key,
    this.size = 48,
    this.color = BytzGoTheme.brandBlue,
    this.showIcon = true,
  });

  final double size;
  final Color color;
  final bool showIcon;

  @override
  State<BikerSearchRadar> createState() => _BikerSearchRadarState();
}

class _BikerSearchRadarState extends State<BikerSearchRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(widget.size),
                painter: _RadarPainter(
                  progress: _ctrl.value,
                  color: widget.color,
                ),
              ),
              if (widget.showIcon)
                Icon(
                  Icons.radar,
                  size: widget.size * 0.38,
                  color: BytzGoTheme.sheetBg,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide / 2;

    for (var i = 0; i < 3; i++) {
      final t = (progress + i * 0.33) % 1.0;
      final r = maxR * (0.35 + t * 0.65);
      final opacity = (1 - t) * 0.55;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Sweep wedge
    final sweep = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          color.withValues(alpha: 0.35),
          color.withValues(alpha: 0.02),
          color.withValues(alpha: 0.02),
        ],
        stops: const [0, 0.25, 1],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(Rect.fromCircle(center: center, radius: maxR));
    canvas.drawCircle(center, maxR * 0.92, sweep);

    canvas.drawCircle(
      center,
      maxR * 0.22,
      Paint()..color = BytzGoTheme.sheetBg,
    );
    canvas.drawCircle(
      center,
      maxR * 0.16,
      Paint()..color = color.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Full-map overlay: radar at pickup + animated nearby biker pins (fallback map).
class MapBikerSearchOverlay extends StatefulWidget {
  const MapBikerSearchOverlay({
    super.key,
    required this.centerLat,
    required this.centerLng,
    required this.nearbyRiders,
    this.showRadar = true,
  });

  final double centerLat;
  final double centerLng;
  final List<LocationPoint> nearbyRiders;
  final bool showRadar;

  @override
  State<MapBikerSearchOverlay> createState() => _MapBikerSearchOverlayState();
}

class _MapBikerSearchOverlayState extends State<MapBikerSearchOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob;

  @override
  void initState() {
    super.initState();
    _bob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  Offset _toScreen(double lat, double lng, Size size) {
    const anchorY = 0.42;
    final dLat = lat - widget.centerLat;
    final dLng = lng - widget.centerLng;
    // ~1° lat ≈ 111km; scale to map viewport
    final scale = size.shortestSide * 4.2;
    final x = size.width * 0.5 + dLng * scale;
    final y = size.height * anchorY - dLat * scale;
    return Offset(
      x.clamp(28.0, size.width - 28),
      y.clamp(size.height * 0.12, size.height * 0.58),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final center = _toScreen(widget.centerLat, widget.centerLng, size);

        return AnimatedBuilder(
          animation: _bob,
          builder: (context, _) {
            final bob = 2 + _bob.value * 3;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (widget.showRadar)
                  Positioned(
                    left: center.dx - 72,
                    top: center.dy - 72 + bob * 0.2,
                    child: const BikerSearchRadar(size: 144, showIcon: false),
                  ),
                ...widget.nearbyRiders.asMap().entries.map((e) {
                  final r = e.value;
                  final pos = _toScreen(r.lat, r.lng, size);
                  return Positioned(
                    left: pos.dx - 18,
                    top: pos.dy - 18 - bob * (0.4 + (e.key % 3) * 0.15),
                    child: _NearbyBikerPin(index: e.key),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }
}

class _NearbyBikerPin extends StatelessWidget {
  const _NearbyBikerPin({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1),
      duration: Duration(milliseconds: 400 + (index % 4) * 120),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: BytzGoTheme.sheetBg,
          shape: BoxShape.circle,
          border: Border.all(color: BytzGoTheme.accent, width: 2),
          boxShadow: [
            BoxShadow(
              color: BytzGoTheme.accent.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(
          Icons.two_wheeler,
          size: 20,
          color: BytzGoTheme.accentDark,
        ),
      ),
    );
  }
}
