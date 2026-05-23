/// Live storefront status + discount shown to customers on the Shops tab.
class VendorShopPromo {
  const VendorShopPromo({
    required this.shopOpenStatus,
    this.shopStatusMessage,
    this.shopDiscountLabel,
    this.shopDiscountPercent,
    this.shopPromoUpdatedAt,
    this.shopStoryImage,
    this.shopStoryPostedAt,
    this.shopStoryExpiresAt,
    this.hasActiveStory = false,
  });

  final String shopOpenStatus;
  final String? shopStatusMessage;
  final String? shopDiscountLabel;
  final double? shopDiscountPercent;
  final DateTime? shopPromoUpdatedAt;
  final String? shopStoryImage;
  final DateTime? shopStoryPostedAt;
  final DateTime? shopStoryExpiresAt;
  final bool hasActiveStory;

  bool get isOpen => shopOpenStatus == 'open';
  bool get isBusy => shopOpenStatus == 'busy';
  bool get isClosed => shopOpenStatus == 'closed';

  bool get hasCustomerFacingPromo =>
      hasActiveStory ||
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

  Duration? get storyTimeLeft {
    if (shopStoryExpiresAt == null) return null;
    final left = shopStoryExpiresAt!.difference(DateTime.now());
    if (left.isNegative) return Duration.zero;
    return left;
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
      shopStoryImage:
          (json['shop_story_image'] ?? json['shopStoryImage'])?.toString(),
      shopStoryPostedAt: _parseTime(
        json['shop_story_posted_at'] ?? json['shopStoryPostedAt'],
      ),
      shopStoryExpiresAt: _parseTime(
        json['shop_story_expires_at'] ?? json['shopStoryExpiresAt'],
      ),
      hasActiveStory: json['has_active_story'] == true,
    );
  }

  static DateTime? _parseTime(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }
}
