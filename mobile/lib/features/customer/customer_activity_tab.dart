import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

  final void Function(Order order) onTrackOrder;

  @override
  State<CustomerActivityTab> createState() => CustomerActivityTabState();
}

class CustomerActivityTabState extends State<CustomerActivityTab> {
  List<Order> _orders = [];
  bool _loading = true;
  String? _error;
  Session? _watchedSession;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<Session>();
    if (!identical(session, _watchedSession)) {
      _watchedSession?.removeListener(_onSessionChanged);
      _watchedSession = session..addListener(_onSessionChanged);
    }
  }

  @override
  void dispose() {
    _watchedSession?.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    if (context.read<Session>().isAuthenticated) {
      _load();
    } else {
      setState(() {
        _orders = [];
        _error = null;
        _loading = false;
      });
    }
  }

  void noteOrder(Order order) {
    setState(() {
      final i = _orders.indexWhere((o) => o.id == order.id);
      if (i >= 0) {
        _orders[i] = order;
      } else {
        _orders = [order, ..._orders];
      }
      _loading = false;
      _error = null;
    });
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    final session = context.read<Session>();
    if (!session.isAuthenticated) {
      setState(() {
        _orders = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = session.user?.id;
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

  List<Order> get _liveTrips =>
      _orders.where(customerIsLiveTrackableTrip).toList();

  List<Order> get _scheduledTrips =>
      _orders.where((o) => o.status == 'scheduled').toList();

  List<Order> get _historyTrips => _orders.where((o) {
        if (o.status == 'delivered' || o.status == 'cancelled') return true;
        if (o.status == 'scheduled') return false;
        // Stale trips that are no longer live-trackable.
        return !customerIsLiveTrackableTrip(o);
      }).toList();

  bool _isAuthError(String? message) {
    if (message == null) return false;
    final lower = message.toLowerCase();
    return lower.contains('sign in') || lower.contains('session');
  }

  @override
  Widget build(BuildContext context) {
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
              title: _isAuthError(_error) ? 'Sign in required' : 'Could not load trips',
              message: _error!,
              onRetry: _isAuthError(_error)
                  ? () => context.push('/login')
                  : _load,
              retryLabel: _isAuthError(_error) ? 'Sign in' : 'Try again',
              light: true,
            ),
          ],
        ),
      );
    }

    final live = _liveTrips;
    final scheduled = _scheduledTrips;
    final history = _historyTrips;
    final hasAny = live.isNotEmpty || scheduled.isNotEmpty || history.isNotEmpty;

    return RefreshIndicator(
      onRefresh: _load,
      color: BytzGoTheme.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (!hasAny)
            const BytzEmptyState(
              light: true,
              icon: Icons.two_wheeler_outlined,
              title: 'No trips yet',
              subtitle:
                  'Shop orders and bike deliveries appear here after you place them.',
            )
          else ...[
            if (live.isNotEmpty) ...[
              Text('Live trips', style: BytzGoTheme.sheetTitle(16)),
              const SizedBox(height: 10),
              ...live.map(
                (o) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ActiveTripTile(
                    address: customerTripDisplayRoute(o),
                    status: customerTripHeadline(o),
                    price: formatCedis(o.total),
                    onTap: () => widget.onTrackOrder(o),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (scheduled.isNotEmpty) ...[
              Text('Scheduled', style: BytzGoTheme.sheetTitle(16)),
              const SizedBox(height: 10),
              ...scheduled.map(
                (o) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ActiveTripTile(
                    address: customerTripDisplayRoute(o),
                    status: customerTripHeadline(o),
                    price: formatCedis(o.total),
                    onTap: () => widget.onTrackOrder(o),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (history.isNotEmpty) ...[
              Text('History', style: BytzGoTheme.sheetTitle(16)),
              const SizedBox(height: 10),
              ...history.map((o) => _historyTile(o)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _historyTile(Order o) {
    final cancelled = o.status == 'cancelled';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          leading: Icon(
            cancelled ? Icons.cancel_outlined : Icons.check_circle,
            color: cancelled ? BytzGoTheme.danger : BytzGoTheme.accentDark,
          ),
          title: Text(
            customerTripDisplayRoute(o),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${customerTripHeadline(o)} · ${formatOrderDate(o.createdAt)}',
            style: BytzGoTheme.sheetBody(12),
          ),
          trailing: Text(
            formatCedis(o.total),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          onTap: cancelled ? null : () => widget.onTrackOrder(o),
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
