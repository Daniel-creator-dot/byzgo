import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists the latest incoming-ride push so the call UI can open after unlock.
class PendingIncomingRideStore {
  PendingIncomingRideStore._();

  static const _key = 'pending_incoming_ride_v1';

  static Map<String, String> _normalize(Map<String, dynamic> raw) {
    return {
      for (final e in raw.entries) e.key: e.value?.toString() ?? '',
    };
  }

  static bool isExpired(Map<String, String> data) {
    final expiresRaw = data['expiresAt']?.trim() ?? '';
    if (expiresRaw.isEmpty) return false;
    try {
      return DateTime.parse(expiresRaw).isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  static Future<void> save(Map<String, dynamic> raw) async {
    final data = _normalize(raw);
    final orderId = data['orderId']?.trim() ?? '';
    if (orderId.isEmpty || data['type'] != 'incoming-ride') return;
    if (isExpired(data)) {
      await clear();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data));
  }

  static Future<Map<String, String>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = _normalize(jsonDecode(raw) as Map<String, dynamic>);
      if (data['type'] != 'incoming-ride') {
        await clear();
        return null;
      }
      if (isExpired(data)) {
        await clear();
        return null;
      }
      return data;
    } catch (_) {
      await clear();
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
