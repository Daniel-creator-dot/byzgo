import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/shop_conversation.dart';
import '../../models/shop_message.dart';

class ShopChatRepository {
  ShopChatRepository(this._api);

  final ApiClient _api;

  Future<List<ShopConversation>> fetchConversations() async {
    final res = await _api.dio.get<dynamic>('/api/shop/conversations');
    final data = res.data;
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => ShopConversation.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<ShopConversation> startWithVendor(String vendorId) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/shop/conversations',
      data: {'vendor_id': vendorId},
    );
    return ShopConversation.fromJson(Map<String, dynamic>.from(res.data ?? {}));
  }

  Future<ShopConversation> startWithCustomer(String customerId) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/shop/conversations',
      data: {'customer_id': customerId},
    );
    return ShopConversation.fromJson(Map<String, dynamic>.from(res.data ?? {}));
  }

  Future<List<ShopMessage>> fetchMessages(String conversationId) async {
    final res = await _api.dio.get<dynamic>(
      '/api/shop/conversations/$conversationId/messages',
    );
    final data = res.data;
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => ShopMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<ShopMessage> sendMessage(String conversationId, String body) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/shop/conversations/$conversationId/messages',
      data: {'body': body},
    );
    return ShopMessage.fromJson(Map<String, dynamic>.from(res.data ?? {}));
  }

  Future<void> markRead(String conversationId) async {
    await _api.dio.post<void>('/api/shop/conversations/$conversationId/read');
  }

  static String errorMessage(Object err) {
    if (err is DioException) {
      return ApiClient.messageFromDio(err, 'Chat failed');
    }
    if (err is Exception) return err.toString().replaceFirst('Exception: ', '');
    return err.toString();
  }
}
