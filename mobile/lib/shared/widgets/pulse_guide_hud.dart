import 'package:flutter/material.dart';

import '../../models/order.dart';
import '../pulse_guide.dart';
/// Rider HUD chip when customer has activated Pulse Guide™.
class PulseGuideHud extends StatelessWidget {
  const PulseGuideHud({
    super.key,
    required this.order,
    this.distanceMeters,
  });

  final Order order;
  final int? distanceMeters;

  @override
  Widget build(BuildContext context) {
    if (!isPulseGuideActive(order)) return const SizedBox.shrink();

    final phase = order.pulseGuidePhase ?? 'pickup';
    final dist = formatPulseDistance(distanceMeters);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.4),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.gps_fixed, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pulse Guide — ${phase == 'pickup' ? 'pickup' : 'drop-off'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                Text(
                  dist.isNotEmpty
                      ? 'Customer live spot · $dist'
                      : 'Follow the red pulse on the map',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
