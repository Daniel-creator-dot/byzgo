import 'package:flutter/foundation.dart';

/// Unread pharmacy chat badges per conversation.
class ShopChatUnread extends ChangeNotifier {
  final Map<String, int> _counts = {};

  int unreadFor(String conversationId) => _counts[conversationId] ?? 0;

  int get total =>
      _counts.values.fold<int>(0, (sum, value) => sum + value);

  void setCount(String conversationId, int count) {
    final next = count < 0 ? 0 : count;
    if (_counts[conversationId] == next) return;
    if (next == 0) {
      _counts.remove(conversationId);
    } else {
      _counts[conversationId] = next;
    }
    notifyListeners();
  }

  void increment(String conversationId) {
    setCount(conversationId, unreadFor(conversationId) + 1);
  }

  void markRead(String conversationId) {
    setCount(conversationId, 0);
  }

  void applyConversationList(Iterable<({String id, int unread})> rows) {
    _counts.clear();
    for (final row in rows) {
      if (row.unread > 0) _counts[row.id] = row.unread;
    }
    notifyListeners();
  }
}
