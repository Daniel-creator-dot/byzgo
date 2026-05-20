import '../core/json_parse.dart';

class Product {
  const Product({
    required this.id,
    required this.vendorId,
    required this.name,
    required this.price,
    this.description,
    this.category,
    this.imageUrl,
    this.isAvailable = true,
    this.isApproved = true,
  });

  final String id;
  final String vendorId;
  final String name;
  final double price;
  final String? description;
  final String? category;
  final String? imageUrl;
  final bool isAvailable;
  final bool isApproved;

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id']?.toString() ?? '',
      vendorId: (json['vendorId'] ?? json['vendor_id'])?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      price: parseJsonDoubleOrZero(json['price']),
      description: json['description']?.toString(),
      category: json['category']?.toString(),
      imageUrl: (json['imageUrl'] ?? json['image_url'])?.toString(),
      isAvailable: json['is_available'] != false && json['isAvailable'] != false,
      isApproved: json['is_approved'] == true || json['isApproved'] == true,
    );
  }
}
