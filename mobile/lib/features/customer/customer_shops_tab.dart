import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../models/location_point.dart';
import '../../models/vendor.dart';
import '../../shared/theme.dart';
import '../orders/orders_repository.dart';
import 'customer_vendor_menu_screen.dart';
class CustomerShopsTab extends StatefulWidget {
  const CustomerShopsTab({
    super.key,
    required this.onShopPickup,
  });

  /// User picked a shop — switch to ride tab with pickup set.
  final void Function(LocationPoint pickup) onShopPickup;

  @override
  State<CustomerShopsTab> createState() => _CustomerShopsTabState();
}

class _CustomerShopsTabState extends State<CustomerShopsTab> {
  List<Vendor> _vendors = [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final region = context.read<Session>().user?.region;
      final list =
          await context.read<OrdersRepository>().fetchVendors(region: region);
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

  List<Vendor> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _vendors;
    return _vendors
        .where((v) =>
            v.name.toLowerCase().contains(q) ||
            (v.address?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  void _openVendorMenu(Vendor vendor) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => CustomerVendorMenuScreen(
          vendor: vendor,
          onBookPickup: widget.onShopPickup,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search shops & restaurants',
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
        const SizedBox(height: 12),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: BytzGoTheme.danger),
                      ),
                    )
                  : _filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No shops in your area yet',
                            style: BytzGoTheme.sheetBody(14),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: _filtered.length,
                            itemBuilder: (context, i) {
                              final v = _filtered[i];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Material(
                                  color: BytzGoTheme.sheetDivider
                                      .withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    onTap: () => _openVendorMenu(v),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 52,
                                            height: 52,
                                            decoration: BoxDecoration(
                                              color: BytzGoTheme.accent
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: const Icon(
                                              Icons.storefront,
                                              color: BytzGoTheme.accentDark,
                                              size: 28,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  v.name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 16,
                                                    color: BytzGoTheme.sheetText,
                                                  ),
                                                ),
                                                if (v.address != null) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    v.address!,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: BytzGoTheme.sheetBody(
                                                      12,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          const Icon(
                                            Icons.chevron_right,
                                            color: BytzGoTheme.brandBlue,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}
