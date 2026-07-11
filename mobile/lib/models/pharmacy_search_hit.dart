import 'product.dart';
import 'vendor.dart';

class PharmacySearchHit {
  const PharmacySearchHit({
    required this.vendor,
    required this.matches,
  });

  final Vendor vendor;
  final List<Product> matches;

  factory PharmacySearchHit.fromJson(Map<String, dynamic> json) {
    final vendorJson = json['vendor'];
    final matchesJson = json['matches'];
    return PharmacySearchHit(
      vendor: Vendor.fromJson(
        vendorJson is Map
            ? Map<String, dynamic>.from(vendorJson)
            : Map<String, dynamic>.from(json),
      ),
      matches: matchesJson is List
          ? matchesJson
              .whereType<Map>()
              .map((e) => Product.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}
