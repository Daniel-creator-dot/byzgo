import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'biker_search_radar.dart';
import 'ride_map_background.dart';
import '../theme.dart';

/// Full-screen ride shell: map + optional top bar + bottom sheet.
class RideShell extends StatelessWidget {
  const RideShell({
    super.key,
    this.topBar,
    required this.sheet,
    this.showRoute = false,
    this.mapChild,
    this.floatingMapChild,
  });

  final Widget? topBar;
  final Widget sheet;
  final bool showRoute;
  /// Map layer — pass [RideGoogleMap] or defaults to painted background.
  final Widget? mapChild;
  final Widget? floatingMapChild;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BytzGoTheme.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (mapChild != null)
            mapChild!
          else ...[
            const RideMapBackground(),
            if (showRoute) const MapRouteArc(),
          ],
          if (floatingMapChild != null) floatingMapChild!,
          if (topBar != null)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: topBar!,
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: sheet,
          ),
        ],
      ),
    );
  }
}

/// White rounded bottom sheet — scrollable body + optional pinned footer (CTA).
class RideSheet extends StatelessWidget {
  const RideSheet({
    super.key,
    required this.child,
    this.footer,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 12),
    this.footerPadding = const EdgeInsets.fromLTRB(20, 0, 20, 12),
    this.maxHeightFraction = 0.62,
    this.bottomInset = 0,
    this.minSheetHeight = 220,
  });

  final Widget child;
  /// Pinned below scroll (e.g. primary CTA) — always visible and tappable.
  final Widget? footer;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry footerPadding;
  /// Max fraction of screen height for the whole sheet (handle + body + footer).
  final double maxHeightFraction;
  /// Subtract from max height (e.g. tab bar overlap).
  final double bottomInset;
  final double minSheetHeight;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenH = media.size.height;
        final parentH = constraints.maxHeight;
        final capFromScreen = screenH * maxHeightFraction - bottomInset;
        final capFromParent = parentH.isFinite && parentH > 0
            ? parentH - bottomInset
            : capFromScreen;
        final maxH = (capFromParent < capFromScreen ? capFromParent : capFromScreen)
            .clamp(minSheetHeight, screenH);

        return Container(
          width: double.infinity,
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: BytzGoTheme.sheetBg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(BytzGoTheme.sheetRadius),
            ),
            border: Border(
              top: BorderSide(color: BytzGoTheme.sheetDivider.withValues(alpha: 0.8)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 32,
                offset: const Offset(0, -10),
              ),
              BoxShadow(
                color: BytzGoTheme.brandBlue.withValues(alpha: 0.06),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: BytzGoTheme.sheetDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: padding,
                  child: child,
                ),
              ),
              if (footer != null)
                Padding(
                  padding: footerPadding.add(
                    EdgeInsets.only(bottom: media.padding.bottom * 0.15),
                  ),
                  child: footer!,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Subtle press scale for sharp tactile feedback.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    required this.onTap,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Fade + slide in when child appears (e.g. price quote).
class RideAnimatedReveal extends StatelessWidget {
  const RideAnimatedReveal({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: visible ? child : const SizedBox.shrink(key: ValueKey('hidden')),
    );
  }
}

/// Pickup / dropoff row like Uber.
class LocationRow extends StatelessWidget {
  const LocationRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.hint,
    required this.controller,
    this.onTap,
    this.readOnly = false,
  });

  final Widget icon;
  final Color iconColor;
  final String hint;
  final TextEditingController controller;
  final VoidCallback? onTap;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        icon,
        const SizedBox(width: 14),
        Expanded(
          child: TextField(
            controller: controller,
            readOnly: readOnly,
            onTap: onTap,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: BytzGoTheme.sheetText,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: BytzGoTheme.sheetMuted.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

Widget pickupDot() => Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: BytzGoTheme.accent,
        shape: BoxShape.circle,
      ),
    );

Widget dropoffSquare() => Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetText,
        borderRadius: BorderRadius.circular(2),
      ),
    );

