/// Okada (motorcycle) vs Keke (tricycle) — used for fare and rider matching.
class VehicleType {
  static const String bike = 'bike';
  static const String tricycle = 'tricycle';

  static const List<String> all = [bike, tricycle];

  static String label(String type) {
    switch (type) {
      case tricycle:
        return 'Keke';
      case bike:
      default:
        return 'Okada';
    }
  }

  static String subtitle(String type) {
    switch (type) {
      case tricycle:
        return 'Tricycle · more seats';
      case bike:
      default:
        return 'Motorcycle · fastest';
    }
  }

  static String iconAsset(String type) {
    switch (type) {
      case tricycle:
        return 'assets/branding/onboarding_delivery.png';
      case bike:
      default:
        return 'assets/branding/hero_delivery.png';
    }
  }
}
