import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
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
        color: BytzGoTheme.sheetDivider.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
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
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
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
        fillColor: const Color(0xFFF3F4F6),
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
        Expanded(child: Divider(color: BytzGoTheme.sheetDivider.withValues(alpha: 0.9))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: BytzGoTheme.sheetBody(13).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Divider(color: BytzGoTheme.sheetDivider.withValues(alpha: 0.9))),
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
      child: OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: Colors.white,
          side: BorderSide(color: BytzGoTheme.sheetDivider.withValues(alpha: 0.95)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          foregroundColor: BytzGoTheme.sheetText,
        ),
        child: loading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GoogleMark(),
                  const SizedBox(width: 12),
                  const Text(
                    'Continue with Google',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ],
              ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: BytzGoTheme.sheetDivider),
      ),
      child: const Center(
        child: Text(
          'G',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: Color(0xFF4285F4),
          ),
        ),
      ),
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

/// Rotating circular image bubble (login footer gallery).
class AuthRoundGalleryBubble extends StatefulWidget {
  const AuthRoundGalleryBubble({
    super.key,
    required this.assets,
    this.size = 78,
    this.startIndex = 0,
    this.interval = const Duration(milliseconds: 2600),
  });

  final List<String> assets;
  final double size;
  final int startIndex;
  final Duration interval;

  @override
  State<AuthRoundGalleryBubble> createState() => _AuthRoundGalleryBubbleState();
}

class _AuthRoundGalleryBubbleState extends State<AuthRoundGalleryBubble>
    with SingleTickerProviderStateMixin {
  late int _index;
  late final AnimationController _pulse;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _index = widget.startIndex % widget.assets.length;
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % widget.assets.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.assets[_index];
    return ScaleTransition(
      scale: Tween<double>(begin: 0.94, end: 1.06).animate(
        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AuthPartnerFooter.kesbridgeGold.withValues(alpha: 0.85),
              BytzGoTheme.accent.withValues(alpha: 0.75),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AuthPartnerFooter.kesbridgeGold.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(3),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          child: ClipOval(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 550),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: Image.asset(
                asset,
                key: ValueKey(asset),
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kesbridge partnership + animated round galleries on each side.
class AuthPartnerFooter extends StatelessWidget {
  const AuthPartnerFooter({super.key});

  static const Color kesbridgeGold = Color(0xFFC9A227);
  static const Color kesbridgeGoldDark = Color(0xFF9A7B1A);

  static const _galleryAssets = [
    'assets/branding/onboarding_delivery.png',
    'assets/branding/onboarding_rider.png',
    'assets/branding/hero_delivery.png',
    'assets/branding/onboarding_team.png',
    'assets/branding/hero_rider.png',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AuthRoundGalleryBubble(
              assets: _galleryAssets,
              startIndex: 0,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Partnered by',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: kesbridgeGoldDark.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0A0A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kesbridgeGold.withValues(alpha: 0.45)),
                    ),
                    child: Image.asset(
                      'assets/branding/kesbridge_logo.png',
                      height: 28,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            AuthRoundGalleryBubble(
              assets: _galleryAssets,
              startIndex: 2,
              interval: const Duration(milliseconds: 3100),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Kesbridge Insurance Brokers',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
            color: kesbridgeGold,
            letterSpacing: 0.2,
          ),
        ),
      ],
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
