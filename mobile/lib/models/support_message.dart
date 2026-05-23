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

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    return SupportMessage(
      id: json['id']?.toString() ?? '',
      ticketId: (json['ticketId'] ?? json['ticket_id'])?.toString() ?? '',
      senderId: (json['senderId'] ?? json['sender_id'])?.toString() ?? '',
      senderName:
          (json['senderName'] ?? json['sender_name'])?.toString() ?? 'User',
      senderRole: (json['senderRole'] ?? json['sender_role'])?.toString(),
      body: json['body']?.toString() ?? '',
      createdAt: (json['createdAt'] ?? json['created_at'])?.toString() ?? '',
      isMine: json['isMine'] == true || json['is_mine'] == true,
    );
  }
}
