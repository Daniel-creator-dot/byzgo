import '../core/json_parse.dart';

class RiderStats {
  const RiderStats({
    this.tripsToday = 0,
    this.tripsWeek = 0,
    this.tripsMonth = 0,
    this.earningsToday = 0,
    this.earningsWeek = 0,
    this.earningsMonth = 0,
    this.avgRating,
    this.ratedTrips = 0,
    this.offersReceived = 0,
    this.offersAccepted = 0,
    this.offersDeclined = 0,
    this.acceptanceRate,
    this.activeTrips = 0,
  });

  final int tripsToday;
  final int tripsWeek;
  final int tripsMonth;
  final double earningsToday;
  final double earningsWeek;
  final double earningsMonth;
  final double? avgRating;
  final int ratedTrips;
  final int offersReceived;
  final int offersAccepted;
  final int offersDeclined;
  final double? acceptanceRate;
  final int activeTrips;

  factory RiderStats.fromJson(Map<String, dynamic> json) {
    return RiderStats(
      tripsToday: parseJsonInt(json['tripsToday'] ?? json['trips_today']) ?? 0,
      tripsWeek: parseJsonInt(json['tripsWeek'] ?? json['trips_week']) ?? 0,
      tripsMonth: parseJsonInt(json['tripsMonth'] ?? json['trips_month']) ?? 0,
      earningsToday: parseJsonDoubleOrZero(json['earningsToday'] ?? json['earnings_today']),
      earningsWeek: parseJsonDoubleOrZero(json['earningsWeek'] ?? json['earnings_week']),
      earningsMonth: parseJsonDoubleOrZero(json['earningsMonth'] ?? json['earnings_month']),
      avgRating: json['avgRating'] != null || json['avg_rating'] != null
          ? parseJsonDoubleOrZero(json['avgRating'] ?? json['avg_rating'])
          : null,
      ratedTrips: parseJsonInt(json['ratedTrips'] ?? json['rated_trips']) ?? 0,
      offersReceived: parseJsonInt(json['offersReceived'] ?? json['offers_received']) ?? 0,
      offersAccepted: parseJsonInt(json['offersAccepted'] ?? json['offers_accepted']) ?? 0,
      offersDeclined: parseJsonInt(json['offersDeclined'] ?? json['offers_declined']) ?? 0,
      acceptanceRate: json['acceptanceRate'] != null || json['acceptance_rate'] != null
          ? parseJsonDoubleOrZero(json['acceptanceRate'] ?? json['acceptance_rate'])
          : null,
      activeTrips: parseJsonInt(json['activeTrips'] ?? json['active_trips']) ?? 0,
    );
  }
}
