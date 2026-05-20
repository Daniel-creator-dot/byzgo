/// Display helpers for pharmacy / formulary product data.
String formatPharmacyCategory(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'Medicines';

  var s = raw.trim();
  if (s.contains(' - ')) {
    s = s.split(' - ').first.trim();
  }
  s = s.replaceFirst(
    RegExp(
      r'^[\d.]+\s*(packs?|tablet|capsule|other)?\s*',
      caseSensitive: false,
    ),
    '',
  );
  s = s.replaceFirst(RegExp(r'^(other|miscellaneous)\s*', caseSensitive: false), '');
  if (s.length < 2) return 'Medicines';
  if (s.length > 48) return '${s.substring(0, 45)}…';
  return s[0].toUpperCase() + s.substring(1);
}

int? stockQtyFromDescription(String? description) {
  if (description == null || description.isEmpty) return null;
  final m = RegExp(r'In stock:\s*(-?\d+)', caseSensitive: false).firstMatch(description);
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}
