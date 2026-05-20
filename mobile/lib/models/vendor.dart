import '../core/json_parse.dart';

class Vendor {
  const Vendor({
    required this.id,
    required this.name,
    this.lat,
    this.lng,
    this.address,
    this.region,
    this.phone,
    this.shopCategory,
    this.coverImage,
  });

  final String id;
  final String name;
  final double? lat;
  final double? lng;
  final String? address;
  final String? region;
  final String? phone;
  final String? shopCategory;
  final String? coverImage;

  factory Vendor.fromJson(Map<String, dynamic> json) {
    return Vendor(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      lat: parseJsonDouble(json['lat']),
      lng: parseJsonDouble(json['lng']),
      address: json['address']?.toString(),
      region: json['region']?.toString(),
      phone: json['phone']?.toString(),
      shopCategory: (json['shop_category'] ?? json['shopCategory'])?.toString(),
      coverImage: (json['cover_image'] ?? json['coverImage'])?.toString(),
    );
  }
}
