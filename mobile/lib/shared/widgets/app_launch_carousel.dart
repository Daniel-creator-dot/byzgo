import 'dart:async';

import 'package:flutter/material.dart';

import '../responsive_layout.dart';
import '../theme.dart';
import 'bytz_brand.dart';

class _LaunchSlide {
  const _LaunchSlide({
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  final String asset;
  final String title;
  final String subtitle;
  final Color accent;
}

/// Opening experience — brand carousel + loader while the app boots.
class AppLaunchCarousel extends StatefulWidget {
  const AppLaunchCarousel({
    super.key,
    this.message = 'Getting things ready…',
  });

  final String message;

  static const _slides = [
    _LaunchSlide(
      asset: 'assets/branding/onboarding_rider.png',
      title: 'Smart moves',
      subtitle: 'Fast bike delivery across your city',
      accent: BytzGoTheme.brandBlue,
    ),
    _LaunchSlide(
      asset: 'assets/branding/onboarding_delivery.png',
      title: 'Handed with care',
      subtitle: 'Track every trip live from pickup to door',
      accent: BytzGoTheme.accent,
    ),
    _LaunchSlide(
      asset: 'assets/branding/onboarding_team.png',
      title: 'Powered by people',
      subtitle: 'Riders, shops & support — one sharp app',
      accent: BytzGoTheme.brandBlue,
    ),
  ];

  @override
  State<AppLaunchCarousel> createState() => _AppLaunchCarouselState();
}

class _AppLaunchCarouselState extends State<AppLaunchCarousel>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  int _page = 0;
  Timer? _autoTimer;
  late final AnimationController _loaderSpin;
  late final AnimationController _loaderPulse;

  @override
  void initState() {
    super.initState();
    _loaderSpin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _loaderPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      _autoTimer?.cancel();
      _autoTimer = null;
      if (_loaderSpin.isAnimating) _loaderSpin.stop();
      if (_loaderPulse.isAnimating) _loaderPulse.stop();
      return;
    }
    if (!_loaderSpin.isAnimating) _loaderSpin.repeat();
    if (!_loaderPulse.isAnimating) _loaderPulse.repeat(reverse: true);
    _autoTimer ??= Timer.periodic(const Duration(milliseconds: 3400), (_) {
      if (!_pageController.hasClients) return;
      final next = (_page + 1) % AppLaunchCarousel._slides.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageController.dispose();
    _loaderSpin.dispose();
    _loaderPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Material(
      color: BytzGoTheme.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _AmbientGlow(),
          SafeArea(
            child: BytzLayout.constrainContent(
              context,
              maxWidth: BytzLayout.phoneContentMaxWidth,
              fillHeight: true,
              child: Column(
              children: [
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: BytzGoLogo(fontSize: 34),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemCount: AppLaunchCarousel._slides.length,
                    itemBuilder: (context, index) {
                      return _SlideCard(
                        slide: AppLaunchCarousel._slides[index],
                        active: index == _page,
                      );
                    },
                  ),
                ),
                _PageDots(count: AppLaunchCarousel._slides.length, index: _page),
                const SizedBox(height: 20),
                _BytzGoLaunchLoader(
                  spin: _loaderSpin,
                  pulse: _loaderPulse,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.message,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: 16 + bottomPad),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    BytzGoTheme.brandBlue.withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 120,
            left: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    BytzGoTheme.accent.withValues(alpha: 0.28),
                    Colors.transparent,
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

class _SlideCard extends StatelessWidget {
  const _SlideCard({required this.slide, required this.active});

  final _LaunchSlide slide;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: active ? 1.0 : 0.94,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: slide.accent.withValues(alpha: active ? 0.55 : 0.2),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: slide.accent.withValues(alpha: 0.25),
                      blurRadius: active ? 28 : 12,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      slide.asset,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      filterQuality: FilterQuality.high,
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.15),
                            Colors.black.withValues(alpha: 0.75),
                          ],
                          stops: const [0.35, 0.65, 1.0],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _CaptionPanel(slide: slide),
          ],
        ),
      ),
    );
  }
}

class _CaptionPanel extends StatelessWidget {
  const _CaptionPanel({required this.slide});

  final _LaunchSlide slide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetBg.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BytzGoTheme.sheetDivider.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: slide.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'BYTZGO',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
                color: slide.accent,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            slide.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              height: 1.1,
              color: BytzGoTheme.sheetText,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            slide.subtitle,
            style: BytzGoTheme.sheetBody(13),
          ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: active
                ? BytzGoTheme.accent
                : Colors.white.withValues(alpha: 0.2),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: BytzGoTheme.accent.withValues(alpha: 0.45),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

/// Branded ring loader — blue + lime arcs, soft pulse.
class _BytzGoLaunchLoader extends StatelessWidget {
  const _BytzGoLaunchLoader({
    required this.spin,
    required this.pulse,
  });

  final AnimationController spin;
  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([spin, pulse]),
      builder: (context, child) {
        final scale = 0.92 + pulse.value * 0.08;
        return Transform.scale(
          scale: scale,
          child: SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(64, 64),
                  painter: _RingLoaderPainter(rotation: spin.value),
                ),
                Image.asset(
                  'assets/branding/preloader.png',
                  width: 40,
                  height: 40,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, __, ___) => Image.asset(
                    'assets/branding/app_logo.png',
                    width: 36,
                    height: 36,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RingLoaderPainter extends CustomPainter {
  _RingLoaderPainter({required this.rotation});

  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation * 6.28318);

    final blueArc = Paint()
      ..shader = SweepGradient(
        colors: [
          BytzGoTheme.brandBlue.withValues(alpha: 0.05),
          BytzGoTheme.brandBlue,
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final greenArc = Paint()
      ..color = BytzGoTheme.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: radius),
      0,
      2.1,
      false,
      blueArc,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: radius),
      2.4,
      1.2,
      false,
      greenArc,
    );
    canvas.restore();

    final dot = Paint()..color = BytzGoTheme.accent;
    canvas.drawCircle(center, 3.5, dot);
  }

  @override
  bool shouldRepaint(covariant _RingLoaderPainter old) =>
      old.rotation != rotation;
}
