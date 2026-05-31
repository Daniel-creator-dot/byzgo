import 'package:flutter/material.dart';

import '../models/order.dart';
import 'theme.dart';

/// Uber Eats / Bolt Food-style driver tier. The more stars a driver keeps
/// (across enough rated trips), the higher they climb toward Gold.
enum DriverTier { gold, silver, bronze, fresh }

DriverTier driverTierFrom(double? avg, int count) {
  if (avg == null || count < 3) return DriverTier.fresh;
  if (avg >= 4.8 && count >= 20) return DriverTier.gold;
  if (avg >= 4.5 && count >= 8) return DriverTier.silver;
  if (avg >= 4.0) return DriverTier.bronze;
  return DriverTier.fresh;
}

DriverTier driverTierFromName(String? name) {
  switch (name) {
    case 'gold':
      return DriverTier.gold;
    case 'silver':
      return DriverTier.silver;
    case 'bronze':
      return DriverTier.bronze;
    default:
      return DriverTier.fresh;
  }
}

/// Resolve the tier for an order's assigned driver — prefers the backend
/// value, falls back to computing from the exposed average + count.
DriverTier driverTierForOrder(Order order) {
  if (order.riderTier != null && order.riderTier!.isNotEmpty) {
    return driverTierFromName(order.riderTier);
  }
  return driverTierFrom(order.riderAvgRating, order.riderRatingCount ?? 0);
}

extension DriverTierMeta on DriverTier {
  bool get isGold => this == DriverTier.gold;

  String get label {
    switch (this) {
      case DriverTier.gold:
        return 'Gold';
      case DriverTier.silver:
        return 'Silver';
      case DriverTier.bronze:
        return 'Bronze';
      case DriverTier.fresh:
        return 'New';
    }
  }

  Color get color {
    switch (this) {
      case DriverTier.gold:
        return const Color(0xFFF5B301);
      case DriverTier.silver:
        return const Color(0xFF94A3B8);
      case DriverTier.bronze:
        return const Color(0xFFCD7F32);
      case DriverTier.fresh:
        return BytzGoTheme.brandBlue;
    }
  }
}

/// Small pill showing the driver's tier (with a medal for Gold) and, when
/// available, their average rating. Use on customer tracking + rider profile.
class DriverTierBadge extends StatelessWidget {
  const DriverTierBadge({
    super.key,
    required this.tier,
    this.avgRating,
    this.ratingCount,
    this.compact = false,
  });

  final DriverTier tier;
  final double? avgRating;
  final int? ratingCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = tier.color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 4 : 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: tier.isGold ? 0.18 : 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            tier == DriverTier.fresh ? Icons.eco_outlined : Icons.workspace_premium,
            size: compact ? 13 : 15,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            tier == DriverTier.fresh ? 'New driver' : '${tier.label} driver',
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
          if (avgRating != null && (ratingCount ?? 0) > 0) ...[
            const SizedBox(width: 6),
            Icon(Icons.star_rounded, size: compact ? 12 : 14, color: color),
            const SizedBox(width: 1),
            Text(
              avgRating!.toStringAsFixed(1),
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
