class AppUpdateNoticeConfig {
  const AppUpdateNoticeConfig({
    required this.enabled,
    required this.title,
    required this.message,
    required this.minVersion,
    required this.minBuild,
    required this.iosUrl,
    required this.androidUrl,
    required this.force,
    required this.id,
  });

  final bool enabled;
  final String title;
  final String message;
  final String minVersion;
  final int minBuild;
  final String iosUrl;
  final String androidUrl;
  final bool force;
  final String id;

  factory AppUpdateNoticeConfig.fromJson(Map<String, dynamic> json) {
    final enabledRaw = json['enabled'] ?? json['app_update_enabled'];
    final forceRaw = json['force'] ?? json['app_update_force'];
    return AppUpdateNoticeConfig(
      enabled: enabledRaw == true || enabledRaw == 'true' || enabledRaw == 1,
      title: (json['title'] ?? json['app_update_title'] ?? 'New BytzGo update')
          .toString()
          .trim(),
      message: (json['message'] ?? json['app_update_message'] ?? '')
          .toString()
          .trim(),
      minVersion: (json['min_version'] ?? json['app_update_min_version'] ?? '')
          .toString()
          .trim(),
      minBuild: int.tryParse(
            (json['min_build'] ?? json['app_update_min_build'] ?? '0').toString(),
          ) ??
          0,
      iosUrl: (json['ios_url'] ?? json['app_update_ios_url'] ?? '').toString().trim(),
      androidUrl:
          (json['android_url'] ?? json['app_update_android_url'] ?? '').toString().trim(),
      force: forceRaw == true || forceRaw == 'true' || forceRaw == 1,
      id: (json['id'] ?? '').toString(),
    );
  }

  bool get hasMessage => message.isNotEmpty;

  bool shouldShowFor({required String currentVersion, required int currentBuild}) {
    if (!enabled || !hasMessage) return false;
    if (minVersion.isEmpty && minBuild <= 0) return true;
    if (minVersion.isNotEmpty && _isOlderVersion(currentVersion, minVersion)) {
      return true;
    }
    if (minBuild > 0 && currentBuild < minBuild) return true;
    return false;
  }

  static bool _isOlderVersion(String current, String minimum) {
    List<int> parts(String raw) => raw
        .split(RegExp(r'[^0-9]+'))
        .where((p) => p.isNotEmpty)
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final a = parts(current);
    final b = parts(minimum);
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av < bv) return true;
      if (av > bv) return false;
    }
    return false;
  }
}
