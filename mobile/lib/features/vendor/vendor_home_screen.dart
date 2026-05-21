import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../core/socket_service.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../shared/format.dart';
import '../../shared/shop_categories.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/bytz_hero_header.dart';
import '../../shared/widgets/delete_account_button.dart';
import '../../shared/widgets/legal_links.dart';
import '../../shared/widgets/ops_stat_card.dart';
import '../auth/auth_repository.dart';
import 'vendor_product_editor.dart';
import 'vendor_repository.dart';
import '../../shared/data_url_image.dart';

enum _VendorTab { overview, stock, orders, store }

class VendorHomeScreen extends StatefulWidget {
  const VendorHomeScreen({super.key});

  @override
  State<VendorHomeScreen> createState() => _VendorHomeScreenState();
}

class _VendorHomeScreenState extends State<VendorHomeScreen> {
  _VendorTab _tab = _VendorTab.overview;
  VendorDashboard? _dash;
  bool _loading = true;
  String? _error;
  String? _storeMsg;
  final _menuSearch = TextEditingController();
  List<Product> _menuProducts = [];
  bool _menuLoading = false;
  Timer? _menuSearchDebounce;
  SocketService? _socket;

  @override
  void initState() {
    super.initState();
    _wireSocket();
    _load();
  }

  @override
  void dispose() {
    _menuSearchDebounce?.cancel();
    _menuSearch.dispose();
    _socket?.onOrderUpdated = null;
    super.dispose();
  }

