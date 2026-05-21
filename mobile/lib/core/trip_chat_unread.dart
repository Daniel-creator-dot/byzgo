import 'package:flutter/foundation.dart';

/// Per-order unread trip chat counts (in-app badge, separate from push).
class TripChatUnread extends ChangeNotifier {
  final Map<String, int> _counts = {};

  int countFor(String orderId) => _counts[orderId] ?? 0;

  bool hasUnread(String orderId) => countFor(orderId) > 0;

  void markUnread(String orderId) {
    _counts[orderId] = (_counts[orderId] ?? 0) + 1;
    notifyListeners();
  }

  void markRead(String orderId) {
    if (_counts.remove(orderId) != null) notifyListeners();
  }

  void clear() {
    if (_counts.isEmpty) return;
    _counts.clear();
    notifyListeners();
  }
}
