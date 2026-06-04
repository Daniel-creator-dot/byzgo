import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../core/socket_service.dart';
import '../../models/support_message.dart';
import '../../models/support_ticket.dart';
import '../../shared/theme.dart';
import 'support_repository.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({
    super.key,
    required this.ticket,
    this.adminMode = false,
  });

  final SupportTicket ticket;
  final bool adminMode;

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  late SupportTicket _ticket;
  List<SupportMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket;
    _load();
    context.read<SocketService>().addSupportMessageListener(_onSocketMessage);
  }

  @override
  void dispose() {
    context.read<SocketService>().removeSupportMessageListener(_onSocketMessage);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSocketMessage(String ticketId, SupportMessage message) {
    if (ticketId != _ticket.id) return;
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
      final repo = context.read<SupportRepository>();
      final ticket = await repo.fetchTicket(_ticket.id);
      final list = await repo.fetchMessages(_ticket.id);
      if (!mounted) return;
      setState(() {
        _ticket = ticket;
        _messages = list;
        _loading = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = SupportRepository.errorMessage(e);
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending || _ticket.status == 'closed') return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final repo = context.read<SupportRepository>();
      final msg = await repo.sendMessage(_ticket.id, text);
      _controller.clear();
      if (!mounted) return;
      setState(() {
        if (!_messages.any((m) => m.id == msg.id)) {
          _messages = [..._messages, msg];
        }
        _sending = false;
      });
      final refreshed = await repo.fetchTicket(_ticket.id);
      if (mounted) setState(() => _ticket = refreshed);
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = SupportRepository.errorMessage(e);
      });
    }
  }

  Future<void> _updateStatus(String status) async {
    try {
      final updated = await context.read<SupportRepository>().updateAdminTicket(
            _ticket.id,
            status: status,
            assignSelf: true,
          );
      if (mounted) setState(() => _ticket = updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(SupportRepository.errorMessage(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
    final session = context.watch<Session>();
    final isAdmin = session.user?.role.name == 'admin';
    final canSend = _ticket.status != 'closed';

    return Scaffold(
      backgroundColor: BytzGoTheme.sheetBg,
      appBar: AppBar(
        backgroundColor: BytzGoTheme.sheetBg,
        foregroundColor: BytzGoTheme.sheetText,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _ticket.displayLabel,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            Text(
              _ticket.subject,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (widget.adminMode && isAdmin)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: _updateStatus,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'open', child: Text('Mark open')),
                PopupMenuItem(value: 'pending', child: Text('Awaiting user')),
                PopupMenuItem(value: 'resolved', child: Text('Resolved')),
                PopupMenuItem(value: 'closed', child: Text('Close ticket')),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          _TicketMetaBar(ticket: _ticket, adminMode: widget.adminMode),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                        child: Text(
                          'Start the conversation — our team will join shortly.',
                          style: BytzGoTheme.sheetBody(14),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) =>
                            _MessageBubble(message: _messages[i]),
                      ),
          ),
          if (!canSend)
            Container(
              width: double.infinity,
              color: BytzGoTheme.sheetDivider.withValues(alpha: 0.5),
              padding: const EdgeInsets.all(12),
              child: Text(
                'This case is closed. Open a new ticket if you still need help.',
                textAlign: TextAlign.center,
                style: BytzGoTheme.sheetBody(12),
              ),
            )
          else
            Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                8,
                12,
                12 + MediaQuery.viewInsetsOf(context).bottom,
              ),
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
                        hintText: widget.adminMode
                            ? 'Reply as support…'
                            : 'Type a message…',
                        filled: true,
                        fillColor:
                            BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
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
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TicketMetaBar extends StatelessWidget {
  const _TicketMetaBar({required this.ticket, required this.adminMode});

  final SupportTicket ticket;
  final bool adminMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          _chip(SupportTicket.categoryLabel(ticket.category)),
          _chip(SupportTicket.statusLabel(ticket.status)),
          if (adminMode && ticket.creatorName != null)
            _chip(
              '${SupportTicket.roleLabel(ticket.createdByRole)} · ${ticket.creatorName}',
            ),
          if (ticket.relatedOrderId != null && ticket.relatedOrderId!.length > 8)
            _chip('Order ${ticket.relatedOrderId!.substring(0, 8)}…'),
          if (ticket.assignedAdminName != null)
            _chip('Agent: ${ticket.assignedAdminName}'),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BytzGoTheme.sheetDivider),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final SupportMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: mine
              ? BytzGoTheme.brandBlue
              : BytzGoTheme.sheetDivider.withValues(alpha: 0.5),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(
                message.displaySenderName,
                style: const TextStyle(
                  color: BytzGoTheme.brandBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            Text(
              message.body,
              style: TextStyle(
                color: mine ? Colors.white : BytzGoTheme.sheetText,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
