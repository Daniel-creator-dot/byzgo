import 'package:flutter/material.dart';

import '../../models/order.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/biker_search_radar.dart';

/// Floating HUD on the driver map (radar, offers, recenter).
class RiderDriveHud extends StatelessWidget {
  const RiderDriveHud({
    super.key,
    required this.isOnline,
    required this.offerCount,
    required this.mappedOfferCount,
    this.previewOrder,
    this.earningsToday,
    this.tripsToday,
    this.onRecenter,
  });

  final bool isOnline;
  final int offerCount;
  final int mappedOfferCount;
  final Order? previewOrder;
  final double? earningsToday;
  final int? tripsToday;
  final VoidCallback? onRecenter;

  @override
  Widget build(BuildContext context) {
    if (!isOnline) return const SizedBox.shrink();

    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            top: 4,
            left: 12,
            right: 12,
            child: _TopBanner(
              offerCount: offerCount,
              mappedOfferCount: mappedOfferCount,
              previewOrder: previewOrder,
            ),
          ),
          if (offerCount == 0)
            Positioned(
              left: 12,
              right: 80,
              bottom: 8,
              child: _ScanningCard(tripsToday: tripsToday),
            ),
          if (offerCount > 0)
            Positioned(
              left: 12,
              bottom: 8,
              child: _OffersLegend(count: mappedOfferCount),
            ),
          if (earningsToday != null)
            Positioned(
              right: 12,
              top: 72,
              child: _EarningsChip(amount: earningsToday!),
            ),
          if (onRecenter != null)
            Positioned(
              right: 12,
              bottom: 8,
              child: _RecenterFab(onPressed: onRecenter!),
            ),
        ],
      ),
    );
  }
}

class _TopBanner extends StatelessWidget {
  const _TopBanner({
    required this.offerCount,
    required this.mappedOfferCount,
    this.previewOrder,
  });

  final int offerCount;
  final int mappedOfferCount;
  final Order? previewOrder;

  @override
  Widget build(BuildContext context) {
    final preview = previewOrder;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BytzGoTheme.accent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            height: 42,
            child: offerCount > 0
                ? const Icon(Icons.location_on, color: BytzGoTheme.accent, size: 28)
                : const BikerSearchRadar(size: 42, color: BytzGoTheme.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preview != null
                      ? 'Previewing job #${preview.id.length > 4 ? preview.id.substring(preview.id.length - 4) : preview.id}'
                      : offerCount > 0
                          ? '$offerCount request${offerCount == 1 ? '' : 's'} nearby'
                          : 'Scanning for customers',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  preview != null
                      ? '${preview.customerName} · ${formatCedis(preview.total)}'
                      : mappedOfferCount > 0
                          ? 'Green = pickup · Blue = customer drop-off'
                          : 'Jobs with addresses appear on the map',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanningCard extends StatelessWidget {
  const _ScanningCard({this.tripsToday});

  final int? tripsToday;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetBg.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const BikerSearchRadar(size: 36, color: BytzGoTheme.brandBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Live radar on',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: BytzGoTheme.sheetText,
                  ),
                ),
                Text(
                  tripsToday != null && tripsToday! > 0
                      ? '$tripsToday trips today · new jobs ping you'
                      : 'Customer pickups show as pins when requested',
                  style: BytzGoTheme.sheetBody(11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OffersLegend extends StatelessWidget {
  const _OffersLegend({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetBg.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count ON MAP',
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: BytzGoTheme.brandBlue,
            ),
          ),
          const SizedBox(height: 6),
          _row(Colors.green, 'Pickup'),
          _row(Colors.blue, 'Customer'),
          _row(Colors.orange, 'You'),
        ],
      ),
    );
  }

  Widget _row(Color c, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
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

class _EarningsChip extends StatelessWidget {
  const _EarningsChip({required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: BytzGoTheme.accent.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'TODAY',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w900,
              color: Color(0xFF020617),
            ),
          ),
          Text(
            formatCedis(amount),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: Color(0xFF020617),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecenterFab extends StatelessWidget {
  const _RecenterFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BytzGoTheme.sheetBg,
      elevation: 4,
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
