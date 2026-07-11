import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/shop_chat_unread.dart';
import '../core/socket_service.dart';
import '../features/auth/auth_gate.dart';
import '../features/shop_chat/shop_chat_repository.dart';
import '../models/shop_conversation.dart';
import '../models/shop_message.dart';
import '../models/vendor.dart';
import 'theme.dart';
import 'widgets/sheet_theme_scope.dart';

Future<void> openShopChatWithCustomer(
  BuildContext context, {
  required String customerId,
  required String customerName,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final conv =
        await context.read<ShopChatRepository>().startWithCustomer(customerId);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await showShopChatSheet(
      context,
      conversation: conv,
      title: customerName.isNotEmpty ? customerName : 'Customer',
      isVendor: true,
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ShopChatRepository.errorMessage(e))),
    );
  }
}

Future<void> openShopChatWithVendor(
  BuildContext context, {
  required Vendor vendor,
}) async {
  if (!requireCustomerAuth(
    context,
    message: 'Sign in to chat with this pharmacy',
  )) {
    return;
  }
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final conv = await context.read<ShopChatRepository>().startWithVendor(vendor.id);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await showShopChatSheet(
      context,
      conversation: conv,
      title: vendor.name,
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ShopChatRepository.errorMessage(e))),
    );
  }
}

Future<void> showShopChatSheet(
  BuildContext context, {
  required ShopConversation conversation,
  required String title,
  bool isVendor = false,
}) {
  context.read<ShopChatUnread>().markRead(conversation.id);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: BytzGoTheme.sheetBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SheetThemeScope(
      child: ShopChatSheet(
        conversation: conversation,
        title: title,
        isVendor: isVendor,
      ),
    ),
  ).whenComplete(() {
    if (context.mounted) {
      context.read<ShopChatUnread>().markRead(conversation.id);
    }
  });
}

class ShopChatSheet extends StatefulWidget {
  const ShopChatSheet({
    super.key,
    required this.conversation,
    required this.title,
    this.isVendor = false,
  });

  final ShopConversation conversation;
  final String title;
  final bool isVendor;

  @override
  State<ShopChatSheet> createState() => _ShopChatSheetState();
}

class _ShopChatSheetState extends State<ShopChatSheet> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  List<ShopMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  List<String> get _quickReplies => widget.isVendor
      ? const [
          'Yes, it is in stock',
          'Sorry, currently out of stock',
          'Prescription required for this item',
          'Your order is ready for pickup',
        ]
      : const [
          'Do you have this medicine in stock?',
          'What is the price?',
          'Can I pick up today?',
          'Do you deliver to my area?',
        ];

  @override
  void initState() {
    super.initState();
    _load();
    context.read<SocketService>().addShopMessageListener(_onSocketMessage);
  }

  @override
  void dispose() {
    context.read<SocketService>().removeShopMessageListener(_onSocketMessage);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSocketMessage(String conversationId, ShopMessage message) {
    if (conversationId != widget.conversation.id) return;
    if (_messages.any((m) => m.id == message.id)) return;
    setState(() => _messages = [..._messages, message]);
    _scrollToEnd();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<ShopChatRepository>();
      final list = await repo.fetchMessages(widget.conversation.id);
      await repo.markRead(widget.conversation.id);
      if (!mounted) return;
      context.read<ShopChatUnread>().markRead(widget.conversation.id);
      setState(() {
        _messages = list;
        _loading = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ShopChatRepository.errorMessage(e);
      });
    }
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final repo = context.read<ShopChatRepository>();
      final msg = await repo.sendMessage(widget.conversation.id, text);
      if (preset == null) _controller.clear();
      if (!mounted) return;
      setState(() {
        if (!_messages.any((m) => m.id == msg.id)) {
          _messages = [..._messages, msg];
        }
        _sending = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = ShopChatRepository.errorMessage(e);
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: BytzGoTheme.sheetDivider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: BytzGoTheme.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.local_pharmacy_outlined, color: BytzGoTheme.accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: BytzGoTheme.sheetText,
                            ),
                          ),
                          Text(
                            'Secure pharmacy chat',
                            style: BytzGoTheme.sheetBody(11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: BytzGoTheme.sheetText),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _quickReplies.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final label = _quickReplies[i];
                    return ActionChip(
                      label: Text(label, style: const TextStyle(fontSize: 11)),
                      onPressed: _sending ? null : () => _send(label),
                    );
                  },
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: BytzGoTheme.danger, fontSize: 12),
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                widget.isVendor
                                    ? 'Reply to customer questions about medicines, stock, and pickup.'
                                    : 'Ask about availability, price, prescription rules, or delivery.',
                                style: BytzGoTheme.sheetBody(14),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _messages.length,
                            itemBuilder: (context, i) {
                              final m = _messages[i];
                              return _MessageBubble(message: m);
                            },
                          ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        style: const TextStyle(color: BytzGoTheme.sheetText),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Ask about a medicine…',
                          filled: true,
                          fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _sending ? null : () => _send(),
                      style: FilledButton.styleFrom(
                        backgroundColor: BytzGoTheme.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send, size: 20, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ShopMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: mine
              ? BytzGoTheme.accent.withValues(alpha: 0.15)
              : BytzGoTheme.sheetDivider.withValues(alpha: 0.5),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 4),
            bottomRight: Radius.circular(mine ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(
                message.displaySenderName,
                style: BytzGoTheme.sheetBody(11).copyWith(
                  fontWeight: FontWeight.w800,
                  color: BytzGoTheme.accent,
                ),
              ),
            Text(
              message.body,
              style: BytzGoTheme.sheetBody(14).copyWith(
                color: BytzGoTheme.sheetText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