/// Primary black CTA (Uber "Confirm" style).
class RidePrimaryButton extends StatelessWidget {
  const RidePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? BytzGoTheme.accent;
    final fg = (bg == BytzGoTheme.accent || bg == BytzGoTheme.accentDark)
        ? BytzGoTheme.accentOn
        : BytzGoTheme.sheetBg;
    return PressableScale(
      enabled: !loading && onPressed != null,
      onTap: onPressed,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        elevation: 2,
        shadowColor: bg.withValues(alpha: 0.45),
        child: Container(
          height: BytzGoTheme.buttonHeight,
          alignment: Alignment.center,
          child: loading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: fg.withValues(alpha: 0.9),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: fg, size: 22),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        color: fg,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Green accent button (Bolt accept).
class RideAccentButton extends StatelessWidget {
  const RideAccentButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BytzGoTheme.accent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: loading ? null : onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: BytzGoTheme.buttonHeight,
          alignment: Alignment.center,
          child: loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: BytzGoTheme.accentOn,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: BytzGoTheme.accentOn,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Rider online / offline toggle (Bolt driver mode).
class OnlineToggle extends StatelessWidget {
  const OnlineToggle({
    super.key,
    required this.isOnline,
    required this.onChanged,
  });

  final bool isOnline;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BytzGoTheme.sheetBg,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(32),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pill('Offline', !isOnline, () => onChanged(false)),
            _pill('Go online', isOnline, () {
              HapticFeedback.mediumImpact();
              onChanged(true);
            }),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? BytzGoTheme.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: selected ? BytzGoTheme.accentOn : BytzGoTheme.sheetMuted,
          ),
        ),
      ),
    );
  }
}

/// Trip status chip on map overlay.
class TripStatusChip extends StatelessWidget {
  const TripStatusChip({
    super.key,
    required this.label,
    this.icon = Icons.two_wheeler,
    this.searching = false,
    this.nearbyCount,
    this.etaPhrase,
    this.showRiderApproaching = false,
  });

  final String label;
  final IconData icon;
  final bool searching;
  final int? nearbyCount;
  final String? etaPhrase;
  final bool showRiderApproaching;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetBg,
        borderRadius: BorderRadius.circular(24),
        border: searching
            ? Border.all(color: BytzGoTheme.brandBlue.withValues(alpha: 0.35))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (searching)
            const BikerSearchRadar(size: 28, color: BytzGoTheme.brandBlue)
          else if (showRiderApproaching)
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: BytzGoTheme.brandBlue.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.near_me,
                size: 18,
                color: BytzGoTheme.brandBlue,
              ),
            )
          else
            Icon(icon, size: 18, color: BytzGoTheme.accent),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: BytzGoTheme.sheetText,
                ),
              ),
              if (etaPhrase != null && etaPhrase!.isNotEmpty)
                Text(
                  etaPhrase!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: BytzGoTheme.brandBlue,
                  ),
                )
              else if (searching && nearbyCount != null && nearbyCount! > 0)
                Text(
                  '$nearbyCount biker${nearbyCount == 1 ? '' : 's'} nearby',
                  style: BytzGoTheme.sheetBody(11),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Service type row — bike delivery.
class ServiceTypeTile extends StatelessWidget {
  const ServiceTypeTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.price,
    this.selected = true,
  });

  final String title;
  final String subtitle;
  final String price;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: selected
            ? BytzGoTheme.accent.withValues(alpha: 0.1)
            : BytzGoTheme.sheetDivider.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? BytzGoTheme.accent : BytzGoTheme.sheetDivider,
          width: selected ? 2 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: BytzGoTheme.accent.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: BytzGoTheme.sheetText,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.two_wheeler,
              color: BytzGoTheme.sheetBg,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: BytzGoTheme.sheetText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: BytzGoTheme.sheetBody(13)),
              ],
            ),
          ),
          Text(
            price,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: BytzGoTheme.sheetText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Active trip list tile in sheet.
class ActiveTripTile extends StatelessWidget {
  const ActiveTripTile({
    super.key,
    required this.address,
    required this.status,
    required this.price,
    required this.onTap,
  });

  final String address;
  final String status;
  final String price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BytzGoTheme.sheetDivider.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: BytzGoTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.two_wheeler,
                  color: BytzGoTheme.accentDark,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusLabel(status),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: BytzGoTheme.accentDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: BytzGoTheme.sheetText,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                price,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: BytzGoTheme.sheetText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Finding rider';
      case 'preparing':
        return 'Preparing';
      case 'ready':
        return 'Ready for pickup';
      case 'picked_up':
        return 'On the way';
      case 'arrived':
        return 'Rider arrived';
      default:
        return status.replaceAll('_', ' ');
    }
  }
}
