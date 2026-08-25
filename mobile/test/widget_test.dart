import 'package:flutter_test/flutter_test.dart';

import 'package:bytzgo_mobile/shared/delivery_pricing.dart';
import 'package:bytzgo_mobile/shared/format.dart';
import 'package:bytzgo_mobile/shared/ghana_location.dart';

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

  test('okada-first from Amasaman / Kasoa pickup text', () {
    expect(
      accraRideEmphasis(pickupAddress: 'Amasan, Accra'),
      AccraRideEmphasis.okada,
    );
    expect(
      accraRideEmphasis(pickupAddress: 'Kasoa New Town'),
      AccraRideEmphasis.okada,
    );
  });

  test('delivery-first from Cantonment / Asylum Down text', () {
    expect(
      accraRideEmphasis(pickupAddress: 'Cantonment, Accra'),
      AccraRideEmphasis.package,
    );
    expect(
      accraRideEmphasis(pickupAddress: 'Asyllum Down'),
      AccraRideEmphasis.package,
    );
  });

  test('pickup address beats user region and GPS', () {
    expect(
      accraRideEmphasis(
        pickupAddress: 'Spintex Road',
        userRegion: 'Kasoa',
        lat: 5.70,
        lng: -0.30,
      ),
      AccraRideEmphasis.package,
    );
  });

  test('user region then GPS when pickup is unresolved', () {
    expect(
      accraRideEmphasis(
        pickupAddress: 'Finding address…',
        userRegion: 'Weija',
      ),
      AccraRideEmphasis.okada,
    );
    expect(
      accraRideEmphasis(lat: 5.635, lng: -0.08),
      AccraRideEmphasis.package,
    );
  });
}
