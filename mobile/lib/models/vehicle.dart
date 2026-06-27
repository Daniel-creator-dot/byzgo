import '../core/json_parse.dart';

class Vehicle {
  const Vehicle({
    required this.id,
    required this.ownerId,
    required this.plateNumber,
    this.make,
    this.model,
    this.year,
    this.color,
    required this.vehicleType,
    required this.status,
    this.assignedRiderId,
    this.assignedRiderName,
    this.assignedRiderPhone,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String ownerId;
  final String plateNumber;
  final String? make;
  final String? model;
  final int? year;
  final String? color;
  final String vehicleType;
  final String status;
  final String? assignedRiderId;
  final String? assignedRiderName;
  final String? assignedRiderPhone;
  final String? notes;
  final String? createdAt;
  final String? updatedAt;

  String get displayName {
    final parts = <String>[];
    if (make?.trim().isNotEmpty == true) parts.add(make!.trim());
    if (model?.trim().isNotEmpty == true) parts.add(model!.trim());
    if (parts.isEmpty) return plateNumber;
    return '${parts.join(' ')} · $plateNumber';
  }

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json['id']?.toString() ?? '',
      ownerId: json['owner_id']?.toString() ?? '',
      plateNumber: json['plate_number']?.toString() ?? '',
      make: json['make']?.toString(),
      model: json['model']?.toString(),
      year: parseJsonInt(json['year']),
      color: json['color']?.toString(),
      vehicleType: json['vehicle_type']?.toString() ?? 'motorcycle',
      status: json['status']?.toString() ?? 'active',
      assignedRiderId: json['assigned_rider_id']?.toString(),
      assignedRiderName: json['assigned_rider_name']?.toString(),
      assignedRiderPhone: json['assigned_rider_phone']?.toString(),
      notes: json['notes']?.toString(),
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }
}

class OwnerDashboardStats {
  const OwnerDashboardStats({
    required this.totalVehicles,
    required this.activeVehicles,
    required this.assignedVehicles,
    required this.maintenanceVehicles,
  });

  final int totalVehicles;
  final int activeVehicles;
  final int assignedVehicles;
  final int maintenanceVehicles;

  factory OwnerDashboardStats.fromJson(Map<String, dynamic> json) {
    return OwnerDashboardStats(
      totalVehicles: parseJsonInt(json['total_vehicles']) ?? 0,
      activeVehicles: parseJsonInt(json['active_vehicles']) ?? 0,
      assignedVehicles: parseJsonInt(json['assigned_vehicles']) ?? 0,
      maintenanceVehicles: parseJsonInt(json['maintenance_vehicles']) ?? 0,
    );
  }
}

class OwnerDashboard {
  const OwnerDashboard({
    required this.stats,
    required this.vehicles,
    this.ownerStatus,
  });

  final OwnerDashboardStats stats;
  final List<Vehicle> vehicles;
  final String? ownerStatus;
}
