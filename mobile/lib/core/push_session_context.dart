import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/role.dart';

/// Reads the persisted session role from background isolates (FCM handler).
class PushSessionContext {
  PushSessionContext._();

  static const _kUser = 'bytzgo_user';
  static const _storage = FlutterSecureStorage();

  static Future<AppRole?> activeRole() async {
    try {
      final userJson = await _storage.read(key: _kUser);
      if (userJson == null) return null;
      final map = jsonDecode(userJson) as Map<String, dynamic>;
      return AppRole.fromString(map['role']?.toString());
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isRider() async {
    final role = await activeRole();
    return role == AppRole.rider;
  }
}
