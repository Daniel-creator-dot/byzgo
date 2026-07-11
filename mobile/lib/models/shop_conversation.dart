class ShopConversation {
  const ShopConversation({
    required this.id,
    required this.customerId,
    required this.vendorId,
    required this.customerName,
    required this.vendorName,
    this.shopCategory,
    this.lastMessageAt,
    this.lastMessagePreview = '',
    this.unreadCount = 0,
    this.peerName = '',
  });

  final String id;
  final String customerId;
  final String vendorId;
  final String customerName;
  final String vendorName;
  final String? shopCategory;
  final String? lastMessageAt;
  final String lastMessagePreview;
  final int unreadCount;
  final String peerName;

  factory ShopConversation.fromJson(Map<String, dynamic> json) {
    return ShopConversation(
      id: json['id']?.toString() ?? '',
      customerId: (json['customerId'] ?? json['customer_id'])?.toString() ?? '',
      vendorId: (json['vendorId'] ?? json['vendor_id'])?.toString() ?? '',
      customerName: (json['customerName'] ?? json['customer_name'])?.toString() ?? 'Customer',
      vendorName: (json['vendorName'] ?? json['vendor_name'])?.toString() ?? 'Pharmacy',
      shopCategory: (json['shopCategory'] ?? json['shop_category'])?.toString(),
      lastMessageAt: (json['lastMessageAt'] ?? json['last_message_at'])?.toString(),
      lastMessagePreview:
          (json['lastMessagePreview'] ?? json['last_message_preview'])?.toString() ?? '',
      unreadCount: int.tryParse(
            (json['unreadCount'] ?? json['unread_count'] ?? '0').toString(),
          ) ??
          0,
      peerName: (json['peerName'] ?? json['peer_name'])?.toString() ?? '',
    );
  }
}
