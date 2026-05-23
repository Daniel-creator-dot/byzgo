import '../core/json_parse.dart';
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

  VendorShopPromo get promo => VendorShopPromo(
        shopOpenStatus: shopOpenStatus,
        shopStatusMessage: shopStatusMessage,
        shopDiscountLabel: shopDiscountLabel,
        shopDiscountPercent: shopDiscountPercent,
        shopPromoUpdatedAt: shopPromoUpdatedAt,
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
      coverImage: (json['cover_image'] ?? json['coverImage'])?.toString(),
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
      shopOpenStatus:
          (json['shop_open_status'] ?? shopOpenStatus).toString(),
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
    );
  }
}
