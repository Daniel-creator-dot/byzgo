import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// White rounded top sheet container.
class RideSheet extends StatelessWidget {
  const RideSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 28),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      width: double.infinity,
      decoration: BytzGoTheme.sheetDecoration(),
      child: Padding(
        padding: padding.add(EdgeInsets.only(bottom: bottom > 0 ? bottom : 16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: BytzGoTheme.sheetDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
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
    final bg = color ?? BytzGoTheme.sheetText;
    final fg = bg == BytzGoTheme.accent ? BytzGoTheme.accentOn : BytzGoTheme.sheetBg;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: loading ? null : onPressed,
        borderRadius: BorderRadius.circular(14),
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
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetBg,
        borderRadius: BorderRadius.circular(24),
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
          Icon(icon, size: 18, color: BytzGoTheme.accent),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: BytzGoTheme.sheetText,
            ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: selected
            ? BytzGoTheme.accent.withValues(alpha: 0.08)
            : BytzGoTheme.sheetDivider.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? BytzGoTheme.accent : BytzGoTheme.sheetDivider,
          width: selected ? 2 : 1,
        ),
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
