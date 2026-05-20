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

  /// Parsed from description seeded by Primecare formulary (`In stock: N`).
  int? get stockQty {
    final d = description;
    if (d == null || d.isEmpty) return null;
    final m = RegExp(r'In stock:\s*(-?\d+)', caseSensitive: false).firstMatch(d);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  bool get canAddToCart {
    if (!isAvailable || !isApproved) return false;
    final stock = stockQty;
    return stock == null || stock > 0;
  }

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
