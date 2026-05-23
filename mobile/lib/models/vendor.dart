import '../core/json_parse.dart';
import '../shared/client_image_url.dart';
import 'vendor_shop_promo.dart';

class Vendor {
  const Vendor({
    required this.id,
    required this.name,
    this.email,
    this.lat,
    this.lng,
    this.address,
    this.region,
    this.phone,
    this.shopCategory,
    this.coverImage,
    this.shopOpenStatus = 'open',
    this.shopStatusMessage,
    this.shopDiscountLabel,
    this.shopDiscountPercent,
    this.shopPromoUpdatedAt,
    this.shopStoryImage,
    this.shopStoryPostedAt,
    this.shopStoryExpiresAt,
    this.hasActiveStory = false,
  });

  final String id;
  final String name;
  final String? email;
  final double? lat;
  final double? lng;
  final String? address;
  final String? region;
  final String? phone;
  final String? shopCategory;
  final String? coverImage;
  final String shopOpenStatus;
  final String? shopStatusMessage;
  final String? shopDiscountLabel;
  final double? shopDiscountPercent;
  final DateTime? shopPromoUpdatedAt;
  final String? shopStoryImage;
  final DateTime? shopStoryPostedAt;
  final DateTime? shopStoryExpiresAt;
  final bool hasActiveStory;

  VendorShopPromo get promo => VendorShopPromo(
        shopOpenStatus: shopOpenStatus,
        shopStatusMessage: shopStatusMessage,
        shopDiscountLabel: shopDiscountLabel,
        shopDiscountPercent: shopDiscountPercent,
        shopPromoUpdatedAt: shopPromoUpdatedAt,
        shopStoryImage: shopStoryImage,
        shopStoryPostedAt: shopStoryPostedAt,
        shopStoryExpiresAt: shopStoryExpiresAt,
        hasActiveStory: hasActiveStory,
      );

  bool get hasCustomerFacingPromo => promo.hasCustomerFacingPromo;

  factory Vendor.fromJson(Map<String, dynamic> json) {
    final pct = json['shop_discount_percent'] ?? json['shopDiscountPercent'];
    return Vendor(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString(),
      lat: parseJsonDouble(json['lat']),
      lng: parseJsonDouble(json['lng']),
      address: json['address']?.toString(),
      region: json['region']?.toString(),
      phone: json['phone']?.toString(),
      shopCategory: (json['shop_category'] ?? json['shopCategory'])?.toString(),
      coverImage: ClientImageUrl.resolve(
        (json['cover_image'] ?? json['coverImage'])?.toString(),
      ),
      shopOpenStatus:
          (json['shop_open_status'] ?? json['shopOpenStatus'] ?? 'open').toString(),
      shopStatusMessage:
          (json['shop_status_message'] ?? json['shopStatusMessage'])?.toString(),
      shopDiscountLabel:
          (json['shop_discount_label'] ?? json['shopDiscountLabel'])?.toString(),
      shopDiscountPercent: pct == null ? null : double.tryParse(pct.toString()),
      shopPromoUpdatedAt: DateTime.tryParse(
        (json['shop_promo_updated_at'] ?? json['shopPromoUpdatedAt'] ?? '')
            .toString(),
      ),
      shopStoryImage:
          (json['shop_story_image'] ?? json['shopStoryImage'])?.toString(),
      shopStoryPostedAt: DateTime.tryParse(
        (json['shop_story_posted_at'] ?? json['shopStoryPostedAt'] ?? '')
            .toString(),
      ),
      shopStoryExpiresAt: DateTime.tryParse(
        (json['shop_story_expires_at'] ?? json['shopStoryExpiresAt'] ?? '')
            .toString(),
      ),
      hasActiveStory: json['has_active_story'] == true,
    );
  }

  Vendor copyWithPromo(Map<String, dynamic> json) {
    return Vendor(
      id: id,
      name: json['name']?.toString() ?? name,
      email: email,
      lat: lat,
      lng: lng,
      address: address,
      region: region,
      phone: phone,
      shopCategory: shopCategory,
      coverImage: coverImage,
      shopOpenStatus: (json['shop_open_status'] ?? shopOpenStatus).toString(),
      shopStatusMessage: json.containsKey('shop_status_message')
          ? json['shop_status_message']?.toString()
          : shopStatusMessage,
      shopDiscountLabel: json.containsKey('shop_discount_label')
          ? json['shop_discount_label']?.toString()
          : shopDiscountLabel,
      shopDiscountPercent: json.containsKey('shop_discount_percent')
          ? (json['shop_discount_percent'] == null
              ? null
              : double.tryParse(json['shop_discount_percent'].toString()))
          : shopDiscountPercent,
      shopPromoUpdatedAt: json.containsKey('shop_promo_updated_at')
          ? DateTime.tryParse((json['shop_promo_updated_at'] ?? '').toString())
          : shopPromoUpdatedAt,
      shopStoryImage: json.containsKey('shop_story_image')
          ? json['shop_story_image']?.toString()
          : shopStoryImage,
      shopStoryPostedAt: json.containsKey('shop_story_posted_at')
          ? DateTime.tryParse((json['shop_story_posted_at'] ?? '').toString())
          : shopStoryPostedAt,
      shopStoryExpiresAt: json.containsKey('shop_story_expires_at')
          ? DateTime.tryParse((json['shop_story_expires_at'] ?? '').toString())
          : shopStoryExpiresAt,
      hasActiveStory: json.containsKey('has_active_story')
          ? json['has_active_story'] == true
          : hasActiveStory,
    );
  }
}
