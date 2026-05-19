enum AppRole {
  customer,
  vendor,
  rider,
  admin;

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
        return 'Vendor';
      case AppRole.rider:
        return 'Rider';
      case AppRole.admin:
        return 'Admin';
    }
  }
}
