/// Customer bottom navigation — mirrors web `CustomerShell` tabs.
enum CustomerTab {
  courier,
  shops,
  activity,
  profile;

  String get label {
    switch (this) {
      case CustomerTab.courier:
        return 'Ride';
      case CustomerTab.shops:
        return 'Pharmacy';
      case CustomerTab.activity:
        return 'Activity';
      case CustomerTab.profile:
        return 'Account';
    }
  }
}
