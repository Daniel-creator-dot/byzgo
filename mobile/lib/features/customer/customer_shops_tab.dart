import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../core/socket_service.dart';
import '../../models/location_point.dart';
import '../../models/order.dart';
import '../../models/vendor.dart';
import '../../shared/shop_categories.dart';
import '../../shared/theme.dart';
import '../../shared/vendor_contact.dart';
import '../../shared/widgets/accra_shops_map.dart';
import '../../shared/widgets/bytz_hero_header.dart';
import '../../shared/widgets/ops_stat_card.dart';
import '../../shared/widgets/vendor_shop_avatar.dart';
import '../../shared/widgets/vendor_promo_badge.dart';
import '../orders/orders_repository.dart';
import 'customer_shop_promo_float.dart';
import 'customer_vendor_menu_screen.dart';

class CustomerShopsTab extends StatefulWidget {
  const CustomerShopsTab({
    super.key,
    required this.onShopPickup,
    this.onShopOrderPlaced,
  });

  final void Function(LocationPoint pickup) onShopPickup;
  final void Function(Order order)? onShopOrderPlaced;

  @override
  State<CustomerShopsTab> createState() => _CustomerShopsTabState();
}

class _CustomerShopsTabState extends State<CustomerShopsTab> {
  List<Vendor> _vendors = [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();
  String _categoryId = 'restaurant';
  String? _mapSelectedVendorId;
  SocketService? _socket;
  VendorPromoHandler? _promoHandler;

  @override
  void initState() {
    super.initState();
    _wirePromoSocket();
    _load();
  }

  @override
  void dispose() {
    if (_promoHandler != null) {
      _socket?.removeVendorPromoListener(_promoHandler!);
    }
    _searchCtrl.dispose();
    super.dispose();
  }

  void _wirePromoSocket() {
    _socket = context.read<SocketService>();
    _promoHandler = (data) {
      final id = data['vendorId']?.toString() ?? data['id']?.toString();
      if (id == null || !mounted) return;
      setState(() {
        final i = _vendors.indexWhere((v) => v.id == id);
        if (i >= 0) {
          _vendors[i] = _vendors[i].copyWithPromo(data);
        }
      });
    };
    _socket!.addVendorPromoListener(_promoHandler!);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final region = context.read<Session>().user?.region;
      final list = await context.read<OrdersRepository>().fetchVendors(
            region: region,
            category: _categoryId,
          );
      if (!mounted) return;
      setState(() {
        _vendors = list;
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

  void _selectCategory(String id) {
    if (_categoryId == id) return;
    setState(() => _categoryId = id);
    _load();
  }

  List<Vendor> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    var list = _vendors;
    if (q.isNotEmpty) {
      list = list
          .where((v) =>
              v.name.toLowerCase().contains(q) ||
              (v.address?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    list.sort((a, b) {
      int rank(Vendor v) {
        switch (v.shopOpenStatus) {
          case 'closed':
            return 3;
          case 'busy':
            return 2;
          default:
            return 1;
        }
      }
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      if (a.hasCustomerFacingPromo != b.hasCustomerFacingPromo) {
        return a.hasCustomerFacingPromo ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
    return list;
  }

  int get _openShopCount =>
      _vendors.where((v) => v.shopOpenStatus == 'open').length;

  void _openVendorMenu(Vendor vendor) {
    setState(() => _mapSelectedVendorId = vendor.id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => CustomerVendorMenuScreen(
          vendor: vendor,
          onBookPickup: widget.onShopPickup,
          onShopOrderPlaced: widget.onShopOrderPlaced,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cat = ShopCategory.byId(_categoryId) ?? ShopCategory.ordered.first;
    final filtered = _filtered;

    return RefreshIndicator(
      color: BytzGoTheme.accent,
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: BytzHeroHeader(
                kicker: 'Marketplace',
                title: _categoryId == 'restaurant'
                    ? 'Popular restaurants in Accra'
                    : _categoryId == 'groceries'
                        ? 'Popular groceries in Accra'
                        : 'Shops near you',
                assetPath: 'assets/branding/hero_delivery.png',
                dark: false,
                height: 120,
              ),
            ),
          ),
          if (!_loading && _error == null && _vendors.any((v) => v.hasCustomerFacingPromo))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: CustomerShopPromoFloat(
                  vendors: _vendors,
                  onTapVendor: _openVendorMenu,
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                height: 88,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: ShopCategory.ordered.map((c) {
                    final selected = c.id == _categoryId;
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Material(
                        color: selected
                            ? c.accent.withValues(alpha: 0.15)
                            : BytzGoTheme.sheetDivider.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () => _selectCategory(c.id),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: 96,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected
                                    ? c.accent
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(c.icon, color: c.accent, size: 26),
                                const SizedBox(height: 6),
                                Text(
                                  c.label.split(' ').first,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: selected
                                        ? BytzGoTheme.sheetText
                                        : BytzGoTheme.sheetMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: AccraShopsMap(
              vendors: filtered,
              categoryId: _categoryId,
              selectedVendorId: _mapSelectedVendorId,
              onVendorTap: _openVendorMenu,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                height: 92,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    OpsStatCard(
                      light: true,
                      label: cat.label,
                      value: '${filtered.length}',
                      icon: cat.icon,
                      accent: cat.accent,
                      subtitle: '$_openShopCount open now',
                    ),
                    OpsStatCard(
                      light: true,
                      label: 'All shops',
                      value: '${_vendors.length}',
                      icon: Icons.storefront_outlined,
                      accent: BytzGoTheme.brandBlue,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search ${cat.label.toLowerCase()}…',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: BytzGoTheme.danger),
                  ),
                ),
              ),
            )
          else if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(cat.icon, size: 48, color: cat.accent.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      Text(
                        'No ${cat.label.toLowerCase()} in your area yet',
                        style: BytzGoTheme.sheetTitle(16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Try another category or check back soon.',
                        style: BytzGoTheme.sheetBody(13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final v = filtered[i];
                    final chip = ShopCategory.byId(v.shopCategory) ?? cat;
                    final closed = v.shopOpenStatus == 'closed';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Opacity(
                        opacity: closed ? 0.72 : 1,
                        child: Material(
                          color: BytzGoTheme.sheetBg,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(
                              color: chip.accent.withValues(alpha: closed ? 0.12 : 0.25),
                            ),
                          ),
                          child: InkWell(
                            onTap: () => _openVendorMenu(v),
                            borderRadius: BorderRadius.circular(18),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  VendorShopAvatar(
                                    vendor: v,
                                    size: 56,
                                    categoryId: _categoryId,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          v.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                            color: BytzGoTheme.sheetText,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        v.promoBadgeRow(compact: true),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: chip.accent.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            chip.label,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              color: chip.accent,
                                            ),
                                          ),
                                        ),
                                        if (v.address != null) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            v.address!,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: BytzGoTheme.sheetBody(12),
                                          ),
                                        ],
                                        if (v.phone != null && v.phone!.trim().isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            formatVendorPhone(v.phone),
                                            style: BytzGoTheme.sheetBody(12).copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: BytzGoTheme.brandBlue,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            if (v.phone != null && v.phone!.trim().isNotEmpty)
                                              TextButton.icon(
                                                onPressed: () => callVendorPhone(v.phone),
                                                icon: const Icon(Icons.phone, size: 16),
                                                label: const Text('Call'),
                                                style: TextButton.styleFrom(
                                                  foregroundColor: BytzGoTheme.brandBlue,
                                                  padding: EdgeInsets.zero,
                                                  minimumSize: const Size(0, 32),
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ),
                                              ),
                                            if (v.phone != null && v.phone!.trim().isNotEmpty)
                                              const SizedBox(width: 8),
                                            TextButton.icon(
                                              onPressed: () => openVendorInGoogleMaps(v),
                                              icon: const Icon(Icons.map, size: 16),
                                              label: const Text('Maps'),
                                              style: TextButton.styleFrom(
                                                foregroundColor: BytzGoTheme.sheetMuted,
                                                padding: EdgeInsets.zero,
                                                minimumSize: const Size(0, 32),
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: BytzGoTheme.brandBlue,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: filtered.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
