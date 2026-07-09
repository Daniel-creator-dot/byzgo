import 'package:flutter/material.dart';

import '../../shared/theme.dart';

/// Okada / Keke / Bicycle picker — signup (light) and driver console (dark).
class RiderVehicleTypePicker extends StatelessWidget {
  const RiderVehicleTypePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.dark = false,
    this.compact = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool dark;
  final bool compact;

  static const options = [
    ('motorcycle', 'Okada', 'Motorcycle · rides & packages', Icons.two_wheeler),
    ('keke', 'Keke', 'Tricycle · up to 4 passengers', Icons.electric_rickshaw_outlined),
    ('bicycle', 'Bicycle', 'Package delivery only', Icons.pedal_bike_outlined),
  ];

  static String labelFor(String? type) {
    final t = (type ?? 'motorcycle').toLowerCase();
    return options
        .firstWhere((o) => o.$1 == t, orElse: () => options.first)
        .$2;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: options.map((opt) {
        final active = value == opt.$1;
        final bg = dark
            ? (active
                ? BytzGoTheme.accent.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.06))
            : (active
                ? BytzGoTheme.accent.withValues(alpha: 0.12)
                : const Color(0xFFF3F4F6));
        final border = active ? BytzGoTheme.accent : Colors.transparent;
        final titleColor = dark
            ? (active ? Colors.white : Colors.white70)
            : BytzGoTheme.sheetText;
        final subColor = dark
            ? Colors.white54
            : BytzGoTheme.sheetMuted;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => onChanged(opt.$1),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: compact ? 10 : 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border, width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(
                      opt.$4,
                      size: compact ? 22 : 26,
                      color: active ? BytzGoTheme.accentDark : subColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            opt.$2,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: compact ? 13 : 14,
                              color: titleColor,
                            ),
                          ),
                          if (!compact) ...[
                            const SizedBox(height: 2),
                            Text(
                              opt.$3,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: subColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (active)
                      Icon(
                        Icons.check_circle,
                        color: BytzGoTheme.accentDark,
                        size: compact ? 20 : 22,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
