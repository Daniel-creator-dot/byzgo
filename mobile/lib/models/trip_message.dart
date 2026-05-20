class TripMessage {
  const TripMessage({
    required this.id,
    required this.orderId,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.createdAt,
    required this.isMine,
  });

  final String id;
  final String orderId;
  final String senderId;
  final String senderName;
  final String body;
  final String createdAt;
  final bool isMine;

  factory TripMessage.fromJson(Map<String, dynamic> json) {
    return TripMessage(
      id: json['id']?.toString() ?? '',
      orderId: (json['orderId'] ?? json['order_id'])?.toString() ?? '',
      senderId: (json['senderId'] ?? json['sender_id'])?.toString() ?? '',
      senderName: (json['senderName'] ?? json['sender_name'])?.toString() ?? 'User',
      body: json['body']?.toString() ?? '',
      createdAt: (json['createdAt'] ?? json['created_at'])?.toString() ?? '',
      isMine: json['isMine'] == true || json['is_mine'] == true,
    );
  }
}
