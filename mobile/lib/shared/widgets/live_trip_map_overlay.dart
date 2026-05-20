import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/location_point.dart';
import '../../models/order.dart';
import '../../shared/customer_trip.dart';
import '../../shared/delivery_pricing.dart';
import '../theme.dart';
import 'biker_search_radar.dart';

/// HUD on the map during active trip tracking (search + rider approaching).
class LiveTripMapHud extends StatelessWidget {
  const LiveTripMapHud({
    super.key,
    required this.order,
    required this.searching,
    this.nearbyCount,
    this.etaPhrase,
    this.riderPosition,
    this.navTarget,
    this.onRecenter,
  });

  final Order order;
  final bool searching;
  final int? nearbyCount;
  final String? etaPhrase;
  final LocationPoint? riderPosition;
  final LocationPoint? navTarget;
  final VoidCallback? onRecenter;

  double? get _distanceKm {
    if (riderPosition == null || navTarget == null) return null;
    if (!riderPosition!.hasCoords || !navTarget!.hasCoords) return null;
    return haversineDistanceKm(
      riderPosition!.lat,
      riderPosition!.lng,
      navTarget!.lat,
      navTarget!.lng,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasRider = order.riderId != null && !searching;
    final dist = _distanceKm;

    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            top: 56,
            left: 12,
            right: 12,
            child: _StatusBanner(
              order: order,
              searching: searching,
              nearbyCount: nearbyCount,
              etaPhrase: etaPhrase,
              distanceKm: dist,
              hasRider: hasRider,
            ),
          ),
          if (hasRider && dist != null)
            Positioned(
              left: 12,
              bottom: 12,
              child: _DistanceRadarPill(
                distanceKm: dist,
                label: order.status == 'picked_up' ? 'To you' : 'To pickup',
              ),
            ),
          if (searching)
            Positioned(
              right: 12,
              bottom: 12,
              child: _ScanningLegend(nearbyCount: nearbyCount ?? 0),
            ),
          if (hasRider)
            Positioned(
              right: 12,
              bottom: 12,
              child: _MapLegendCompact(),
            ),
          if (onRecenter != null)
            Positioned(
              right: 12,
              top: 120,
              child: _RecenterButton(onPressed: onRecenter!),
            ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.order,
    required this.searching,
    this.nearbyCount,
    this.etaPhrase,
    this.distanceKm,
    required this.hasRider,
  });

  final Order order;
  final bool searching;
  final int? nearbyCount;
  final String? etaPhrase;
  final double? distanceKm;
  final bool hasRider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetBg.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: searching
              ? BytzGoTheme.brandBlue.withValues(alpha: 0.4)
              : BytzGoTheme.accent.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: searching
                ? const BikerSearchRadar(size: 44, color: BytzGoTheme.brandBlue)
                : hasRider
                    ? _ApproachRadarMini(distanceKm: distanceKm)
                    : Icon(
                        _iconForStatus(order.status),
                        color: BytzGoTheme.accentDark,
                        size: 26,
                      ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customerTripHeadline(order),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: BytzGoTheme.sheetText,
                  ),
                ),
                const SizedBox(height: 2),
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
                    'Scanning · $nearbyCount biker${nearbyCount == 1 ? '' : 's'} on radar',
                    style: BytzGoTheme.sheetBody(11),
                  )
                else if (hasRider && distanceKm != null)
                  Text(
                    '${distanceKm!.toStringAsFixed(1)} km away · live on map',
                    style: BytzGoTheme.sheetBody(11),
                  )
                else
                  Text(
                    customerTripSubline(order),
                    style: BytzGoTheme.sheetBody(11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (order.riderName != null && order.riderName!.isNotEmpty && hasRider)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: BytzGoTheme.brandBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.two_wheeler, size: 16, color: BytzGoTheme.brandBlue),
                  const SizedBox(width: 4),
                  Text(
                    order.riderName!.split(' ').first,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: BytzGoTheme.brandBlue,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconForStatus(String status) {
    switch (status) {
      case 'delivered':
        return Icons.check_circle;
      case 'arrived':
        return Icons.place;
      case 'picked_up':
        return Icons.local_shipping;
      default:
        return Icons.two_wheeler;
    }
  }
}

class _ApproachRadarMini extends StatefulWidget {
  const _ApproachRadarMini({this.distanceKm});

  final double? distanceKm;

  @override
  State<_ApproachRadarMini> createState() => _ApproachRadarMiniState();
}

class _ApproachRadarMiniState extends State<_ApproachRadarMini>
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
      builder: (context, _) {
        return CustomPaint(
          size: const Size(44, 44),
          painter: _MiniRiderRadarPainter(progress: _ctrl.value),
          child: const Center(
            child: Icon(
              Icons.two_wheeler,
              size: 20,
              color: BytzGoTheme.brandBlue,
            ),
          ),
        );
      },
    );
  }
}

