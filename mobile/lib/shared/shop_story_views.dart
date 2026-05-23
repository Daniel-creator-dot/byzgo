import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/vendor.dart';

/// Tracks which Shop Drop each customer last viewed (ring turns gray after open).
class ShopStoryViews {
  ShopStoryViews._();
  static const _key = 'bytzgo_story_seen_posted_at';

  static Future<Map<String, int>> loadSeenPostedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> markSeen(Vendor vendor) async {
    if (!vendor.hasActiveStory) return;
    final posted = vendor.shopStoryPostedAt?.millisecondsSinceEpoch;
    if (posted == null) return;
    final prefs = await SharedPreferences.getInstance();
    final map = await loadSeenPostedAt();
    map[vendor.id] = posted;
    await prefs.setString(_key, jsonEncode(map));
  }

  static bool showStoryRing(Vendor vendor, Map<String, int> seenPostedAt) {
    if (!vendor.hasActiveStory) return false;
    final posted = vendor.shopStoryPostedAt?.millisecondsSinceEpoch;
    if (posted == null) return true;
    final seen = seenPostedAt[vendor.id];
    return seen == null || seen < posted;
  }
}
