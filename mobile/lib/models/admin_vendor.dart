class AdminVendor {
  const AdminVendor({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    this.phone,
    this.shopCategory,
    this.address,
    this.region,
    this.productCount = 0,
    this.pendingProducts = 0,
    this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String status;
  final String? phone;
  final String? shopCategory;
  final String? address;
  final String? region;
  final int productCount;
  final int pendingProducts;
  final String? createdAt;

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';

  factory AdminVendor.fromJson(Map<String, dynamic> json) {
    return AdminVendor(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      phone: json['phone']?.toString(),
      shopCategory: json['shop_category']?.toString(),
      address: json['address']?.toString(),
      region: json['region']?.toString(),
      productCount: (json['product_count'] as num?)?.toInt() ?? 0,
      pendingProducts: (json['pending_products'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at']?.toString(),
    );
  }
}

class CreateVendorResult {
  const CreateVendorResult({required this.vendor, required this.message});

  final AdminVendor vendor;
  final String message;

  factory CreateVendorResult.fromJson(Map<String, dynamic> json) {
    final user = Map<String, dynamic>.from(json['user'] as Map? ?? {});
    return CreateVendorResult(
      vendor: AdminVendor.fromJson(user),
      message: json['message']?.toString() ?? 'Store account created',
    );
  }
}
