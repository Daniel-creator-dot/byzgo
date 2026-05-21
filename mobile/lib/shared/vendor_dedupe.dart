import '../models/vendor.dart';

const _primecareCanonicalEmail = 'vendor@bytzgo.net';

bool isPrimeCareVendor(Vendor vendor) {
  final n = vendor.name.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (n.contains('primecare')) return true;
  return vendor.name.toLowerCase().contains('prime care');
}

/// Show a single Primecare Pharmacy even if the database has duplicate vendor rows.
List<Vendor> dedupeVendors(List<Vendor> vendors) {
  final primecare = vendors.where(isPrimeCareVendor).toList();
  final rest = vendors.where((v) => !isPrimeCareVendor(v)).toList();
  if (primecare.length <= 1) return vendors;
  Vendor keeper = primecare.first;
  for (final v in primecare) {
    if (v.email?.toLowerCase() == _primecareCanonicalEmail) {
      keeper = v;
      break;
    }
  }
  return [...rest, keeper];
}
