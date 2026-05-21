import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/widgets/legal_links.dart';
import '../../../shared/widgets/ride_ui.dart';

/// Drag handle + optional title row for auth bottom sheet.
class AuthSheetHeader extends StatelessWidget {
  const AuthSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: BytzGoTheme.sheetDivider,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
        Text(title, style: BytzGoTheme.sheetTitle(26)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: BytzGoTheme.sheetBody(14)),
        ],
        const SizedBox(height: 4),
        Container(
          height: 3,
          width: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            gradient: const LinearGradient(
              colors: [BytzGoTheme.brandBlue, BytzGoTheme.accent],
            ),
          ),
        ),
      ],
    );
  }
}

/// Sign in / Join pill toggle.
class AuthModeSegment extends StatelessWidget {
  const AuthModeSegment({
    super.key,
    required this.signInSelected,
    required this.onSignIn,
    required this.onJoin,
  });

  final bool signInSelected;
  final VoidCallback onSignIn;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BytzGoTheme.sheetDivider.withValues(alpha: 0.6)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth / 2;
          return Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment:
                    signInSelected ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  width: w,
                  height: 40,
                  decoration: BoxDecoration(
                    color: signInSelected ? BytzGoTheme.accent : BytzGoTheme.sheetText,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: (signInSelected ? BytzGoTheme.accent : BytzGoTheme.sheetText)
                            .withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _SegmentTap(
                      label: 'Sign in',
                      selected: signInSelected,
                      onTap: onSignIn,
                      selectedOnDark: false,
                    ),
                  ),
                  Expanded(
                    child: _SegmentTap(
                      label: 'Join',
                      selected: !signInSelected,
                      onTap: onJoin,
                      selectedOnDark: true,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SegmentTap extends StatelessWidget {
  const _SegmentTap({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.selectedOnDark,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool selectedOnDark;

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? (selectedOnDark ? BytzGoTheme.sheetBg : BytzGoTheme.accentOn)
        : BytzGoTheme.sheetMuted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: fg,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.autocorrect = true,
    this.suffix,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool autocorrect;
  final Widget? suffix;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autocorrect: autocorrect,
      style: const TextStyle(
        color: BytzGoTheme.sheetText,
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null
            ? Icon(icon, color: BytzGoTheme.brandBlue, size: 22)
            : null,
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: BytzGoTheme.sheetDivider.withValues(alpha: 0.9),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BytzGoTheme.brandBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BytzGoTheme.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BytzGoTheme.danger, width: 2),
        ),
      ),
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BytzGoTheme.danger.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, color: BytzGoTheme.danger, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: BytzGoTheme.danger,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 20, color: BytzGoTheme.danger),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  BytzGoTheme.sheetDivider.withValues(alpha: 0),
                  BytzGoTheme.sheetDivider,
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'or continue with',
            style: BytzGoTheme.sheetBody(12).copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  BytzGoTheme.sheetDivider,
                  BytzGoTheme.sheetDivider.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AuthGoogleButton extends StatelessWidget {
  const AuthGoogleButton({
    super.key,
    required this.onPressed,
    this.loading = false,
  });

  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      enabled: onPressed != null && !loading,
      onTap: onPressed,
      child: Material(
        color: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: BytzGoTheme.brandBlue.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SizedBox(
              height: 52,
              child: loading
                  ? const Center(
                      child: SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const _GoogleMark(size: 20),
                        const SizedBox(width: 12),
                        Text(
                          'Continue with Google',
                          style: BytzGoTheme.sheetBody(15).copyWith(
                            fontWeight: FontWeight.w700,
                            color: BytzGoTheme.sheetText,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark({this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    const stroke = 2.2;
    final arcPaint = (Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 1),
      -0.4,
      1.2,
      false,
      arcPaint(const Color(0xFF4285F4)),
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 1),
      0.85,
      1.1,
      false,
      arcPaint(const Color(0xFF34A853)),
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 1),
      2.0,
      1.0,
      false,
      arcPaint(const Color(0xFFFBBC05)),
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 1),
      3.15,
      1.15,
      false,
      arcPaint(const Color(0xFFEA4335)),
    );
    canvas.drawLine(
      Offset(r, r * 0.45),
      Offset(r * 1.55, r * 0.45),
      Paint()
        ..color = const Color(0xFF4285F4)
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Google sign-in, legal copy, and partner strip — one coordinated block.
class AuthLoginExtras extends StatelessWidget {
  const AuthLoginExtras({
    super.key,
    required this.showGoogle,
    required this.onGoogle,
    this.googleLoading = false,
  });

  final bool showGoogle;
  final VoidCallback? onGoogle;
  final bool googleLoading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showGoogle) ...[
          const AuthOrDivider(),
          const SizedBox(height: 14),
          AuthGoogleButton(
            onPressed: onGoogle,
            loading: googleLoading,
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const LegalLinksRow(),
        ),
        const SizedBox(height: 14),
        const AuthPartnerFooter(),
      ],
    );
  }
}

/// Feature chips on login hero.
class AuthHeroFeatures extends StatelessWidget {
  const AuthHeroFeatures({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: const [
        _FeatureChip(icon: Icons.two_wheeler_rounded, label: 'Fast bikes'),
        _FeatureChip(icon: Icons.location_on_outlined, label: 'Live tracking'),
        _FeatureChip(icon: Icons.account_balance_wallet_outlined, label: 'MoMo wallet'),
      ],
    );
  }
}

/// Kesbridge partnership — clean trust strip aligned with BytzGo blue + lime.
class AuthPartnerFooter extends StatelessWidget {
  const AuthPartnerFooter({super.key});

  static const Color kesbridgeGold = Color(0xFFD4AF37);

  static const _thumbAssets = [
    'assets/branding/onboarding_delivery.png',
    'assets/branding/onboarding_rider.png',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            BytzGoTheme.brandBlue.withValues(alpha: 0.06),
            BytzGoTheme.accent.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(
          color: BytzGoTheme.brandBlue.withValues(alpha: 0.12),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Row(
            children: [
              _DeliveryThumbs(assets: _thumbAssets),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          size: 14,
                          color: BytzGoTheme.brandBlue.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'In partnership with',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: BytzGoTheme.brandBlue.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C1222),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: kesbridgeGold.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Image.asset(
                        'assets/branding/kesbridge_logo.png',
                        height: 26,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Kesbridge Insurance Brokers',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: BytzGoTheme.sheetMuted,
                        letterSpacing: 0.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeliveryThumbs extends StatelessWidget {
  const _DeliveryThumbs({required this.assets});

  final List<String> assets;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            child: _ThumbCircle(asset: assets[0], size: 40),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: _ThumbCircle(asset: assets[1], size: 36),
          ),
        ],
      ),
    );
  }
}

class _ThumbCircle extends StatelessWidget {
  const _ThumbCircle({required this.asset, required this.size});

  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: BytzGoTheme.brandBlue.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: BytzGoTheme.accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
