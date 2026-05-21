import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/places_service.dart';
import '../../models/location_point.dart';
import '../../models/vendor.dart';
import '../../shared/vendor_pickup.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/sheet_theme_scope.dart';
import '../orders/orders_repository.dart';

/// Pick a shop/vendor as pickup location.
Future<LocationPoint?> showCustomerShopsSheet(
  BuildContext context, {
  String? region,
}) {
  return showModalBottomSheet<LocationPoint>(
    context: context,
    isScrollControlled: true,
    backgroundColor: BytzGoTheme.sheetBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SheetThemeScope(
          child: _CustomerShopsSheet(region: region),
        ),
  );
}

class _CustomerShopsSheet extends StatefulWidget {
  const _CustomerShopsSheet({this.region});

  final String? region;

  @override
  State<_CustomerShopsSheet> createState() => _CustomerShopsSheetState();
}

class _CustomerShopsSheetState extends State<_CustomerShopsSheet> {
  List<Vendor> _vendors = [];
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
      final list = await context.read<OrdersRepository>().fetchVendors(
            region: widget.region,
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

  Future<void> _selectVendor(Vendor vendor) async {
    final point = await resolveVendorPickup(
      vendor,
      context.read<PlacesService>(),
    );
    if (!mounted) return;
    if (point == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not find this shop on the map — try another store.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.pop(context, point);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: BytzGoTheme.sheetDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Order from shops', style: BytzGoTheme.sheetTitle()),
            const SizedBox(height: 4),
            Text(
              'Pick a shop as your pickup point',
              style: BytzGoTheme.sheetBody(14),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: const TextStyle(color: BytzGoTheme.danger)),
              )
            else if (_vendors.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No shops available in your area yet.',
                  style: BytzGoTheme.sheetBody(14),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _vendors.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final v = _vendors[i];
                    return Material(
                      color: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () => _selectVendor(v),
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: BytzGoTheme.accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.storefront_outlined,
                                  color: BytzGoTheme.accentDark,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        color: BytzGoTheme.sheetText,
                                      ),
                                    ),
                                    if (v.address != null && v.address!.isNotEmpty)
                                      Text(
                                        v.address!,
                                        style: BytzGoTheme.sheetBody(12),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: BytzGoTheme.sheetMuted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
