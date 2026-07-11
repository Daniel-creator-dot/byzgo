import 'package:flutter/material.dart';

import '../../models/ride_service.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/ride_google_map.dart';
import '../../shared/widgets/ride_hub_welcome.dart';
import '../../shared/widgets/ride_ui.dart';

/// Hero + quick actions for the ride & delivery booking sheet.
class DeliveryBookingHeader extends StatelessWidget {
  const DeliveryBookingHeader({
    super.key,
    required this.firstName,
    required this.balance,
    required this.selectedService,
    this.vendorMode = false,
    this.onShops,
    this.onWallet,
    this.onTrips,
    this.onProfile,
  });

  final String firstName;
  final double balance;
  final RideServiceType selectedService;
  final bool vendorMode;
  final VoidCallback? onShops;
  final VoidCallback? onWallet;
  final VoidCallback? onTrips;
  final VoidCallback? onProfile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RideHubWelcome(
          firstName: firstName,
          balance: balance,
          selectedService: selectedService,
          vendorMode: vendorMode,
          onWallet: onWallet,
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 92,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (onShops != null)
                _QuickTile(
                  image: 'assets/branding/pharmacy_hub_welcome.png',
                  label: 'Pharmacy',
                  accent: const Color(0xFF14B8A6),
                  onTap: onShops,
                ),
              _QuickTile(
                image: 'assets/branding/onboarding_delivery.png',
                label: 'Top up',
                accent: const Color(0xFF22C55E),
                onTap: onWallet,
              ),
              _QuickTile(
                image: 'assets/branding/onboarding_rider.png',
                label: 'Trips',
                accent: const Color(0xFF0EA5E9),
                onTap: onTrips,
              ),
              _QuickTile(
                image: 'assets/branding/hero_login.png',
                label: 'Account',
                accent: const Color(0xFFA855F7),
                onTap: onProfile,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.image,
    required this.label,
    required this.accent,
    this.onTap,
  });

