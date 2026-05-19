import 'package:flutter/material.dart';

import '../../models/location_point.dart';
import '../../shared/widgets/ride_google_map.dart';

/// Map layer that rebuilds only when [riderPosition] changes (not whole shell).
class RiderDriveMapLayer extends StatelessWidget {
  const RiderDriveMapLayer({
    super.key,
    required this.riderPosition,
    required this.pickup,
    required this.destination,
    required this.showRoute,
  });

  final ValueNotifier<LocationPoint?> riderPosition;
  final LocationPoint? pickup;
  final LocationPoint? destination;
  final bool showRoute;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LocationPoint?>(
      valueListenable: riderPosition,
      builder: (context, pos, _) {
        return RideGoogleMap(
          pickup: pickup,
          destination: destination,
          riderPosition: pos,
          showRoute: showRoute,
        );
      },
    );
  }
}
