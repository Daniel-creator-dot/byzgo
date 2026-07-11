enum AppRole {
  customer,
  vendor,
  rider,
  admin,
  owner;

  static AppRole fromString(String? value) {
    return AppRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => AppRole.customer,
    );
  }

  String get label {
    switch (this) {
      case AppRole.customer:
        return 'Customer';
      case AppRole.vendor:
        return 'Pharmacy / Health retailer';
      case AppRole.rider:
        return 'Driver / Rider';
      case AppRole.admin:
        return 'Admin';
      case AppRole.owner:
        return 'Fleet owner';
    }
  }
}
