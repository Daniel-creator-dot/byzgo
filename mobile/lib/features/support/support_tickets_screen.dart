import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/support_ticket.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/sheet_theme_scope.dart';
import 'create_support_ticket_screen.dart';
import 'support_chat_screen.dart';
import 'support_repository.dart';

class SupportTicketsScreen extends StatefulWidget {
  const SupportTicketsScreen({super.key});

  @override
  State<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends State<SupportTicketsScreen> {
  List<SupportTicket> _tickets = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<SupportRepository>().fetchMyTickets();
      if (!mounted) return;
      setState(() {
        _tickets = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = SupportRepository.errorMessage(e);
      });
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<SupportTicket>(
      MaterialPageRoute(
        builder: (_) => const SheetThemeScope(
          child: CreateSupportTicketScreen(),
        ),
      ),
    );
    if (created != null && mounted) {
      await _load();
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => SheetThemeScope(
            child: SupportChatScreen(ticket: created),
          ),
        ),
      );
      if (mounted) _load();
    }
  }

  Future<void> _openTicket(SupportTicket ticket) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SheetThemeScope(
          child: SupportChatScreen(ticket: ticket),
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BytzGoTheme.sheetBg,
      appBar: AppBar(
        backgroundColor: BytzGoTheme.sheetBg,
        foregroundColor: BytzGoTheme.sheetText,
        elevation: 0,
        title: const Text(
          'Help & support',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: BytzGoTheme.brandBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('New case'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: BytzGoTheme.brandBlue,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: BytzGoTheme.danger),
                        ),
                      ),
                    ],
                  )
                : _tickets.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        children: [
                          const SizedBox(height: 40),
                          Icon(
                            Icons.support_agent_outlined,
                            size: 56,
                            color: BytzGoTheme.sheetMuted.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No support cases yet',
                            textAlign: TextAlign.center,
                            style: BytzGoTheme.sheetTitle(18),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tell us about an order, payment, or account issue and we will respond in this thread.',
                            textAlign: TextAlign.center,
                            style: BytzGoTheme.sheetBody(14),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: _tickets.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final t = _tickets[i];
                          return _TicketTile(
                            ticket: t,
                            onTap: () => _openTicket(t),
                          );
                        },
                      ),
      ),
    );
  }
}

class _TicketTile extends StatelessWidget {
  const _TicketTile({required this.ticket, required this.onTap});

  final SupportTicket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (ticket.status) {
      'open' => BytzGoTheme.brandBlue,
      'pending' => const Color(0xFFF59E0B),
      'resolved' => BytzGoTheme.accentDark,
      _ => BytzGoTheme.sheetMuted,
    };

    return Material(
      color: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    ticket.displayId,
                    style: const TextStyle(
                      color: BytzGoTheme.brandBlue,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      SupportTicket.statusLabel(ticket.status),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                ticket.subject,
                style: BytzGoTheme.sheetTitle(15),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                SupportTicket.categoryLabel(ticket.category),
                style: BytzGoTheme.sheetBody(12),
              ),
              if (ticket.lastMessagePreview != null) ...[
                const SizedBox(height: 8),
                Text(
                  ticket.lastMessagePreview!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BytzGoTheme.sheetBody(13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
