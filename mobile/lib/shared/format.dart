/// Ghana cedi display — port of `src/lib/format.ts`.
String formatCedis(num? amount, {int decimals = 2}) {
  final n = amount?.toDouble();
  if (n == null || !n.isFinite) {
    return '₵0.${'0' * decimals}';
  }
  return '₵${n.toStringAsFixed(decimals)}';
}

String formatCedisCompact(num? amount) {
  final n = amount?.toDouble();
  if (n == null || !n.isFinite) return '₵0';
  if (n >= 1000000) return '₵${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '₵${(n / 1000).toStringAsFixed(1)}k';
  return '₵${n.toStringAsFixed(2)}';
}
