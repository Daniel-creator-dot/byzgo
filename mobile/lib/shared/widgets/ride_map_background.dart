import 'package:flutter/material.dart';

import '../theme.dart';

/// Stylized full-screen map (no API key) — Bolt/Uber dark map feel.
class RideMapBackground extends StatelessWidget {
  const RideMapBackground({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const CustomPaint(painter: _MapPainter()),
        if (child != null) child!,
      ],
    );
  }
}

class _MapPainter extends CustomPainter {
  const _MapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final land = Paint()..color = BytzGoTheme.mapLand;
    canvas.drawRect(Offset.zero & size, land);

    // Water band
    final water = Paint()..color = BytzGoTheme.mapWater;
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.62, size.width, size.height * 0.38),
      water,
    );

    // Road grid
    final road = Paint()
      ..color = BytzGoTheme.mapRoad
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    const spacing = 48.0;
    for (var x = -spacing; x < size.width + spacing; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height * 0.15, size.height), road);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), road);
    }

    // Main arteries
    final artery = Paint()
      ..color = BytzGoTheme.mapGrid
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.1, size.height * 0.35),
      Offset(size.width * 0.9, size.height * 0.55),
      artery,
    );
    canvas.drawLine(
      Offset(size.width * 0.55, 0),
      Offset(size.width * 0.45, size.height),
      artery,
    );

    // User pin area glow
    final center = Offset(size.width * 0.5, size.height * 0.42);
    final glow = Paint()
      ..color = BytzGoTheme.accent.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
    canvas.drawCircle(center, 56, glow);

    // Bike pin
    final pinOuter = Paint()..color = BytzGoTheme.sheetBg;
    canvas.drawCircle(center, 14, pinOuter);
    final pinInner = Paint()..color = BytzGoTheme.accent;
    canvas.drawCircle(center, 10, pinInner);

    // Subtle vignette
    final vignette = Rect.fromLTWH(0, 0, size.width, size.height);
    final gradient = RadialGradient(
      center: Alignment.center,
      radius: 1.1,
      colors: [
        Colors.transparent,
        Colors.black.withValues(alpha: 0.35),
      ],
    );
    canvas.drawRect(vignette, Paint()..shader = gradient.createShader(vignette));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Pulsing ring around rider position on map.
class MapPulseMarker extends StatefulWidget {
  const MapPulseMarker({super.key});

  @override
  State<MapPulseMarker> createState() => _MapPulseMarkerState();
}

class _MapPulseMarkerState extends State<MapPulseMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final t = _ctrl.value;
          final scale = 1 + t * 0.8;
          final opacity = (1 - t) * 0.5;
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: BytzGoTheme.accent.withValues(alpha: opacity),
                      width: 2,
                    ),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: BytzGoTheme.accent,
            shape: BoxShape.circle,
            border: Border.all(color: BytzGoTheme.sheetBg, width: 3),
            boxShadow: [
              BoxShadow(
                color: BytzGoTheme.accent.withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      );
  }
}

/// Decorative route line between two points (screen coords).
class MapRouteArc extends StatelessWidget {
  const MapRouteArc({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RoutePainter(),
      size: Size.infinite,
    );
  }
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(size.width * 0.32, size.height * 0.38);
    final end = Offset(size.width * 0.68, size.height * 0.52);
    final path = Path();
    path.moveTo(start.dx, start.dy);
    final mid = Offset(
      (start.dx + end.dx) / 2,
      (start.dy + end.dy) / 2 - 40,
    );
    path.quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);

    final paint = Paint()
      ..color = BytzGoTheme.accent
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);

    // Dots at ends
    canvas.drawCircle(start, 6, Paint()..color = BytzGoTheme.sheetBg);
    canvas.drawCircle(start, 4, Paint()..color = BytzGoTheme.accent);
    canvas.drawCircle(end, 6, Paint()..color = BytzGoTheme.sheetBg);
    canvas.drawCircle(end, 4, Paint()..color = BytzGoTheme.sheetText);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
