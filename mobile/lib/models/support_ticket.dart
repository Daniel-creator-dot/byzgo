class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.displayId,
    required this.category,
    required this.subject,
    required this.status,
    required this.createdBy,
    required this.createdByRole,
    this.creatorName,
    this.creatorEmail,
    this.relatedOrderId,
    this.assignedAdminId,
    this.assignedAdminName,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.messageCount,
  });

  final String id;
  final String displayId;
  final String category;
  final String subject;
  final String status;
  final String createdBy;
  final String createdByRole;
  final String? creatorName;
  final String? creatorEmail;
  final String? relatedOrderId;
  final String? assignedAdminId;
  final String? assignedAdminName;
  final String createdAt;
  final String updatedAt;
  final String? lastMessageAt;
  final String? lastMessagePreview;
  final int? messageCount;

  bool get isOpen => status == 'open' || status == 'pending';

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    return SupportTicket(
      id: json['id']?.toString() ?? '',
      displayId: (json['displayId'] ?? json['display_id'])?.toString() ?? '',
      category: json['category']?.toString() ?? 'other',
      subject: json['subject']?.toString() ?? '',
      status: json['status']?.toString() ?? 'open',
      createdBy: (json['createdBy'] ?? json['created_by'])?.toString() ?? '',
      createdByRole:
          (json['createdByRole'] ?? json['created_by_role'])?.toString() ?? '',
      creatorName: (json['creatorName'] ?? json['creator_name'])?.toString(),
      creatorEmail:
          (json['creatorEmail'] ?? json['creator_email'])?.toString(),
      relatedOrderId:
          (json['relatedOrderId'] ?? json['related_order_id'])?.toString(),
      assignedAdminId:
          (json['assignedAdminId'] ?? json['assigned_admin_id'])?.toString(),
      assignedAdminName: (json['assignedAdminName'] ??
              json['assigned_admin_name'])
          ?.toString(),
      createdAt: (json['createdAt'] ?? json['created_at'])?.toString() ?? '',
      updatedAt: (json['updatedAt'] ?? json['updated_at'])?.toString() ?? '',
      lastMessageAt:
          (json['lastMessageAt'] ?? json['last_message_at'])?.toString(),
      lastMessagePreview: (json['lastMessagePreview'] ??
              json['last_message_preview'])
          ?.toString(),
      messageCount: json['messageCount'] is int
          ? json['messageCount'] as int
          : int.tryParse(json['messageCount']?.toString() ?? ''),
    );
  }

  static String categoryLabel(String category) {
    switch (category) {
      case 'order':
        return 'Order issue';
      case 'payment':
        return 'Payment & wallet';
      case 'account':
        return 'Account';
      case 'delivery':
        return 'Delivery';
      case 'shop':
        return 'Shop / menu';
      default:
        return 'Other';
    }
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'open':
        return 'Open';
      case 'pending':
        return 'Awaiting you';
      case 'resolved':
        return 'Resolved';
      case 'closed':
        return 'Closed';
      default:
        return status;
    }
  }

  static String roleLabel(String role) {
    switch (role) {
      case 'customer':
        return 'Customer';
      case 'vendor':
        return 'Vendor';
      case 'rider':
        return 'Driver';
      case 'admin':
        return 'Admin';
      case 'owner':
        return 'Fleet owner';
      default:
        return role;
    }
  }
}