  final String image;
  final String label;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: PressableScale(
        onTap: onTap,
        child: Container(
          width: 88,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(image, fit: BoxFit.cover),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Package / parcel type chips.
class PackageTypeSelector extends StatelessWidget {
  const PackageTypeSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  static const options = [
    _Pkg('Package', Icons.inventory_2_outlined, Color(0xFF0EA5E9)),
    _Pkg('Documents', Icons.description_outlined, Color(0xFF6366F1)),
    _Pkg('Medicine', Icons.medication_outlined, Color(0xFF14B8A6)),
    _Pkg('Electronics', Icons.devices_other_outlined, Color(0xFF8B5CF6)),
    _Pkg('Fragile', Icons.wine_bar_outlined, Color(0xFFEC4899)),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WHAT ARE YOU SENDING?',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            color: BytzGoTheme.sheetMuted.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: options.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final o = options[i];
              final isOn = selected == o.label;
              return PressableScale(
                onTap: () => onSelected(o.label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isOn
                        ? o.color.withValues(alpha: 0.15)
                        : BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isOn ? o.color : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        o.icon,
                        size: 18,
                        color: isOn ? o.color : BytzGoTheme.sheetMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        o.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: isOn ? BytzGoTheme.sheetText : BytzGoTheme.sheetMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Pkg {
  const _Pkg(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

/// Pickup / drop-off card with visual route spine.
class VisualRouteCard extends StatelessWidget {
  const VisualRouteCard({
    super.key,
    required this.pickupChild,
    required this.dropoffChild,
  });

  final Widget pickupChild;
  final Widget dropoffChild;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BytzGoTheme.sheetDivider),
        boxShadow: [
          BoxShadow(
            color: BytzGoTheme.brandBlue.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 36,
              child: Column(
                children: [
                  const SizedBox(height: 22),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: BytzGoTheme.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: BytzGoTheme.accent.withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: CustomPaint(
                      painter: _RouteLinePainter(),
                      size: const Size(12, double.infinity),
                    ),
                  ),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: BytzGoTheme.sheetText,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 22),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  pickupChild,
                  Divider(
                    height: 1,
                    color: BytzGoTheme.sheetDivider.withValues(alpha: 0.7),
                  ),
                  dropoffChild,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          BytzGoTheme.accent,
          BytzGoTheme.brandBlue,
          BytzGoTheme.sheetText,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Fee quote with hero bike image.
class DeliveryQuoteCard extends StatelessWidget {
  const DeliveryQuoteCard({
    super.key,
    required this.fee,
    required this.distanceKm,
    this.surgeActive = false,
    this.loading = false,
    this.promotionDiscount = 0,
    this.promotionName,
  });

  final double fee;
  final double distanceKm;
  final bool surgeActive;
  final bool loading;
  final double promotionDiscount;
  final String? promotionName;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            BytzGoTheme.accent.withValues(alpha: 0.22),
            BytzGoTheme.brandBlue.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: BytzGoTheme.accent.withValues(alpha: 0.45)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              right: -4,
              top: 0,
              bottom: 0,
              width: 96,
              child: Opacity(
                opacity: 0.35,
                child: Image.asset(
                  'assets/branding/hero_rider.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.centerLeft,
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      BytzGoTheme.sheetBg,
                      BytzGoTheme.sheetBg.withValues(alpha: 0.97),
                      BytzGoTheme.sheetBg.withValues(alpha: 0.82),
                      BytzGoTheme.sheetBg.withValues(alpha: 0.45),
                    ],
                    stops: const [0.0, 0.45, 0.72, 1.0],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 88, 16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: BytzGoTheme.sheetText,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.two_wheeler,
                      color: BytzGoTheme.accent,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Bike courier',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: BytzGoTheme.sheetText,
                              ),
                            ),
                            if (surgeActive) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'SURGE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                            if (!loading && promotionDiscount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: BytzGoTheme.accent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  (promotionName?.trim().isNotEmpty == true)
                                      ? promotionName!.trim().toUpperCase()
                                      : 'PROMO',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          loading
                              ? 'Calculating…'
                              : distanceKm > 0
                                  ? promotionDiscount > 0
                                      ? '${distanceKm.toStringAsFixed(1)} km · Save ${formatCedis(promotionDiscount)}'
                                      : '${distanceKm.toStringAsFixed(1)} km · Pay on arrival'
                                  : 'Pay when rider arrives',
                          style: BytzGoTheme.sheetBody(12),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (!loading && promotionDiscount > 0)
                        Text(
                          formatCedis(fee + promotionDiscount),
                          style: TextStyle(
                            decoration: TextDecoration.lineThrough,
                            fontSize: 12,
                            color: BytzGoTheme.sheetMuted.withValues(alpha: 0.9),
                          ),
                        ),
                      Text(
                        loading
                            ? 'Calculating…'
                            : formatCedis(fee),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: loading ? 16 : 20,
                          color: loading
                              ? BytzGoTheme.sheetMuted
                              : BytzGoTheme.accentDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MapPickModeChips extends StatelessWidget {
  const MapPickModeChips({
    super.key,
    required this.mode,
    required this.onMode,
  });

  final MapPickMode mode;
  final ValueChanged<MapPickMode> onMode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _chip('Set pickup on map', MapPickMode.pickup, Icons.trip_origin),
        const SizedBox(width: 8),
        _chip('Set drop-off on map', MapPickMode.destination, Icons.place),
      ],
    );
  }

  Widget _chip(String label, MapPickMode m, IconData icon) {
    final on = mode == m;
    return Expanded(
      child: PressableScale(
        onTap: () => onMode(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: on
                ? BytzGoTheme.brandBlue.withValues(alpha: 0.12)
                : BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: on ? BytzGoTheme.brandBlue : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: on ? BytzGoTheme.brandBlue : BytzGoTheme.sheetMuted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: on ? BytzGoTheme.brandBlue : BytzGoTheme.sheetMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
