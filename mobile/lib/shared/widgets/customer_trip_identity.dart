import 'package:flutter/material.dart';

import '../../models/order.dart';
import '../theme.dart';
import 'contact_avatar.dart';

/// Customer name, photo, and average rating for riders during a trip.
class CustomerTripIdentity extends StatelessWidget {
  const CustomerTripIdentity({
    super.key,
    required this.order,
    this.light = false,
  });

  final Order order;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final name = order.customerName.trim().isEmpty ? 'Customer' : order.customerName.trim();
    final rating = order.customerAvgRating;
    final textColor = light ? Colors.white : BytzGoTheme.sheetText;
    final muted = light ? Colors.white.withValues(alpha: 0.7) : BytzGoTheme.sheetMuted;

    return Row(
      children: [
        ContactAvatar(
          name: name,
          avatarUrl: order.customerAvatarUrl,
          radius: 22,
          backgroundColor: light
              ? Colors.white.withValues(alpha: 0.12)
              : BytzGoTheme.brandBlue.withValues(alpha: 0.12),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (rating != null && rating > 0) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.star_rounded, size: 14, color: BytzGoTheme.accent),
                    const SizedBox(width: 2),
                    Text(
                      rating.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: muted,
                      ),
                    ),
                    Text(
                      ' customer rating',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
