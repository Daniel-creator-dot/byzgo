import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/json_parse.dart';

class RiderCommissionSummary {
  const RiderCommissionSummary({
    required this.commissionPercent,
    required this.insurancePercent,
    required this.platformPercent,
    required this.totalOwed,
    required this.hasOverdue,
    required this.canGoOnline,
    required this.policy,
    required this.settlements,
  });

  final double commissionPercent;
  final double insurancePercent;
  final double platformPercent;
  final double totalOwed;
  final bool hasOverdue;
  final bool canGoOnline;
  final String policy;
  final List<RiderCommissionSettlement> settlements;

  factory RiderCommissionSummary.fromJson(Map<String, dynamic> json) {
    final list = json['settlements'];
    return RiderCommissionSummary(
      commissionPercent: parseJsonDouble(json['commission_percent']) ?? 10,
      insurancePercent: parseJsonDouble(json['insurance_percent']) ?? 3,
      platformPercent: parseJsonDouble(json['platform_percent']) ?? 7,
      totalOwed: parseJsonDouble(json['total_owed']) ?? 0,
      hasOverdue: json['has_overdue'] == true,
      canGoOnline: json['can_go_online'] != false,
      policy: json['policy']?.toString() ?? '',
      settlements: list is List
          ? list
              .whereType<Map>()
              .map((e) => RiderCommissionSettlement.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList()
          : const [],
    );
  }
}

class RiderCommissionSettlement {
  const RiderCommissionSettlement({
    required this.id,
    required this.settlementDate,
    required this.amountOwed,
    required this.status,
    required this.isOverdue,
    this.dueAt,
  });

  final String id;
  final String settlementDate;
  final double amountOwed;
  final String status;
  final bool isOverdue;
  final DateTime? dueAt;

  factory RiderCommissionSettlement.fromJson(Map<String, dynamic> json) {
    DateTime? due;
    final raw = json['due_at'];
    if (raw != null) {
      due = DateTime.tryParse(raw.toString());
    }
    return RiderCommissionSettlement(
      id: json['id']?.toString() ?? '',
      settlementDate: json['settlement_date']?.toString() ?? '',
      amountOwed: parseJsonDouble(json['amount_owed']) ?? 0,
      status: json['status']?.toString() ?? 'open',
      isOverdue: json['is_overdue'] == true,
      dueAt: due,
    );
  }
}

class RiderCommissionRepository {
  RiderCommissionRepository(this._api);

  final ApiClient _api;

  Future<RiderCommissionSummary> fetchSummary() async {
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/api/rider/commission/summary',
    );
    return RiderCommissionSummary.fromJson(
      Map<String, dynamic>.from(res.data ?? {}),
    );
  }

  Future<double> payCommission({String? settlementId}) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/rider/commission/pay',
      data: {if (settlementId != null) 'settlement_id': settlementId},
    );
    return parseJsonDouble(res.data?['balance']) ?? 0;
  }

  static String errorMessage(Object err) {
    if (err is DioException) {
      return ApiClient.messageFromDio(err, 'Commission request failed');
    }
    return err.toString();
  }

  static bool isCommissionOverdueError(Object err) {
    if (err is! DioException) return false;
    final data = err.response?.data;
    return data is Map && data['code'] == 'COMMISSION_OVERDUE';
  }
}