  void _wireSocket() {
    final userId = context.read<Session>().user?.id;
    if (userId == null) return;
    _socket = context.read<SocketService>();
    _socket!.onOrderUpdated = (Order order) {
      if (!mounted) return;
      if (order.vendorId != userId) return;
      if (order.status == 'picked_up') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rider picked up order #${order.id.length > 6 ? order.id.substring(order.id.length - 6) : order.id}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: BytzGoTheme.accentDark,
          ),
        );
      }
      if (_tab == _VendorTab.orders || _tab == _VendorTab.overview) {
        unawaited(_load());
      }
    };
  }

  Future<void> _loadMenuProducts({String? query, bool append = false}) async {
    setState(() => _menuLoading = true);
    try {
      final repo = context.read<VendorRepository>();
      final q = query ?? _menuSearch.text;
      final list = await repo.fetchProducts(
        search: q,
        limit: 200,
        offset: append ? _menuProducts.length : 0,
      );
      if (!mounted) return;
      setState(() {
        _menuProducts = append ? [..._menuProducts, ...list] : list;
        _menuLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _menuLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(VendorRepository.errorMessage(e))),
      );
    }
  }

  void _onMenuSearchChanged(String value) {
    _menuSearchDebounce?.cancel();
    _menuSearchDebounce = Timer(const Duration(milliseconds: 320), () {
      _loadMenuProducts(query: value);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dash = await context.read<VendorRepository>().fetchDashboard();
      if (!mounted) return;
      setState(() {
        _dash = dash;
        _loading = false;
      });
      if (_tab == _VendorTab.stock) await _loadMenuProducts();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = VendorRepository.errorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _toggleStock(Product p) async {
    try {
      await context.read<VendorRepository>().setProductAvailability(
            productId: p.id,
            isAvailable: !p.isAvailable,
          );
      await _load();
      if (_tab == _VendorTab.stock) await _loadMenuProducts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(p.isAvailable ? 'Marked out of stock' : 'Back in stock'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(VendorRepository.errorMessage(e)),
          backgroundColor: BytzGoTheme.danger,
        ),
      );
    }
  }

  Future<void> _saveStoreCategory(String categoryId) async {
    setState(() => _storeMsg = null);
    final auth = context.read<AuthRepository>();
    final session = context.read<Session>();
    try {
      final result = await auth.updateProfile(shopCategory: categoryId);
      await session.setSession(
        token: result.token,
        user: result.user,
      );
      if (!mounted) return;
      setState(() => _storeMsg = 'Shop category updated');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _storeMsg = AuthRepository.errorMessage(e));
    }
  }

  Future<void> _openAddProduct() async {
    final user = context.read<Session>().user;
    if (user?.status == 'rejected' || user?.status == 'disabled') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your store account cannot add menu items'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final saved = await showVendorProductEditor(context);
    if (saved == true) {
      await _load();
      if (_tab == _VendorTab.stock) await _loadMenuProducts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item saved — pending admin approval for customers'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openEditProduct(Product p) async {
    final saved = await showVendorProductEditor(context, existing: p);
    if (saved == true) {
      await _load();
      if (_tab == _VendorTab.stock) await _loadMenuProducts();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user!;
    final vendorActive = user.status == 'active';
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      floatingActionButton: _tab == _VendorTab.stock &&
              user.status != 'rejected' &&
              user.status != 'disabled'
          ? FloatingActionButton.extended(
              onPressed: _openAddProduct,
              backgroundColor: BytzGoTheme.accent,
              foregroundColor: const Color(0xFF022C22),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add item'),
            )
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'BytzGO Store',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh, color: Colors.white54),
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
            ),
            Expanded(
              child: _loading && _dash == null
                  ? const Center(
                      child: CircularProgressIndicator(color: BytzGoTheme.accent),
                    )
                  : _error != null && _dash == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!, style: const TextStyle(color: Colors.white70)),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: _load,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          color: BytzGoTheme.accent,
                          onRefresh: _load,
                          child: ListView(
                            padding: EdgeInsets.fromLTRB(16, 8, 16, 100 + bottomPad),
                            children: [
                              if (!vendorActive) ...[
                                _pendingBanner(),
                                const SizedBox(height: 12),
                              ],
                              if (_tab == _VendorTab.overview) ..._overview(user.name),
                              if (_tab == _VendorTab.stock) ..._stock(),
                              if (_tab == _VendorTab.orders) ..._orders(),
                              if (_tab == _VendorTab.store) ..._store(user),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          border: Border(top: BorderSide(color: Color(0xFF1E293B))),
        ),
        padding: EdgeInsets.fromLTRB(8, 8, 8, bottomPad > 0 ? bottomPad : 12),
        child: Row(
          children: _VendorTab.values.map((t) {
            final selected = _tab == t;
            final badge = t == _VendorTab.stock && (_dash?.stats.outOfStock ?? 0) > 0
                ? _dash!.stats.outOfStock
                : t == _VendorTab.orders && (_dash?.stats.activeOrders ?? 0) > 0
                    ? _dash!.stats.activeOrders
                    : null;
            return Expanded(
              child: InkWell(
                onTap: () {
                  setState(() => _tab = t);
                  if (t == _VendorTab.stock && _menuProducts.isEmpty) {
                    _loadMenuProducts();
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            _iconFor(t),
                            size: 22,
                            color: selected ? BytzGoTheme.accent : Colors.white38,
                          ),
                          if (badge != null && badge > 0)
                            Positioned(
                              right: -8,
                              top: -4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  badge > 9 ? '9+' : '$badge',
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
                        _labelFor(t),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: selected ? BytzGoTheme.accent : Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  IconData _iconFor(_VendorTab t) {
    switch (t) {
      case _VendorTab.overview:
        return Icons.dashboard_outlined;
      case _VendorTab.stock:
        return Icons.inventory_2_outlined;
      case _VendorTab.orders:
        return Icons.receipt_long_outlined;
      case _VendorTab.store:
        return Icons.storefront_outlined;
    }
  }

  String _labelFor(_VendorTab t) {
    switch (t) {
      case _VendorTab.overview:
        return 'Overview';
      case _VendorTab.stock:
        return 'Menu';
      case _VendorTab.orders:
        return 'Orders';
      case _VendorTab.store:
        return 'Store';
    }
  }

  List<Widget> _overview(String storeName) {
    final s = _dash!.stats;
    return [
      BytzHeroHeader(
        kicker: 'Vendor',
        title: storeName,
        assetPath: 'assets/branding/hero_delivery.png',
        height: 120,
      ),
      const SizedBox(height: 14),
      SizedBox(
        height: 100,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            OpsStatCard(
              label: 'Active orders',
              value: '${s.activeOrders}',
              icon: Icons.local_shipping_outlined,
              accent: const Color(0xFF38BDF8),
            ),
            OpsStatCard(
              label: 'In stock',
              value: '${s.inStock}',
              icon: Icons.check_circle_outline,
              accent: BytzGoTheme.accent,
            ),
            OpsStatCard(
              label: 'Out of stock',
              value: '${s.outOfStock}',
              icon: Icons.remove_circle_outline,
              accent: const Color(0xFFF59E0B),
            ),
            OpsStatCard(
              label: '7-day sales',
              value: formatCedis(s.revenue7d),
              icon: Icons.payments_outlined,
              accent: const Color(0xFFA855F7),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _sectionTitle('Stock movement'),
      ..._dash!.recentOrders.take(5).map(_orderMovementTile),
      if (_dash!.recentOrders.isEmpty)
        _emptyCard('No orders yet — sales will show here'),
    ];
  }

  Widget _pendingBanner() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
        ),
        child: const Row(
          children: [
            Icon(Icons.hourglass_top, color: Color(0xFFFBBF24)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Store pending approval. Add your menu now — customers see items after admin activates your account.',
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
              ),
            ),
          ],
        ),
      );

  List<Widget> _stock() {
    final stats = _dash?.stats;
    final inStock = stats?.inStock ?? 0;
    final total = inStock + (stats?.outOfStock ?? 0);
    final pending = stats?.pendingApproval ?? 0;
    return [
      BytzHeroHeader(
        kicker: 'Your menu',
        title: 'Stock & prices',
        assetPath: 'assets/branding/hero_delivery.png',
        height: 110,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _menuSearch,
        onChanged: _onMenuSearchChanged,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search medicines (name, category…)',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          prefixIcon: const Icon(Icons.search, color: Colors.white54),
          filled: true,
          fillColor: const Color(0xFF0F172A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF1E293B)),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        '$inStock of $total in stock · $pending pending approval'
        '${_menuSearch.text.trim().isNotEmpty ? ' · showing ${_menuProducts.length} matches' : ''}',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
      ),
      const SizedBox(height: 12),
      if (_menuLoading)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(color: BytzGoTheme.accent)),
        )
      else ...[
        ..._menuProducts.map((p) => _productTile(p)),
        if (_menuProducts.length >= 200)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: OutlinedButton(
              onPressed: _menuLoading ? null : () => _loadMenuProducts(append: true),
              style: OutlinedButton.styleFrom(
                foregroundColor: BytzGoTheme.accent,
                side: const BorderSide(color: Color(0xFF334155)),
              ),
              child: const Text('Load more items'),
            ),
          ),
        if (_menuProducts.isEmpty)
          _emptyCard(
            _menuSearch.text.trim().isEmpty
                ? 'Tap “Add item” to upload a photo, price, and description'
                : 'No items match your search',
          ),
      ],
    ];
  }

  List<Widget> _orders() {
    final orders = _dash?.recentOrders ?? [];
    return [
      BytzHeroHeader(
        kicker: 'Orders',
        title: 'Recent activity',
        assetPath: 'assets/branding/hero_delivery.png',
        height: 110,
      ),
      const SizedBox(height: 12),
      ...orders.map(_orderMovementTile),
      if (orders.isEmpty) _emptyCard('Waiting for customer orders'),
    ];
  }

  List<Widget> _store(dynamic user) {
    final cat = ShopCategory.normalizeVendorCategory(user.shopCategory?.toString());
    return [
      BytzHeroHeader(
        kicker: 'Your shop',
        title: 'Store settings',
        assetPath: 'assets/branding/hero_delivery.png',
        height: 110,
      ),
      const SizedBox(height: 14),
      _sectionTitle('Shop category (customer browse)'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: ShopCategory.ordered.map((c) {
          final selected = c.id == cat;
          return FilterChip(
            label: Text(c.label),
            selected: selected,
            onSelected: (_) => _saveStoreCategory(c.id),
            selectedColor: c.accent.withValues(alpha: 0.25),
            checkmarkColor: c.accent,
          );
        }).toList(),
      ),
      if (_storeMsg != null) ...[
        const SizedBox(height: 10),
        Text(_storeMsg!, style: const TextStyle(color: BytzGoTheme.accent, fontSize: 12)),
      ],
      const SizedBox(height: 16),
      _infoRow('Region', user.region?.toString() ?? 'Not set'),
      _infoRow('Address', user.address?.toString() ?? 'Not set'),
      const SizedBox(height: 12),
      Text(
        'Use the Menu tab to add photos and prices. Toggle stock on/off anytime.',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
      ),
      const SizedBox(height: 24),
      const ProfileLegalSection(),
      const SizedBox(height: 12),
      const Center(child: DeleteAccountButton(dark: true)),
    ];
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      );

  Widget _emptyCard(String msg) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Text(msg, style: const TextStyle(color: Colors.white54)),
      );

  Widget _productTile(Product p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: p.isAvailable ? const Color(0xFF1E293B) : const Color(0xFFF59E0B),
        ),
      ),
      child: InkWell(
        onTap: () => _openEditProduct(p),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: dataUrlImage(p.imageUrl, height: 56),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${p.category ?? 'Item'} · ${formatCedis(p.price)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                    if (!p.isApproved)
                      const Text(
                        'Pending approval',
                        style: TextStyle(
                          color: Color(0xFFFBBF24),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
              ),
              Switch(
                value: p.isAvailable,
                activeThumbColor: BytzGoTheme.accent,
                onChanged: (_) => _toggleStock(p),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _orderMovementTile(dynamic o) {
    final items = o.items;
    final qty = items is List ? items.length : 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: BytzGoTheme.brandBlue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.shopping_bag_outlined, color: Color(0xFF38BDF8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${o.id.toString().length > 6 ? o.id.toString().substring(o.id.toString().length - 6) : o.id}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${o.status} · $qty items · ${formatCedis(o.total)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      );
}
