import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/theme.dart';

/// Soft wave along the top edge of the login sheet (connects to hero).
class AuthSheetTopWave extends StatelessWidget {
  const AuthSheetTopWave({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      width: double.infinity,
      child: CustomPaint(
        painter: _SheetTopWavePainter(),
      ),
    );
  }
}

class _SheetTopWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = BytzGoTheme.sheetBg;
    final accent = Paint()
      ..shader = LinearGradient(
        colors: [
          BytzGoTheme.brandBlue.withValues(alpha: 0.35),
          BytzGoTheme.accent.withValues(alpha: 0.45),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 6))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(0, 14)
      ..cubicTo(
        size.width * 0.22,
        2,
        size.width * 0.38,
        20,
        size.width * 0.55,
        8,
      )
      ..cubicTo(
        size.width * 0.72,
        -2,
        size.width * 0.88,
        18,
        size.width,
        10,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, fill);

    final line = Path()
      ..moveTo(0, 12)
      ..cubicTo(
        size.width * 0.25,
        4,
        size.width * 0.5,
        16,
        size.width * 0.75,
        6,
      )
      ..cubicTo(size.width * 0.92, 0, size.width, 10, size.width, 8);
    canvas.drawPath(line, accent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Rounded icon in a gradient circle (fields, headers, hero).
class AuthRoundedIcon extends StatelessWidget {
  const AuthRoundedIcon({
    super.key,
    required this.icon,
    this.size = 40,
    this.tint,
    this.filled = true,
  });

  final IconData icon;
  final double size;
  final Color? tint;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final iconColor = tint ?? BytzGoTheme.brandBlue;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: filled
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  iconColor.withValues(alpha: 0.14),
                  BytzGoTheme.accent.withValues(alpha: 0.22),
                ],
              )
            : null,
        color: filled ? null : Colors.white,
        border: Border.all(
          color: iconColor.withValues(alpha: 0.28),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: iconColor.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        icon,
        size: size * 0.48,
        color: iconColor,
      ),
    );
  }
}

/// Three linked rounded icons under the sheet title (visual “flow”).
class AuthHeaderIconFlow extends StatelessWidget {
  const AuthHeaderIconFlow({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _IconFlowWirePainter(),
            ),
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              AuthRoundedIcon(icon: Icons.two_wheeler_rounded, size: 38),
              AuthRoundedIcon(
                icon: Icons.pin_drop_rounded,
                size: 42,
                tint: BytzGoTheme.brandBlueBright,
              ),
              AuthRoundedIcon(icon: Icons.shield_rounded, size: 38),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconFlowWirePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final y = size.height * 0.52;
    final x0 = size.width * 0.18;
    final x1 = size.width * 0.5;
    final x2 = size.width * 0.82;

    void wire(Color c, double phase) {
      paint.color = c.withValues(alpha: 0.45);
      final path = Path()
        ..moveTo(x0, y + math.sin(phase) * 4)
        ..quadraticBezierTo(
          (x0 + x1) / 2,
          y - 14,
          x1,
          y + math.cos(phase) * 3,
        )
        ..quadraticBezierTo(
          (x1 + x2) / 2,
          y + 14,
          x2,
          y + math.sin(phase + 1) * 4,
        );
      canvas.drawPath(path, paint);
    }

    wire(BytzGoTheme.brandBlue, 0);
    paint.strokeWidth = 1.2;
    paint.color = BytzGoTheme.accent.withValues(alpha: 0.35);
    final wave = Path()
      ..moveTo(size.width * 0.08, y + 8)
      ..cubicTo(
        size.width * 0.35,
        y - 6,
        size.width * 0.65,
        y + 10,
        size.width * 0.92,
        y - 4,
      );
    canvas.drawPath(wave, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Vertical wave connector between form blocks (e.g. sign-in → Google).
class AuthSectionWaveLink extends StatelessWidget {
  const AuthSectionWaveLink({super.key, this.height = 28});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: height,
            child: CustomPaint(
              painter: _VerticalWaveLinkPainter(),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    BytzGoTheme.brandBlue.withValues(alpha: 0.25),
                    BytzGoTheme.accent.withValues(alpha: 0.15),
                    BytzGoTheme.sheetDivider.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalWaveLinkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    paint.color = BytzGoTheme.brandBlue.withValues(alpha: 0.4);
    final path = Path()
      ..moveTo(cx, 0)
      ..cubicTo(cx - 10, size.height * 0.35, cx + 10, size.height * 0.65, cx, size.height);
    canvas.drawPath(path, paint);

    paint.color = BytzGoTheme.accent.withValues(alpha: 0.5);
    canvas.drawCircle(Offset(cx, 0), 4, Paint()..color = BytzGoTheme.brandBlue.withValues(alpha: 0.35));
    canvas.drawCircle(Offset(cx, size.height), 4, Paint()..color = BytzGoTheme.accent.withValues(alpha: 0.45));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Bridge wave between dark hero and light sheet (sits above sheet).
class AuthHeroSheetBridge extends StatelessWidget {
  const AuthHeroSheetBridge({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: 36,
        width: double.infinity,
        child: CustomPaint(
          painter: _HeroBridgePainter(),
        ),
      ),
    );
  }
}

class _HeroBridgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grad = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          BytzGoTheme.sheetBg.withValues(alpha: 0.85),
          BytzGoTheme.sheetBg,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), grad);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = BytzGoTheme.accent.withValues(alpha: 0.55)
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(0, size.height * 0.55)
      ..quadraticBezierTo(size.width * 0.3, size.height * 0.2, size.width * 0.5, size.height * 0.5)
      ..quadraticBezierTo(size.width * 0.75, size.height * 0.85, size.width, size.height * 0.45);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