class _MiniRiderRadarPainter extends CustomPainter {
  _MiniRiderRadarPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide / 2;
    for (var i = 0; i < 2; i++) {
      final t = (progress + i * 0.5) % 1.0;
      final r = maxR * (0.4 + t * 0.55);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = BytzGoTheme.accent.withValues(alpha: (1 - t) * 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniRiderRadarPainter old) =>
      old.progress != progress;
}

class _DistanceRadarPill extends StatelessWidget {
  const _DistanceRadarPill({
    required this.distanceKm,
    required this.label,
  });

  final double distanceKm;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            BytzGoTheme.brandBlue,
            BytzGoTheme.brandBlue.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: BytzGoTheme.brandBlue.withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.radar, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${distanceKm.toStringAsFixed(1)} km',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScanningLegend extends StatelessWidget {
  const _ScanningLegend({required this.nearbyCount});

  final int nearbyCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetBg.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'LIVE RADAR',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: BytzGoTheme.brandBlue,
            ),
          ),
          const SizedBox(height: 6),
          _legendRow(BytzGoTheme.accent, 'Scan ring'),
          _legendRow(Colors.amber, 'Bikers ($nearbyCount)'),
          _legendRow(Colors.green, 'Pickup'),
        ],
      ),
    );
  }

  Widget _legendRow(Color c, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(t, style: BytzGoTheme.sheetBody(10)),
          ],
        ),
      );
}

class _MapLegendCompact extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetBg.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendDot(color: Colors.orange, label: 'Your biker'),
          SizedBox(height: 4),
          _LegendDot(color: Colors.green, label: 'Pickup'),
          SizedBox(height: 4),
          _LegendDot(color: Colors.blue, label: 'Drop-off'),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: BytzGoTheme.sheetBody(10)),
      ],
    );
  }
}

class _RecenterButton extends StatelessWidget {
  const _RecenterButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BytzGoTheme.sheetBg,
      elevation: 4,
      shadowColor: Colors.black26,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.my_location, color: BytzGoTheme.brandBlue, size: 22),
        ),
      ),
    );
  }
}

/// Web / painted map: rider pin + approach line toward target.
class MapLiveRiderOverlay extends StatefulWidget {
  const MapLiveRiderOverlay({
    super.key,
    required this.rider,
    required this.target,
    this.pickup,
    this.destination,
  });

  final LocationPoint rider;
  final LocationPoint target;
  final LocationPoint? pickup;
  final LocationPoint? destination;

  @override
  State<MapLiveRiderOverlay> createState() => _MapLiveRiderOverlayState();
}

class _MapLiveRiderOverlayState extends State<MapLiveRiderOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Offset _project(
    double lat,
    double lng,
    double centerLat,
    double centerLng,
    Size size,
  ) {
    final scale = size.shortestSide * 3.8;
    final x = size.width * 0.5 + (lng - centerLng) * scale;
    final y = size.height * 0.45 - (lat - centerLat) * scale;
    return Offset(
      x.clamp(24.0, size.width - 24),
      y.clamp(size.height * 0.15, size.height * 0.75),
    );
  }

  @override
  Widget build(BuildContext context) {
    final centerLat = (widget.rider.lat + widget.target.lat) / 2;
    final centerLng = (widget.rider.lng + widget.target.lng) / 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final riderPos = _project(
          widget.rider.lat,
          widget.rider.lng,
          centerLat,
          centerLng,
          size,
        );
        final targetPos = _project(
          widget.target.lat,
          widget.target.lng,
          centerLat,
          centerLng,
          size,
        );

        return AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  size: size,
                  painter: _ApproachLinePainter(
                    from: riderPos,
                    to: targetPos,
                    pulse: _pulse.value,
                  ),
                ),
                Positioned(
                  left: riderPos.dx - 56,
                  top: riderPos.dy - 56,
                  child: BikerSearchRadar(
                    size: 112,
                    color: BytzGoTheme.accent,
                    showIcon: false,
                  ),
                ),
                Positioned(
                  left: riderPos.dx - 22,
                  top: riderPos.dy - 22,
                  child: _LiveRiderPin(pulse: _pulse.value),
                ),
                Positioned(
                  left: targetPos.dx - 14,
                  top: targetPos.dy - 14,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: BytzGoTheme.brandBlue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ApproachLinePainter extends CustomPainter {
  _ApproachLinePainter({
    required this.from,
    required this.to,
    required this.pulse,
  });

  final Offset from;
  final Offset to;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BytzGoTheme.brandBlue.withValues(alpha: 0.55)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, to, paint);

    final dashT = pulse;
    final mid = Offset.lerp(from, to, dashT)!;
    canvas.drawCircle(
      mid,
      6,
      Paint()..color = BytzGoTheme.accent.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant _ApproachLinePainter old) =>
      old.pulse != pulse || old.from != from || old.to != to;
}

class _LiveRiderPin extends StatelessWidget {
  const _LiveRiderPin({required this.pulse});

  final double pulse;

  @override
  Widget build(BuildContext context) {
    final scale = 1 + math.sin(pulse * math.pi * 2) * 0.08;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.orange,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withValues(alpha: 0.5),
              blurRadius: 14,
            ),
          ],
        ),
        child: const Icon(Icons.two_wheeler, color: Colors.white, size: 24),
      ),
    );
  }
}
