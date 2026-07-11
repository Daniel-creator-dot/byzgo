import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/shop_chat_unread.dart';
import '../../core/socket_service.dart';
import '../../models/shop_conversation.dart';
import '../../shared/shop_chat_sheet.dart';
import '../../shared/theme.dart';
import 'shop_chat_repository.dart';

class VendorShopMessagesPanel extends StatefulWidget {
  const VendorShopMessagesPanel({super.key});

  @override
  State<VendorShopMessagesPanel> createState() => _VendorShopMessagesPanelState();
}

class _VendorShopMessagesPanelState extends State<VendorShopMessagesPanel> {
  List<ShopConversation> _conversations = [];
  bool _loading = true;
  ShopMessageHandler? _handler;

  @override
  void initState() {
    super.initState();
    _load();
    _handler = (conversationId, message) {
      if (!mounted || message.isMine) return;
      context.read<ShopChatUnread>().increment(conversationId);
      _load(silent: true);
    };
    context.read<SocketService>().addShopMessageListener(_handler!);
  }

  @override
  void dispose() {
    if (_handler != null) {
      context.read<SocketService>().removeShopMessageListener(_handler!);
    }
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
      });
    }
    try {
      final list = await context.read<ShopChatRepository>().fetchConversations();
      if (!mounted) return;
      context.read<ShopChatUnread>().applyConversationList(
            list.map((c) => (id: c.id, unread: c.unreadCount)),
          );
      setState(() {
        _conversations = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openChat(ShopConversation conversation) async {
    await showShopChatSheet(
      context,
      conversation: conversation,
      title: conversation.peerName.isNotEmpty
          ? conversation.peerName
          : conversation.customerName,
      isVendor: true,
    );
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final unreadTotal = context.watch<ShopChatUnread>().total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'CUSTOMER MESSAGES',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            if (unreadTotal > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  unreadTotal > 99 ? '99+' : '$unreadTotal',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
            const Spacer(),
            if (!_loading)
              TextButton(onPressed: _load, child: const Text('Refresh')),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: CircularProgressIndicator(color: BytzGoTheme.accent),
            ),
          )
        else if (_conversations.isEmpty)
          _emptyCard(
            'Customers can ask about medicines before ordering. Replies appear here in real time.',
          )
        else
          ..._conversations.take(5).map((c) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: c.unreadCount > 0
                      ? BytzGoTheme.accent.withValues(alpha: 0.45)
                      : const Color(0xFF1E293B),
                ),
              ),
              child: ListTile(
                onTap: () => _openChat(c),
                leading: CircleAvatar(
                  backgroundColor: BytzGoTheme.accent.withValues(alpha: 0.15),
                  child: Text(
                    (c.peerName.isNotEmpty ? c.peerName : c.customerName)
                        .substring(0, 1)
                        .toUpperCase(),
                    style: const TextStyle(
                      color: BytzGoTheme.accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                title: Text(
                  c.peerName.isNotEmpty ? c.peerName : c.customerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  c.lastMessagePreview.isNotEmpty
                      ? c.lastMessagePreview
                      : 'Tap to open chat',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: c.unreadCount > 0
                    ? Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          c.unreadCount > 9 ? '9+' : '${c.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      )
                    : const Icon(Icons.chevron_right, color: Colors.white38),
              ),
            );
          }),
      ],
    );
  }

  Widget _emptyCard(String msg) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Text(msg, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      );
}
