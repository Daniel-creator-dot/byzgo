/// Live storefront status + discount shown to customers on the Shops tab.
class VendorShopPromo {
  const VendorShopPromo({
    required this.shopOpenStatus,
    this.shopStatusMessage,
    this.shopDiscountLabel,
    this.shopDiscountPercent,
    this.shopPromoUpdatedAt,
  });

  final String shopOpenStatus;
  final String? shopStatusMessage;
  final String? shopDiscountLabel;
  final double? shopDiscountPercent;
  final DateTime? shopPromoUpdatedAt;

  bool get isOpen => shopOpenStatus == 'open';
  bool get isBusy => shopOpenStatus == 'busy';
  bool get isClosed => shopOpenStatus == 'closed';

  bool get hasCustomerFacingPromo =>
      (shopStatusMessage != null && shopStatusMessage!.trim().isNotEmpty) ||
      (shopDiscountLabel != null && shopDiscountLabel!.trim().isNotEmpty) ||
      !isOpen;

  String get openStatusLabel {
    switch (shopOpenStatus) {
      case 'busy':
        return 'Busy';
      case 'closed':
        return 'Closed';
      default:
        return 'Open';
    }
  }

  factory VendorShopPromo.fromJson(Map<String, dynamic> json) {
    final pct = json['shop_discount_percent'];
    return VendorShopPromo(
      shopOpenStatus:
          (json['shop_open_status'] ?? json['shopOpenStatus'] ?? 'open').toString(),
      shopStatusMessage:
          (json['shop_status_message'] ?? json['shopStatusMessage'])?.toString(),
      shopDiscountLabel:
          (json['shop_discount_label'] ?? json['shopDiscountLabel'])?.toString(),
      shopDiscountPercent: pct == null ? null : double.tryParse(pct.toString()),
      shopPromoUpdatedAt: _parseTime(
        json['shop_promo_updated_at'] ?? json['shopPromoUpdatedAt'],
      ),
    );
  }

  static DateTime? _parseTime(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  VendorShopPromo copyWith({
    String? shopOpenStatus,
    String? shopStatusMessage,
    String? shopDiscountLabel,
    double? shopDiscountPercent,
    DateTime? shopPromoUpdatedAt,
    bool clearMessage = false,
    bool clearDiscountLabel = false,
    bool clearDiscountPercent = false,
  }) {
    return VendorShopPromo(
      shopOpenStatus: shopOpenStatus ?? this.shopOpenStatus,
      shopStatusMessage:
          clearMessage ? null : (shopStatusMessage ?? this.shopStatusMessage),
      shopDiscountLabel: clearDiscountLabel
          ? null
          : (shopDiscountLabel ?? this.shopDiscountLabel),
      shopDiscountPercent: clearDiscountPercent
          ? null
          : (shopDiscountPercent ?? this.shopDiscountPercent),
      shopPromoUpdatedAt: shopPromoUpdatedAt ?? this.shopPromoUpdatedAt,
    );
  }
}
