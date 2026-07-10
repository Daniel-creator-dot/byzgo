import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'pending_incoming_ride_store.dart';

/// Accept/decline tapped on lock-screen CallKit before the rider shell is ready.
class PendingIncomingRideActionStore {
  PendingIncomingRideActionStore._();

  static const _key = 'pending_incoming_ride_action_v1';

  static Future<void> save(String action, Map<String, dynamic> raw) async {
    final data = {
      for (final e in raw.entries) e.key: e.value?.toString() ?? '',
    };
    final orderId = data['orderId']?.trim() ?? '';
    if (orderId.isEmpty) return;
    if (PendingIncomingRideStore.isExpired(data)) {
      await clear();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({'action': action, 'data': data}),
    );
  }

  static Future<({String action, Map<String, String> data})?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final action = decoded['action']?.toString() ?? '';
      final dataRaw = decoded['data'];
      if (action.isEmpty || dataRaw is! Map) {
        await clear();
        return null;
      }
      final data = {
        for (final e in dataRaw.entries) e.key.toString(): e.value?.toString() ?? '',
      };
      if (PendingIncomingRideStore.isExpired(data)) {
        await clear();
        return null;
      }
      return (action: action, data: data);
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
