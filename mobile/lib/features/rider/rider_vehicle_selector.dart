import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../features/auth/auth_repository.dart';
import '../../shared/widgets/rider_vehicle_type_picker.dart';

/// Driver changes vehicle type from Drive tab (after registration).
class RiderVehicleSelector extends StatelessWidget {
  const RiderVehicleSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final vehicle =
        context.select<Session, String?>((s) => s.user?.riderVehicleType) ??
            'motorcycle';
    return RiderVehicleTypePicker(
      value: vehicle,
      dark: true,
      compact: true,
      onChanged: (type) => _setVehicle(context, type),
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
