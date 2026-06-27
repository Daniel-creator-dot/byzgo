import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/json_parse.dart';
import '../../models/vehicle.dart';

class OwnerRepository {
  OwnerRepository(this._api);

  final ApiClient _api;

  Future<OwnerDashboard> fetchDashboard() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/owner/dashboard');
    final data = res.data;
    if (data == null) throw Exception('Empty owner dashboard response');
    final stats = OwnerDashboardStats.fromJson(
      Map<String, dynamic>.from(data['stats'] as Map? ?? {}),
    );
    final vehiclesRaw = data['vehicles'];
    final vehicles = vehiclesRaw is List
        ? vehiclesRaw
            .whereType<Map>()
            .map((e) => Vehicle.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <Vehicle>[];
    final owner = data['owner'];
    final status = owner is Map ? owner['status']?.toString() : null;
    return OwnerDashboard(
      stats: stats,
      vehicles: vehicles,
      ownerStatus: status,
    );
  }

  Future<List<Vehicle>> fetchVehicles() async {
    final res = await _api.dio.get<List<dynamic>>('/api/owner/vehicles');
    final list = res.data ?? [];
    return list
        .whereType<Map>()
        .map((e) => Vehicle.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Vehicle> createVehicle({
    required String plateNumber,
    String? make,
    String? model,
    int? year,
    String? color,
    String vehicleType = 'motorcycle',
    String status = 'active',
    String? notes,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/owner/vehicles',
      data: {
        'plate_number': plateNumber,
        if (make != null) 'make': make,
        if (model != null) 'model': model,
        if (year != null) 'year': year,
        if (color != null) 'color': color,
        'vehicle_type': vehicleType,
        'status': status,
        if (notes != null) 'notes': notes,
      },
    );
    final data = res.data;
    if (data == null) throw Exception('Empty create vehicle response');
    return Vehicle.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Vehicle> updateVehicle({
    required String id,
    String? plateNumber,
    String? make,
    String? model,
    int? year,
    String? color,
    String? vehicleType,
    String? status,
    String? notes,
    String? assignedRiderId,
    bool clearAssignedRider = false,
  }) async {
    final body = <String, dynamic>{};
    if (plateNumber != null) body['plate_number'] = plateNumber;
    if (make != null) body['make'] = make;
    if (model != null) body['model'] = model;
    if (year != null) body['year'] = year;
    if (color != null) body['color'] = color;
    if (vehicleType != null) body['vehicle_type'] = vehicleType;
    if (status != null) body['status'] = status;
    if (notes != null) body['notes'] = notes;
    if (clearAssignedRider) {
      body['assigned_rider_id'] = null;
    } else if (assignedRiderId != null) {
      body['assigned_rider_id'] = assignedRiderId;
    }

    final res = await _api.dio.patch<Map<String, dynamic>>(
      '/api/owner/vehicles/$id',
      data: body,
    );
    final data = res.data;
    if (data == null) throw Exception('Empty update vehicle response');
    return Vehicle.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> deleteVehicle(String id) async {
    await _api.dio.delete('/api/owner/vehicles/$id');
  }

  static String errorMessage(Object err) {
    if (err is DioException) {
      return ApiClient.messageFromDio(err, 'Vehicle request failed');
    }
    return err.toString();
  }
}
