import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../models/order.dart';
import '../../shared/customer_trip.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/bytz_scaffold.dart';
import '../../shared/widgets/ride_ui.dart';
import '../orders/orders_repository.dart';
class CustomerActivityTab extends StatefulWidget {
  const CustomerActivityTab({
    super.key,
    required this.onTrackOrder,
  });

  final VoidCallback onTrackOrder;

  @override
  State<CustomerActivityTab> createState() => _CustomerActivityTabState();
}

class _CustomerActivityTabState extends State<CustomerActivityTab> {
  List<Order> _orders = [];
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
      final userId = context.read<Session>().user?.id;
      final list = await context.read<OrdersRepository>().fetchOrders();
      if (!mounted) return;
      setState(() {
        _orders = userId == null
            ? list
            : list.where((o) => o.customerId == userId).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = OrdersRepository.errorMessage(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _orders.where((o) {
      return !['delivered', 'cancelled'].contains(o.status);
    }).toList();
    final past = _orders.where((o) => o.status == 'delivered').toList();

    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: BytzGoTheme.brandBlue),
        ),
      );
    }

    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _load,
        color: BytzGoTheme.brandBlue,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            BytzErrorPanel(
              message: _error!,
              onRetry: _load,
              light: true,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: BytzGoTheme.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (active.isNotEmpty) ...[
            Text('Live trips', style: BytzGoTheme.sheetTitle(16)),
            const SizedBox(height: 10),
            ...active.map(
              (o) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ActiveTripTile(
                  address: o.address,
                  status: customerTripHeadline(o),
                  price: formatCedis(o.total),
                  onTap: widget.onTrackOrder,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text('History', style: BytzGoTheme.sheetTitle(16)),
          const SizedBox(height: 10),
          if (past.isEmpty && active.isEmpty)
            const BytzEmptyState(
              light: true,
              icon: Icons.two_wheeler_outlined,
              title: 'No trips yet',
              subtitle: 'Book a bike delivery from the Courier tab — your trips will show here.',
            )
          else
            ...past.map((o) => _historyTile(o)),
        ],
      ),
    );
  }

  Widget _historyTile(Order o) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          leading: const Icon(Icons.check_circle, color: BytzGoTheme.accentDark),
          title: Text(
            o.address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            formatOrderDate(o.createdAt),
            style: BytzGoTheme.sheetBody(12),
          ),
          trailing: Text(
            formatCedis(o.total),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

String formatOrderDate(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  return '${dt.day}/${dt.month}/${dt.year}';
}
