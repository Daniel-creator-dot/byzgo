import 'package:flutter/material.dart';

import '../../models/ride_service.dart';
import '../../shared/theme.dart';

/// Bolt/Gokada-style service picker — Okada, Keke, or Package.
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

  @override
  Widget build(BuildContext context) {
    return Row(
      children: RideServiceType.values.map((type) {
        final active = type == selected;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: type != RideServiceType.keke ? 8 : 0,
            ),
            child: Material(
              color: active
                  ? BytzGoTheme.accent.withValues(alpha: 0.14)
                  : BytzGoTheme.sheetMuted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () => onSelected(type),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    vertical: compact ? 10 : 12,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: active
                          ? BytzGoTheme.accent
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        type.icon,
                        size: compact ? 22 : 26,
                        color: active
                            ? BytzGoTheme.accentDark
                            : BytzGoTheme.sheetText.withValues(alpha: 0.55),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        type.label,
                        style: TextStyle(
                          fontSize: compact ? 11 : 12,
                          fontWeight: FontWeight.w800,
                          color: active
                              ? BytzGoTheme.sheetText
                              : BytzGoTheme.sheetText.withValues(alpha: 0.7),
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 2),
                        Text(
                          type == RideServiceType.package
                              ? 'Delivery'
                              : 'Passenger',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: BytzGoTheme.sheetMuted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class PassengerCountStepper extends StatelessWidget {
  const PassengerCountStepper({
    super.key,
    required this.count,
    required this.max,
    required this.onChanged,
  });

  final int count;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Passengers',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: BytzGoTheme.sheetText,
          ),
        ),
        const Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: count > 1 ? () => onChanged(count - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
          color: BytzGoTheme.accentDark,
        ),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 16,
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
    );
  }
}
