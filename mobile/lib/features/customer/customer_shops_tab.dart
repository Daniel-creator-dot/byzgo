import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../core/shop_chat_unread.dart';
import '../../core/socket_service.dart';
import '../../models/location_point.dart';
import '../../models/order.dart';
import '../../models/pharmacy_search_hit.dart';
import '../../models/product.dart';
import '../../models/vendor.dart';
import '../../shared/format.dart';
import '../../shared/shop_categories.dart';
import '../../shared/theme.dart';
import '../../shared/external_navigation.dart';
import '../../shared/shop_chat_sheet.dart';
import '../../shared/vendor_contact.dart';
import '../../shared/widgets/pharmacy_hub_welcome.dart';
import '../../shared/widgets/accra_shops_map.dart';
import '../../shared/widgets/ops_stat_card.dart';
import '../../shared/shop_story_views.dart';
import '../../shared/widgets/vendor_shop_avatar.dart';
import '../../shared/widgets/vendor_promo_badge.dart';
import '../../shared/widgets/vendor_story_ring.dart';
import '../orders/orders_repository.dart';
import 'customer_shop_promo_float.dart';
import 'customer_shop_stories_rail.dart';
import 'customer_vendor_menu_screen.dart';
import 'vendor_story_viewer.dart';

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
  Map<String, int> _seenPostedAt = {};
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _categoryId = 'pharmacy';
  String? _mapSelectedVendorId;
  SocketService? _socket;
  VendorPromoHandler? _promoHandler;
  ShopMessageHandler? _shopChatHandler;
  Timer? _searchDebounce;
  bool _drugSearching = false;
  List<PharmacySearchHit> _drugHits = [];
  bool _drugSearchActive = false;

  @override
  void initState() {
    super.initState();
    _wirePromoSocket();
    _wireShopChatSocket();
    _loadSeen();
    _load();
  }

  Future<void> _loadSeen() async {
    final seen = await ShopStoryViews.loadSeenPostedAt();
    if (!mounted) return;
    setState(() => _seenPostedAt = seen);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    if (_promoHandler != null) {
      _socket?.removeVendorPromoListener(_promoHandler!);
    }
    if (_shopChatHandler != null) {
      _socket?.removeShopMessageListener(_shopChatHandler!);
    }
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() {
        _drugSearchActive = false;
        _drugHits = [];
        _drugSearching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () => _runDrugSearch(q));
  }

  Future<void> _runDrugSearch(String query) async {
    setState(() {
      _drugSearching = true;
      _drugSearchActive = true;
    });
    try {
      final region = context.read<Session>().user?.region;
      final hits = await context.read<OrdersRepository>().searchPharmaciesByDrug(
            query: query,
            region: region,
            category: _categoryId,
          );
      if (!mounted || _searchCtrl.text.trim() != query) return;
      setState(() {
        _drugHits = hits;
        _drugSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _drugSearching = false);
    }
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

  void _wireShopChatSocket() {
    _socket = context.read<SocketService>();
    _shopChatHandler = (conversationId, message) {
      if (!mounted || message.isMine) return;
      context.read<ShopChatUnread>().increment(conversationId);
    };
    _socket!.addShopMessageListener(_shopChatHandler!);
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
    final q = _searchCtrl.text.trim();
    if (q.length >= 2) _runDrugSearch(q);
  }

  Map<String, List<Product>> get _drugMatches => {
        for (final hit in _drugHits) hit.vendor.id: hit.matches,
      };

  List<Vendor> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    var list = _vendors;

    if (_drugSearchActive && q.length >= 2) {
      list = _drugHits.map((h) => h.vendor).toList();
      if (q.isNotEmpty && list.isEmpty && !_drugSearching) {
        list = _vendors
            .where((v) =>
                v.name.toLowerCase().contains(q) ||
                (v.address?.toLowerCase().contains(q) ?? false))
            .toList();
      }
    } else if (q.isNotEmpty) {
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

  List<Vendor> get _storyVendors =>
      _vendors.where((v) => v.hasActiveStory).toList();

  Future<void> _markStorySeen(Vendor vendor) async {
    await ShopStoryViews.markSeen(vendor);
    final posted = vendor.shopStoryPostedAt?.millisecondsSinceEpoch;
    if (posted == null || !mounted) return;
    setState(() => _seenPostedAt = {..._seenPostedAt, vendor.id: posted});
  }

  Future<void> _openShopStories({Vendor? startVendor}) async {
    final stories = _storyVendors;
    if (stories.isEmpty) return;
    var index = 0;
    if (startVendor != null) {
      final i = stories.indexWhere((v) => v.id == startVendor.id);
      if (i >= 0) index = i;
    }
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, __, ___) => VendorStoryViewer(
          vendors: stories,
          initialIndex: index,
          seenPostedAt: _seenPostedAt,
          onSeen: _markStorySeen,
          onOrder: _openVendorMenu,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (mounted) await _loadSeen();
  }

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
              child: PharmacyHubWelcome(
                categoryLabel: _categoryId == 'health'
                    ? 'HEALTH RETAIL HUB'
                    : 'PHARMACY HUB',
                openCount: _openShopCount,
                listedCount: filtered.length,
                onSearchTap: () {
                  _searchFocus.requestFocus();
                },
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
          if (!_loading && _error == null && _storyVendors.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: CustomerShopStoriesRail(
                  vendors: _vendors,
                  seenPostedAt: _seenPostedAt,
                  onSeenVendor: _markStorySeen,
                  onOrderFromStory: _openVendorMenu,
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
                      label: 'All listed',
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
                focusNode: _searchFocus,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search medicine, brand, or pharmacy…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _drugSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: BytzGoTheme.brandBlue.withValues(alpha: 0.18),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: BytzGoTheme.sheetDivider.withValues(alpha: 0.9),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: BytzGoTheme.brandBlue,
                      width: 1.5,
                    ),
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
                        _drugSearchActive && _searchCtrl.text.trim().length >= 2
                            ? 'No pharmacy stocks "${_searchCtrl.text.trim()}" yet'
                            : 'No ${cat.label.toLowerCase()} in your area yet',
                        style: BytzGoTheme.sheetTitle(16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _drugSearchActive
                            ? 'Try a different spelling or browse all pharmacies.'
                            : 'Try the other tab or check back soon.',
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Text(
                      'NEAR YOU',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: BytzGoTheme.sheetMuted.withValues(alpha: 0.9),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${filtered.length} ${cat.label.toLowerCase()}',
                      style: BytzGoTheme.sheetBody(11),
                    ),
                  ],
                ),
              ),
            ),
          if (!_loading && _error == null && filtered.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final v = filtered[i];
                    final chip = ShopCategory.byId(v.shopCategory) ?? cat;
                    final closed = v.shopOpenStatus == 'closed';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Opacity(
                        opacity: closed ? 0.72 : 1,
                        child: Material(
                          color: BytzGoTheme.sheetBg,
                          elevation: 0,
                          shadowColor: chip.accent.withValues(alpha: 0.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: chip.accent.withValues(alpha: closed ? 0.12 : 0.22),
                            ),
                          ),
                          child: InkWell(
                            onTap: () => _openVendorMenu(v),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    chip.accent.withValues(alpha: 0.04),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  if (v.hasActiveStory)
                                    VendorStoryRing(
                                      vendor: v,
                                      size: 56,
                                      unseen: ShopStoryViews.showStoryRing(
                                        v,
                                        _seenPostedAt,
                                      ),
                                      onTap: () => _openShopStories(startVendor: v),
                                    )
                                  else
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
                                        if (_drugMatches[v.id]?.isNotEmpty == true) ...[
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: _drugMatches[v.id]!
                                                .take(3)
                                                .map(
                                                  (p) => Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: BytzGoTheme.accent.withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(
                                                        color: BytzGoTheme.accent.withValues(alpha: 0.25),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      '${p.name} · ${formatCedis(p.price)}',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w700,
                                                        color: BytzGoTheme.accentDark,
                                                      ),
                                                    ),
                                                  ),
                                                )
                                                .toList(),
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
                                            TextButton.icon(
                                              onPressed: () => openShopChatWithVendor(context, vendor: v),
                                              icon: const Icon(Icons.chat_bubble_outline, size: 16),
                                              label: const Text('Chat'),
                                              style: TextButton.styleFrom(
                                                foregroundColor: BytzGoTheme.accent,
                                                padding: EdgeInsets.zero,
                                                minimumSize: const Size(0, 32),
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                            ),
                                            if (v.phone != null && v.phone!.trim().isNotEmpty)
                                              const SizedBox(width: 8),
                                            TextButton.icon(
                                              onPressed: () => showVendorMapPicker(context, v),
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
