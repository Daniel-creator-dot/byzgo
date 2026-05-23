import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/support_message.dart';
import '../../models/support_ticket.dart';

class CreateSupportTicketResult {
  const CreateSupportTicketResult({
    required this.ticket,
    required this.message,
  });

  final SupportTicket ticket;
  final SupportMessage message;
}

class SupportRepository {
  SupportRepository(this._api);

  final ApiClient _api;

  Future<CreateSupportTicketResult> createTicket({
    required String category,
    required String subject,
    required String description,
    String? relatedOrderId,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/support/tickets',
      data: {
        'category': category,
        'subject': subject,
        'description': description,
        if (relatedOrderId != null && relatedOrderId.isNotEmpty)
          'relatedOrderId': relatedOrderId,
      },
    );
    final data = Map<String, dynamic>.from(res.data ?? {});
    return CreateSupportTicketResult(
      ticket: SupportTicket.fromJson(
        Map<String, dynamic>.from(data['ticket'] as Map? ?? {}),
      ),
      message: SupportMessage.fromJson(
        Map<String, dynamic>.from(data['message'] as Map? ?? {}),
      ),
    );
  }

  Future<List<SupportTicket>> fetchMyTickets() async {
    final res = await _api.dio.get<List<dynamic>>('/api/support/tickets');
    return (res.data ?? [])
        .whereType<Map>()
        .map((e) => SupportTicket.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<SupportTicket> fetchTicket(String id) async {
    final res =
        await _api.dio.get<Map<String, dynamic>>('/api/support/tickets/$id');
    return SupportTicket.fromJson(Map<String, dynamic>.from(res.data ?? {}));
  }

  Future<List<SupportMessage>> fetchMessages(String ticketId) async {
    final res = await _api.dio.get<List<dynamic>>(
      '/api/support/tickets/$ticketId/messages',
    );
    return (res.data ?? [])
        .whereType<Map>()
        .map((e) => SupportMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<SupportMessage> sendMessage(String ticketId, String body) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/support/tickets/$ticketId/messages',
      data: {'body': body},
    );
    return SupportMessage.fromJson(Map<String, dynamic>.from(res.data ?? {}));
  }

  Future<List<SupportTicket>> fetchAdminTickets({
    String? status,
    String? category,
    String? role,
  }) async {
    final res = await _api.dio.get<List<dynamic>>(
      '/api/admin/support/tickets',
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
        if (category != null && category.isNotEmpty) 'category': category,
        if (role != null && role.isNotEmpty) 'role': role,
      },
    );
    return (res.data ?? [])
        .whereType<Map>()
        .map((e) => SupportTicket.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<SupportTicket> updateAdminTicket(
    String id, {
    String? status,
    bool assignSelf = false,
  }) async {
    final res = await _api.dio.patch<Map<String, dynamic>>(
      '/api/admin/support/tickets/$id',
      data: {
        if (status != null) 'status': status,
        if (assignSelf) 'assignSelf': true,
      },
    );
    return SupportTicket.fromJson(Map<String, dynamic>.from(res.data ?? {}));
  }

  static String errorMessage(Object err) {
    if (err is DioException) {
      return ApiClient.messageFromDio(err, 'Support request failed');
    }
    return err.toString();
  }
}
