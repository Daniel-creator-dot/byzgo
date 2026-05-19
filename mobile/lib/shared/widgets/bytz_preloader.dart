import 'package:flutter/material.dart';

import '../theme.dart';

/// Branded splash / loading screen using `assets/branding/preloader.png`.
class BytzPreloader extends StatefulWidget {
  const BytzPreloader({
    super.key,
    this.message,
    this.showSpinner = true,
  });

  final String? message;
  final bool showSpinner;

  @override
  State<BytzPreloader> createState() => _BytzPreloaderState();
}

class _BytzPreloaderState extends State<BytzPreloader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final logoWidth = (width * 0.62).clamp(200.0, 320.0);

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: Image.asset(
                'assets/branding/preloader.png',
                width: logoWidth,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            if (widget.showSpinner) ...[
              const SizedBox(height: 32),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: BytzGoTheme.accent,
                ),
              ),
            ],
            if (widget.message != null) ...[
              const SizedBox(height: 16),
              Text(
                widget.message!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full-screen overlay for in-app actions (login, submit, etc.).
class BytzPreloaderOverlay extends StatelessWidget {
  const BytzPreloaderOverlay({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: BytzPreloader(message: message, showSpinner: true),
    );
  }
}
