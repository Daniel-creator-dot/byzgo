import 'package:flutter/material.dart';

import '../../models/ride_service.dart';
import '../../shared/theme.dart';

/// Premium service picker — Package courier, Okada, Keke (Pragia).
class RideServicePicker extends StatelessWidget {
  const RideServicePicker({
    super.key,
    required this.selected,
    required this.onSelected,
    this.compact = false,
  });

  final RideServiceType selected;
  final ValueChanged<RideServiceType> onSelected;
  final bool compact;

  static const _cards = [
    _RideCardSpec(
      type: RideServiceType.package,
      title: 'Package',
      subtitle: 'Bike courier',
      detail: 'Documents · parcels · shop items',
      accent: Color(0xFF0EA5E9),
      gradient: [Color(0xFF0C4A6E), Color(0xFF0369A1)],
    ),
    _RideCardSpec(
      type: RideServiceType.okada,
      title: 'Okada',
      subtitle: 'Motor ride',
      detail: '1–2 passengers · fastest',
      accent: Color(0xFF22C55E),
      gradient: [Color(0xFF14532D), Color(0xFF15803D)],
    ),
    _RideCardSpec(
      type: RideServiceType.keke,
      title: 'Keke',
      subtitle: 'Pragia',
      detail: 'Up to 4 · comfortable',
      accent: Color(0xFFF59E0B),
      gradient: [Color(0xFF78350F), Color(0xFFB45309)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'CHOOSE YOUR MODE',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: BytzGoTheme.sheetMuted.withValues(alpha: 0.95),
          ),
        ),
        SizedBox(height: compact ? 8 : 10),
        Row(
          children: _cards.map((spec) {
            final active = spec.type == selected;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: spec.type != RideServiceType.keke ? 8 : 0,
                ),
                child: _RideServiceCard(
                  spec: spec,
                  active: active,
                  compact: compact,
                  onTap: () => onSelected(spec.type),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _RideCardSpec {
  const _RideCardSpec({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.accent,
    required this.gradient,
  });

  final RideServiceType type;
  final String title;
  final String subtitle;
  final String detail;
  final Color accent;
  final List<Color> gradient;
}

class _RideServiceCard extends StatelessWidget {
  const _RideServiceCard({
    required this.spec,
    required this.active,
    required this.compact,
    required this.onTap,
  });

  final _RideCardSpec spec;
  final bool active;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: active ? 1.0 : 0.97,
      duration: const Duration(milliseconds: 180),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: EdgeInsets.symmetric(
              horizontal: 10,
              vertical: compact ? 12 : 14,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: active
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: spec.gradient,
                    )
                  : null,
              color: active ? null : BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
              border: Border.all(
                color: active ? spec.accent.withValues(alpha: 0.8) : Colors.transparent,
                width: active ? 2 : 1,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: spec.accent.withValues(alpha: 0.28),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: compact ? 34 : 38,
                  height: compact ? 34 : 38,
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white.withValues(alpha: 0.16)
                        : spec.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    spec.type.icon,
                    size: compact ? 20 : 22,
                    color: active ? Colors.white : spec.accent,
                  ),
                ),
                SizedBox(height: compact ? 8 : 10),
                Text(
                  spec.title,
                  style: TextStyle(
                    fontSize: compact ? 13 : 14,
                    fontWeight: FontWeight.w900,
                    color: active ? Colors.white : BytzGoTheme.sheetText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  spec.subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: active
                        ? Colors.white.withValues(alpha: 0.88)
                        : spec.accent,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 6),
                  Text(
                    spec.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? Colors.white.withValues(alpha: 0.72)
                          : BytzGoTheme.sheetMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PassengerCountStepper extends StatelessWidget {
  const PassengerCountStepper({
    super.key,
    required this.count,
    required this.max,
    required this.onChanged,
    this.serviceLabel = 'Passengers',
  });

  final int count;
  final int max;
  final ValueChanged<int> onChanged;
  final String serviceLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BytzGoTheme.sheetDivider),
      ),
      child: Row(
        children: [
          Icon(Icons.groups_rounded, size: 20, color: BytzGoTheme.brandBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serviceLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: BytzGoTheme.sheetText,
                  ),
                ),
                Text(
                  'Max $max on this vehicle',
                  style: BytzGoTheme.sheetBody(11),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: count > 1 ? () => onChanged(count - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
            color: BytzGoTheme.accentDark,
          ),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: BytzGoTheme.sheetText,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: count < max ? () => onChanged(count + 1) : null,
            icon: const Icon(Icons.add_circle_outline),
            color: BytzGoTheme.accentDark,
          ),
        ],
      ),
    );
  }
}
