import '../shared/display_name.dart';

class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.ticketId,
    required this.senderId,
    required this.senderName,
    this.senderRole,
    required this.body,
    required this.createdAt,
    required this.isMine,
  });

  final String id;
  final String ticketId;
  final String senderId;
  final String senderName;
  final String? senderRole;
  final String body;
  final String createdAt;
  final bool isMine;

  String get displaySenderName => displayPersonName(
        senderName,
        role: senderRole,
        fallback: 'BytzGo Support',
      );

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    final role = (json['senderRole'] ?? json['sender_role'])?.toString();
    final rawName = (json['senderName'] ?? json['sender_name'])?.toString();
    return SupportMessage(
      id: json['id']?.toString() ?? '',
      ticketId: (json['ticketId'] ?? json['ticket_id'])?.toString() ?? '',
      senderId: (json['senderId'] ?? json['sender_id'])?.toString() ?? '',
      senderName: displayPersonName(rawName, role: role, fallback: 'BytzGo Support'),
      senderRole: role,
      body: json['body']?.toString() ?? '',
      createdAt: (json['createdAt'] ?? json['created_at'])?.toString() ?? '',
      isMine: json['isMine'] == true || json['is_mine'] == true,
    );
  }
}
