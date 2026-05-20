class AdminStats {
  const AdminStats({
    this.driversOnline = 0,
    this.driversApproved = 0,
    this.driversTotal = 0,
    this.driversPending = 0,
    this.activeOrders = 0,
    this.ordersToday = 0,
    this.vendorsActive = 0,
    this.customersTotal = 0,
    this.grossRevenue = 0,
  });

  final int driversOnline;
  final int driversApproved;
  final int driversTotal;
  final int driversPending;
  final int activeOrders;
  final int ordersToday;
  final int vendorsActive;
  final int customersTotal;
  final double grossRevenue;

  factory AdminStats.fromJson(Map<String, dynamic> json) {
    int i(dynamic v) => int.tryParse('$v') ?? 0;
    double d(dynamic v) => double.tryParse('$v') ?? 0;
    return AdminStats(
      driversOnline: i(json['drivers_online']),
      driversApproved: i(json['drivers_approved']),
      driversTotal: i(json['drivers_total']),
      driversPending: i(json['drivers_pending']),
      activeOrders: i(json['active_orders']),
      ordersToday: i(json['orders_today']),
      vendorsActive: i(json['vendors_active']),
      customersTotal: i(json['customers_total']),
      grossRevenue: d(json['gross_revenue']),
    );
  }
}

class AdminLiveRider {
  const AdminLiveRider({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.region,
    this.status,
    required this.isOnline,
    this.lat,
    this.lng,
    this.locationUpdatedAt,
    this.activeTrips = 0,
    this.hasLocation = false,
  });

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? region;
  final String? status;
  final bool isOnline;
  final double? lat;
  final double? lng;
  final String? locationUpdatedAt;
  final int activeTrips;
  final bool hasLocation;

  factory AdminLiveRider.fromJson(Map<String, dynamic> json) {
    double? coord(dynamic v) {
      if (v == null) return null;
      return double.tryParse('$v');
    }

    return AdminLiveRider(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Driver',
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      region: json['region']?.toString(),
      status: json['status']?.toString(),
      isOnline: json['is_online'] == true,
      lat: coord(json['lat']),
      lng: coord(json['lng']),
      locationUpdatedAt: json['location_updated_at']?.toString(),
      activeTrips: int.tryParse('${json['active_trips']}') ?? 0,
      hasLocation: json['has_location'] == true,
    );
  }

  AdminLiveRider copyWith({
    double? lat,
    double? lng,
    bool? isOnline,
    bool? hasLocation,
    String? locationUpdatedAt,
  }) {
    return AdminLiveRider(
      id: id,
      name: name,
      email: email,
      phone: phone,
      region: region,
      status: status,
      isOnline: isOnline ?? this.isOnline,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      locationUpdatedAt: locationUpdatedAt ?? this.locationUpdatedAt,
      activeTrips: activeTrips,
      hasLocation: hasLocation ?? this.hasLocation,
    );
  }
}

class AdminOverview {
  const AdminOverview({required this.stats, required this.liveRiders});

  final AdminStats stats;
  final List<AdminLiveRider> liveRiders;

  factory AdminOverview.fromJson(Map<String, dynamic> json) {
    final ridersRaw = json['live_riders'];
    final riders = ridersRaw is List
        ? ridersRaw
            .whereType<Map>()
            .map((e) => AdminLiveRider.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <AdminLiveRider>[];
    return AdminOverview(
      stats: AdminStats.fromJson(
        Map<String, dynamic>.from(json['stats'] as Map? ?? {}),
      ),
      liveRiders: riders,
    );
  }

  List<AdminLiveRider> get onlineWithGps => liveRiders
      .where((r) => r.isOnline && r.hasLocation && r.lat != null && r.lng != null)
      .toList();
}
