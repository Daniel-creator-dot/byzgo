import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../core/socket_service.dart';
import '../../features/admin/admin_repository.dart';
import '../../features/orders/orders_repository.dart';
import '../../features/support/support_repository.dart';
import '../../models/admin_overview.dart';
import '../../models/order.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import 'admin_drivers_tab.dart';
import 'admin_live_map.dart';
import 'admin_stores_hub.dart';
import 'admin_pricing_tab.dart';
import 'admin_support_tab.dart';
import 'widgets/admin_hero_header.dart';
import 'widgets/admin_order_detail_sheet.dart';
import 'widgets/admin_stat_card.dart';

enum _AdminTab { live, drivers, stores, orders, support, pricing, insights }

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  _AdminTab _tab = _AdminTab.live;
  AdminOverview? _overview;
  bool _loadingOverview = true;
  String? _overviewError;
  String? _selectedRiderId;
  int _pendingDrivers = 0;
  Timer? _pollTimer;

  final _driversTabKey = GlobalKey<AdminDriversTabState>();
  final _storesHubKey = GlobalKey<AdminStoresHubState>();
  final _supportTabKey = GlobalKey<AdminSupportTabState>();
  int _pendingVendors = 0;
  int _pendingMenu = 0;
  int _openSupport = 0;

  List<Order> _orders = [];
  bool _ordersLoading = false;
  Map<String, dynamic>? _revenue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _wireSocket();
      _refreshOverview();
      _startPolling();
      _loadOrders();
      _loadRevenue();
      _loadPendingCount();
      _loadPendingVendorCount();
      _loadOpenSupportCount();
    });
  }

  Future<void> _loadOpenSupportCount() async {
    try {
      final list = await context.read<SupportRepository>().fetchAdminTickets(status: 'open');
      if (mounted) setState(() => _openSupport = list.length);
    } catch (_) {}
  }

  Future<void> _loadPendingVendorCount() async {
    try {
      final repo = context.read<AdminRepository>();
      final vendors = await repo.fetchVendors();
      final menu = await repo.fetchPendingProducts();
      if (mounted) {
        setState(() {
          _pendingVendors = vendors.where((v) => v.isPending).length;
          _pendingMenu = menu.length;
        });
      }
    } catch (_) {}
  }

  int get _storesBadgeCount => _pendingVendors + _pendingMenu;

  Future<void> _loadPendingCount() async {
    try {
      final list = await context.read<AdminRepository>().fetchPendingRiders();
      if (mounted) setState(() => _pendingDrivers = list.length);
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void deactivate() {
    final socket = context.read<SocketService>();
    socket.onLocationUpdated = null;
    socket.onOrderNew = null;
    socket.onOrderUpdated = null;
    super.deactivate();
  }

  void _wireSocket() {
    final socket = context.read<SocketService>();
    socket.onLocationUpdated = (riderId, lat, lng) {
      if (_overview == null) return;
      final updated = _overview!.liveRiders.map((r) {
        if (r.id != riderId) return r;
        return r.copyWith(
          lat: lat,
          lng: lng,
          hasLocation: true,
          isOnline: true,
          locationUpdatedAt: DateTime.now().toIso8601String(),
        );
      }).toList();
      setState(() => _overview = AdminOverview(stats: _overview!.stats, liveRiders: updated));
    };
    socket.onOrderNew = (_) => _loadOrders();
    socket.onOrderUpdated = (_) {
      _loadOrders();
      _refreshOverview();
    };
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (_tab == _AdminTab.live) _refreshOverview(silent: true);
    });
  }

  Future<void> _refreshOverview({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loadingOverview = true;
        _overviewError = null;
      });
    }
    try {
      final data = await context.read<AdminRepository>().fetchOverview();
      if (!mounted) return;
      setState(() {
        _overview = data;
        _loadingOverview = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _overviewError = AdminRepository.errorMessage(e);
        _loadingOverview = false;
      });
    }
  }

  Future<void> _loadOrders() async {
    setState(() => _ordersLoading = true);
    try {
      final list = await context.read<OrdersRepository>().fetchOrders();
      if (!mounted) return;
      setState(() => _orders = list);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _ordersLoading = false);
    }
  }

  Future<void> _loadRevenue() async {
    try {
      final data = await context.read<AdminRepository>().fetchRevenue();
      if (!mounted) return;
      setState(() => _revenue = data);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user;
    final name = user?.name ?? 'Admin';

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: SafeArea(
        child: Column(
          children: [
            _topBar(name),
            Expanded(child: _buildTabBody()),
            _bottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _topBar(String name) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Image.asset('assets/branding/app_logo.png', height: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BYTZGO CONTROL',
                  style: TextStyle(
                    color: BytzGoTheme.accent,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              _refreshOverview();
              _loadOrders();
              _driversTabKey.currentState?.load();
              _storesHubKey.currentState?.reload();
              _loadPendingVendorCount();
            },
            icon: const Icon(Icons.sync, color: Colors.white70),
          ),
          IconButton(
            onPressed: () async {
              await context.read<Session>().clear();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBody() {
    switch (_tab) {
      case _AdminTab.live:
        return _buildLiveTab();
      case _AdminTab.drivers:
        return AdminDriversTab(
          key: _driversTabKey,
          onPendingCount: (n) => setState(() => _pendingDrivers = n),
        );
      case _AdminTab.stores:
        return AdminStoresHub(
          key: _storesHubKey,
          onVendorPendingCount: (n) => setState(() => _pendingVendors = n),
          onMenuPendingCount: (n) => setState(() => _pendingMenu = n),
        );
      case _AdminTab.orders:
        return _buildOrdersTab();
      case _AdminTab.support:
        return AdminSupportTab(key: _supportTabKey);
      case _AdminTab.pricing:
        return const AdminPricingTab();
      case _AdminTab.insights:
        return _buildInsightsTab();
    }
  }

  Widget _buildLiveTab() {
    if (_loadingOverview && _overview == null) {
      return const Center(
        child: CircularProgressIndicator(color: BytzGoTheme.accent),
      );
    }
    if (_overviewError != null && _overview == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_overviewError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _refreshOverview,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final stats = _overview!.stats;
    final riders = _overview!.liveRiders;
    final online = riders.where((r) => r.isOnline).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AdminHeroHeader(
            title: 'Live fleet',
            subtitle: '${stats.driversOnline} drivers online',
            assetPath: 'assets/branding/hero_rider.png',
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              SizedBox(
                width: 120,
                child: AdminStatCard(
                  label: 'Online',
                  value: '${stats.driversOnline}',
                  icon: Icons.two_wheeler,
                  accent: BytzGoTheme.accent,
                  subtitle: 'of ${stats.driversApproved} approved',
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: AdminStatCard(
                  label: 'Active trips',
                  value: '${stats.activeOrders}',
                  icon: Icons.local_shipping_outlined,
                  accent: const Color(0xFF38BDF8),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: AdminStatCard(
                  label: 'Today',
                  value: '${stats.ordersToday}',
                  icon: Icons.receipt_long,
                  accent: BytzGoTheme.brandBlueBright,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: AdminStatCard(
                  label: 'KYC queue',
                  value: '${stats.driversPending}',
                  icon: Icons.verified_user_outlined,
                  accent: BytzGoTheme.warning,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AdminLiveMap(
                riders: riders,
                selectedId: _selectedRiderId,
                onRiderTap: (r) => setState(() => _selectedRiderId = r.id),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: 3,
          child: _onlineRiderList(online),
        ),
      ],
    );
  }

  Widget _onlineRiderList(List<AdminLiveRider> online) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              _pulseDot(),
              const SizedBox(width: 8),
              Text(
                'ONLINE NOW (${online.length})',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: online.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        opacity: 0.5,
                        child: Image.asset('assets/branding/hero_rider.png', height: 56),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No drivers online right now',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: online.length,
                  itemBuilder: (context, i) {
                    final r = online[i];
                    final selected = _selectedRiderId == r.id;
                    return _riderChip(r, selected);
                  },
                ),
        ),
      ],
    );
  }

  Widget _pulseDot() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: BytzGoTheme.accent.withValues(alpha: value),
            boxShadow: [
              BoxShadow(
                color: BytzGoTheme.accent.withValues(alpha: value * 0.6),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        );
      },
      onEnd: () {
        if (mounted) setState(() {});
      },
    );
  }

  Widget _riderChip(AdminLiveRider r, bool selected) {
    final onTrip = r.activeTrips > 0;
    return GestureDetector(
      onTap: () => setState(() => _selectedRiderId = r.id),
      child: Container(
        width: 168,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E3A1E) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? BytzGoTheme.accent
                : (onTrip ? const Color(0xFF38BDF8) : const Color(0xFF1E293B)).withValues(alpha: 0.8),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: BytzGoTheme.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              r.region ?? 'Ghana',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10),
            ),
            const Spacer(),
            Row(
              children: [
                Icon(
                  onTrip ? Icons.route : Icons.gps_fixed,
                  size: 12,
                  color: onTrip ? const Color(0xFF38BDF8) : BytzGoTheme.accent,
                ),
                const SizedBox(width: 4),
                Text(
                  onTrip
                      ? '${r.activeTrips} trip${r.activeTrips == 1 ? '' : 's'}'
                      : (r.hasLocation ? 'GPS live' : 'No GPS yet'),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: onTrip ? const Color(0xFF38BDF8) : BytzGoTheme.accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersTab() {
    final active = _orders.where((o) => !['delivered', 'cancelled'].contains(o.status)).toList();
    return RefreshIndicator(
      onRefresh: _loadOrders,
      color: BytzGoTheme.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          AdminHeroHeader(
            title: 'Operations',
            subtitle: '${active.length} active orders',
            assetPath: 'assets/branding/hero_delivery.png',
          ),
          const SizedBox(height: 16),
          if (_ordersLoading)
            const Center(child: CircularProgressIndicator(color: BytzGoTheme.accent))
          else if (active.isEmpty)
            _ordersEmpty()
          else
            ...active.take(40).map(_orderTile),
        ],
      ),
    );
  }

  Widget _ordersEmpty() {
    return Container(
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        children: [
          Image.asset('assets/branding/hero_delivery.png', height: 72),
          const SizedBox(height: 12),
          Text(
            'No active orders',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }

  void _openOrderDetail(Order o) {
    showAdminOrderDetailSheet(
      context,
      order: o,
      onOrderUpdated: (updated) {
        setState(() {
          final i = _orders.indexWhere((x) => x.id == updated.id);
          if (i >= 0) _orders[i] = updated;
        });
        _refreshOverview(silent: true);
      },
      onViewRiderOnMap: o.riderId != null && o.riderId!.isNotEmpty
          ? () => setState(() {
                _tab = _AdminTab.live;
                _selectedRiderId = o.riderId;
              })
          : null,
    );
  }

  Widget _orderTile(Order o) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openOrderDetail(o),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: BytzGoTheme.brandBlue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.inventory_2_outlined,
                    color: BytzGoTheme.brandBlueBright, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${o.id.length > 6 ? o.id.substring(o.id.length - 6) : o.id}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      o.status.toUpperCase(),
                      style: TextStyle(
                        color: BytzGoTheme.accent.withValues(alpha: 0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (o.customerName.isNotEmpty)
                      Text(
                        o.customerName,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 11),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatCedis(o.total),
                    style: const TextStyle(
                      color: BytzGoTheme.accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.white.withValues(alpha: 0.35),
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInsightsTab() {
    final summary = _revenue?['summary'] as Map?;
    final gross = double.tryParse('${summary?['gross_revenue']}') ?? _overview?.stats.grossRevenue ?? 0;
    final delivered = int.tryParse('${summary?['total_orders']}') ?? 0;
    final stats = _overview?.stats;

    return RefreshIndicator(
      onRefresh: () async {
        await _refreshOverview();
        await _loadRevenue();
      },
      color: BytzGoTheme.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          AdminHeroHeader(
            title: 'Insights',
            subtitle: 'Platform pulse',
            assetPath: 'assets/branding/hero_delivery.png',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E60C2), Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GROSS REVENUE',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  formatCedis(gross),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$delivered delivered orders',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (stats != null)
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.35,
              children: [
                AdminStatCard(
                  label: 'Customers',
                  value: '${stats.customersTotal}',
                  icon: Icons.people_outline,
                  accent: BytzGoTheme.brandBlueBright,
                ),
                AdminStatCard(
                  label: 'Vendors',
                  value: '${stats.vendorsActive}',
                  icon: Icons.storefront_outlined,
                  accent: const Color(0xFFA78BFA),
                ),
                AdminStatCard(
                  label: 'Drivers',
                  value: '${stats.driversTotal}',
                  icon: Icons.two_wheeler,
                  accent: BytzGoTheme.accent,
                ),
                AdminStatCard(
                  label: 'Fleet online',
                  value: '${stats.driversOnline}',
                  icon: Icons.radar,
                  accent: const Color(0xFF34D399),
                ),
              ],
            ),
          const SizedBox(height: 16),
          Opacity(
            opacity: 0.35,
            child: Image.asset(
              'assets/branding/preloader.png',
              height: 48,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(_AdminTab.live, Icons.radar, 'Live'),
              _navItem(_AdminTab.drivers, Icons.verified_user, 'Drivers', badge: _pendingDrivers),
              _navItem(_AdminTab.stores, Icons.storefront, 'Stores', badge: _storesBadgeCount),
              _navItem(_AdminTab.orders, Icons.list_alt, 'Orders'),
              _navItem(_AdminTab.support, Icons.support_agent, 'Support', badge: _openSupport),
              _navItem(_AdminTab.pricing, Icons.payments_outlined, 'Pricing'),
              _navItem(_AdminTab.insights, Icons.insights, 'Insights'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(_AdminTab tab, IconData icon, String label, {int badge = 0}) {
    final active = _tab == tab;
    return InkWell(
      onTap: () {
        setState(() => _tab = tab);
        if (tab == _AdminTab.live) _refreshOverview(silent: true);
        if (tab == _AdminTab.drivers) _driversTabKey.currentState?.load();
        if (tab == _AdminTab.stores) {
          _storesHubKey.currentState?.reload();
          _loadPendingVendorCount();
        }
        if (tab == _AdminTab.orders) _loadOrders();
        if (tab == _AdminTab.support) {
          _supportTabKey.currentState?.load();
          _loadOpenSupportCount();
        }
        if (tab == _AdminTab.insights) _loadRevenue();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: active ? BytzGoTheme.accent : Colors.white38,
                  size: 24,
                ),
                if (badge > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? BytzGoTheme.accent : Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
