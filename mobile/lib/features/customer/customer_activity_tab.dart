import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../models/order.dart';
import '../../shared/customer_trip.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
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
      return const Center(child: CircularProgressIndicator());
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
          if (_error != null)
            Text(_error!, style: const TextStyle(color: BytzGoTheme.danger)),
          if (past.isEmpty && active.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(
                    Icons.two_wheeler_outlined,
                    size: 48,
                    color: BytzGoTheme.sheetMuted.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No trips yet',
                    style: BytzGoTheme.sheetBody(14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
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
