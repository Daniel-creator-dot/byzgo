import 'package:flutter_test/flutter_test.dart';

import 'package:bytzgo_mobile/shared/delivery_pricing.dart';
import 'package:bytzgo_mobile/shared/format.dart';

void main() {
  test('formatCedis shows cedi symbol', () {
    expect(formatCedis(12.5), '₵12.50');
  });

  test('haversine distance is positive for two Ghana points', () {
    // Accra-ish → Kumasi-ish (rough)
    final km = haversineDistanceKm(5.6037, -0.187, 6.6885, -1.6244);
    expect(km, greaterThan(100));
    expect(km, lessThan(300));
  });
}
