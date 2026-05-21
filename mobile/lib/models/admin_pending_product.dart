import '../core/json_parse.dart';

class AdminPendingProduct {
  const AdminPendingProduct({
    required this.id,
    required this.name,
    required this.price,
    this.description,
    this.category,
    this.imageUrl,
    this.vendorId,
    this.vendorName,
  });

  final String id;
  final String name;
  final double price;
  final String? description;
  final String? category;
  final String? imageUrl;
  final String? vendorId;
  final String? vendorName;

  factory AdminPendingProduct.fromJson(Map<String, dynamic> json) {
    return AdminPendingProduct(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      price: parseJsonDoubleOrZero(json['price']),
      description: json['description']?.toString(),
      category: json['category']?.toString(),
      imageUrl: (json['imageUrl'] ?? json['image_url'])?.toString(),
      vendorId: (json['vendorId'] ?? json['vendor_id'])?.toString(),
      vendorName: json['vendor_name']?.toString(),
    );
  }
}
