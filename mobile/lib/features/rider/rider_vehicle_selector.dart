import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../features/auth/auth_repository.dart';
import '../../shared/theme.dart';

/// Driver chooses Okada (motorcycle) or Keke (tricycle) for job matching.
class RiderVehicleSelector extends StatelessWidget {
  const RiderVehicleSelector({super.key});

  static const _options = [
    ('motorcycle', 'Okada', Icons.two_wheeler),
    ('keke', 'Keke', Icons.electric_rickshaw_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final vehicle =
        context.select<Session, String?>((s) => s.user?.riderVehicleType) ??
            'motorcycle';
    return Row(
      children: _options.map((opt) {
        final active = vehicle == opt.$1;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: opt.$1 == 'motorcycle' ? 8 : 0),
            child: Material(
              color: active
                  ? BytzGoTheme.accent.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => _setVehicle(context, opt.$1),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    children: [
                      Icon(opt.$3, color: active ? BytzGoTheme.accent : Colors.white54, size: 22),
                      const SizedBox(height: 4),
                      Text(
                        opt.$2,
                        style: TextStyle(
                          color: active ? Colors.white : Colors.white60,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
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

  Future<void> _setVehicle(BuildContext context, String type) async {
    try {
      final user =
          await context.read<AuthRepository>().updateRiderVehicleType(type);
      if (!context.mounted) return;
      context.read<Session>().patchUser(user);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AuthRepository.errorMessage(e))),
      );
    }
  }
}
