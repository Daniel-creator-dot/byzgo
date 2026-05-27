import 'package:flutter/material.dart';

import '../../models/rider_stats.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';

/// Driver performance metrics (acceptance rate, earnings, ratings).
class RiderPerformanceSection extends StatelessWidget {
  const RiderPerformanceSection({
    super.key,
    required this.stats,
    this.loading = false,
  });

  final RiderStats? stats;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading && stats == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(color: BytzGoTheme.accent, strokeWidth: 2),
        ),
      );
    }
    final s = stats;
    if (s == null) return const SizedBox.shrink();

    final acceptancePct = s.acceptanceRate != null
        ? '${(s.acceptanceRate! * 100).round()}%'
        : '—';
    final ratingLabel = s.avgRating != null && s.avgRating! > 0
        ? s.avgRating!.toStringAsFixed(1)
        : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Performance',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Last 30 days dispatch · calendar month earnings',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _metricTile('Today', formatCedis(s.earningsToday), '${s.tripsToday} trips'),
            const SizedBox(width: 8),
            _metricTile('This week', formatCedis(s.earningsWeek), '${s.tripsWeek} trips'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _metricTile('This month', formatCedis(s.earningsMonth), '${s.tripsMonth} trips'),
            const SizedBox(width: 8),
            _metricTile('Accept rate', acceptancePct, '${s.offersAccepted}/${s.offersReceived} offers'),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Row(
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customer rating',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '$ratingLabel avg · ${s.ratedTrips} rated trips',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (s.offersDeclined > 0)
                Text(
                  '${s.offersDeclined} declined',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricTile(String label, String value, String sub) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.4),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: BytzGoTheme.accent,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
