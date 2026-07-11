import '../shared/display_name.dart';

class ShopMessage {
  const ShopMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    this.senderRole,
    required this.body,
    required this.createdAt,
    required this.isMine,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String? senderRole;
  final String body;
  final String createdAt;
  final bool isMine;

  String get displaySenderName => displayPersonName(
        senderName,
        role: senderRole,
        fallback: 'Pharmacy',
      );

  factory ShopMessage.fromJson(Map<String, dynamic> json) {
    final role = (json['senderRole'] ?? json['sender_role'])?.toString();
    final rawName = (json['senderName'] ?? json['sender_name'])?.toString();
    return ShopMessage(
      id: json['id']?.toString() ?? '',
      conversationId:
          (json['conversationId'] ?? json['conversation_id'])?.toString() ?? '',
      senderId: (json['senderId'] ?? json['sender_id'])?.toString() ?? '',
      senderName: displayPersonName(rawName, role: role, fallback: 'Pharmacy'),
      senderRole: role,
      body: json['body']?.toString() ?? '',
      createdAt: (json['createdAt'] ?? json['created_at'])?.toString() ?? '',
      isMine: json['isMine'] == true || json['is_mine'] == true,
    );
  }
}
