import 'package:flutter/material.dart';

/// Ride tiers — okada (motorcycle taxi), keke (tricycle), package (courier).
/// Modeled on Gokada/Bolt Bike (NG) and Rapido/auto (IN).
enum RideServiceType {
  package,
  okada,
  keke;

  String get id => name;

  String get label {
    switch (this) {
      case RideServiceType.package:
        return 'Package';
      case RideServiceType.okada:
        return 'Okada';
      case RideServiceType.keke:
        return 'Keke · Pragia';
    }
  }

  String get subtitle {
    switch (this) {
      case RideServiceType.package:
        return 'Send items · bike courier';
      case RideServiceType.okada:
        return 'Ride · 1–2 people · motorcycle';
      case RideServiceType.keke:
        return 'Ride · up to 4 · tricycle (Pragia)';
    }
  }

  IconData get icon {
    switch (this) {
      case RideServiceType.package:
        return Icons.inventory_2_outlined;
      case RideServiceType.okada:
        return Icons.two_wheeler;
      case RideServiceType.keke:
        return Icons.electric_rickshaw_outlined;
    }
  }

  int get maxPassengers {
    switch (this) {
      case RideServiceType.package:
        return 0;
      case RideServiceType.okada:
        return 2;
      case RideServiceType.keke:
        return 4;
    }
  }

  bool get isPassengerRide => this != RideServiceType.package;

  static RideServiceType fromString(String? value) {
    final s = (value ?? 'package').trim().toLowerCase();
    if (s == 'okada' || s == 'bike' || s == 'motorbike') return RideServiceType.okada;
    if (s == 'keke' || s == 'tricycle' || s == 'napep' || s == 'auto') {
      return RideServiceType.keke;
    }
    if (s == 'courier' || s == 'delivery') return RideServiceType.package;
    return RideServiceType.values.firstWhere(
      (t) => t.name == s,
      orElse: () => RideServiceType.package,
    );
  }
}

class RideServiceOption {
  const RideServiceOption({
    required this.type,
    required this.pricePerKm,
    required this.minFee,
  });

  final RideServiceType type;
  final double pricePerKm;
  final double minFee;

  factory RideServiceOption.fromJson(Map<String, dynamic> json) {
    return RideServiceOption(
      type: RideServiceType.fromString(json['id']?.toString()),
      pricePerKm: (json['price_per_km'] as num?)?.toDouble() ?? 4,
      minFee: (json['min_fee'] as num?)?.toDouble() ?? 5,
    );
  }
}

String rideServiceItemLabel(RideServiceType type, {int passengers = 1}) {
  switch (type) {
    case RideServiceType.okada:
      return 'Okada ride · $passengers passenger${passengers == 1 ? '' : 's'}';
    case RideServiceType.keke:
      return 'Keke ride · $passengers passenger${passengers == 1 ? '' : 's'}';
    case RideServiceType.package:
      return 'Package delivery';
  }
}

String rideServiceRequestLabel(RideServiceType type) {
  switch (type) {
    case RideServiceType.okada:
      return 'Request Okada';
    case RideServiceType.keke:
      return 'Request Keke (Pragia)';
    case RideServiceType.package:
      return 'Request bike';
  }
}
