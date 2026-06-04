import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/support_ticket.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/sheet_theme_scope.dart';
import '../support/support_chat_screen.dart';
import '../support/support_repository.dart';
import 'widgets/admin_hero_header.dart';

class AdminSupportTab extends StatefulWidget {
  const AdminSupportTab({super.key});

  @override
  State<AdminSupportTab> createState() => AdminSupportTabState();
}

class AdminSupportTabState extends State<AdminSupportTab> {
  List<SupportTicket> _tickets = [];
  bool _loading = true;
  String? _error;
  String? _statusFilter;
  String? _categoryFilter;
  String? _roleFilter;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<SupportRepository>().fetchAdminTickets(
            status: _statusFilter,
            category: _categoryFilter,
            role: _roleFilter,
          );
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

  int get openCount => _tickets.where((t) => t.status == 'open').length;

  Future<void> _openTicket(SupportTicket ticket) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SheetThemeScope(
          child: SupportChatScreen(ticket: ticket, adminMode: true),
        ),
      ),
    );
    if (mounted) load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: load,
      color: BytzGoTheme.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          const AdminHeroHeader(
            title: 'Support inbox',
            subtitle: 'Cases from customers, vendors & drivers',
            assetPath: 'assets/branding/hero_delivery.png',
          ),
          const SizedBox(height: 12),
          _FilterRow(
            status: _statusFilter,
            category: _categoryFilter,
            role: _roleFilter,
            onStatus: (v) {
              setState(() => _statusFilter = v);
              load();
            },
            onCategory: (v) {
              setState(() => _categoryFilter = v);
              load();
            },
            onRole: (v) {
              setState(() => _roleFilter = v);
              load();
            },
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: BytzGoTheme.danger))
          else if (_tickets.isEmpty)
            Text(
              'No tickets match these filters.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            )
          else
            ..._tickets.map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AdminTicketCard(ticket: t, onTap: () => _openTicket(t)),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.status,
    required this.category,
    required this.role,
    required this.onStatus,
    required this.onCategory,
    required this.onRole,
  });

  final String? status;
  final String? category;
  final String? role;
  final ValueChanged<String?> onStatus;
  final ValueChanged<String?> onCategory;
  final ValueChanged<String?> onRole;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _dropdown(
          label: 'Status',
          value: status,
          items: const [
            null,
            'open',
            'pending',
            'resolved',
            'closed',
          ],
          labels: const {
            null: 'All statuses',
            'open': 'Open',
            'pending': 'Pending',
            'resolved': 'Resolved',
            'closed': 'Closed',
          },
          onChanged: onStatus,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _dropdown(
                label: 'Category',
                value: category,
                items: const [null, 'order', 'payment', 'account', 'delivery', 'shop', 'other'],
                labels: const {
                  null: 'All categories',
                  'order': 'Order',
                  'payment': 'Payment',
                  'account': 'Account',
                  'delivery': 'Delivery',
                  'shop': 'Shop',
                  'other': 'Other',
                },
                onChanged: onCategory,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _dropdown(
                label: 'From',
                value: role,
                items: const [null, 'customer', 'vendor', 'rider'],
                labels: const {
                  null: 'All roles',
                  'customer': 'Customer',
                  'vendor': 'Vendor',
                  'rider': 'Driver',
                },
                onChanged: onRole,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<String?> items,
    required Map<String?, String> labels,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String?>(
      value: value,
      dropdownColor: const Color(0xFF0F172A),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: items
          .map(
            (v) => DropdownMenuItem<String?>(
              value: v,
              child: Text(labels[v] ?? ''),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _AdminTicketCard extends StatelessWidget {
  const _AdminTicketCard({required this.ticket, required this.onTap});

  final SupportTicket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final urgent = ticket.status == 'open';
    return Material(
      color: const Color(0xFF0F172A),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: urgent
                  ? BytzGoTheme.accent.withValues(alpha: 0.5)
                  : const Color(0xFF334155),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    ticket.displayLabel,
                    style: const TextStyle(
                      color: BytzGoTheme.brandBlueBright,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    SupportTicket.statusLabel(ticket.status),
                    style: TextStyle(
                      color: urgent ? BytzGoTheme.accent : Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                ticket.subject,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${SupportTicket.roleLabel(ticket.createdByRole)} · ${ticket.creatorName ?? 'User'} · ${SupportTicket.categoryLabel(ticket.category)}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
              ),
              if (ticket.lastMessagePreview != null) ...[
                const SizedBox(height: 8),
                Text(
                  ticket.lastMessagePreview!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
