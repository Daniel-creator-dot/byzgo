import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/admin_pending_product.dart';
import '../../shared/data_url_image.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import 'admin_repository.dart';
import 'widgets/admin_hero_header.dart';

/// Admin — approve or reject vendor menu items before customers see them.
class AdminMenuTab extends StatefulWidget {
  const AdminMenuTab({super.key, this.onPendingCount});

  final ValueChanged<int>? onPendingCount;

  @override
  State<AdminMenuTab> createState() => AdminMenuTabState();
}

class AdminMenuTabState extends State<AdminMenuTab> {
  List<AdminPendingProduct> _items = [];
  bool _loading = true;
  String? _error;

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
      final list = await context.read<AdminRepository>().fetchPendingProducts();
      if (!mounted) return;
      widget.onPendingCount?.call(list.length);
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AdminRepository.errorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _approve(AdminPendingProduct p) async {
    try {
      await context.read<AdminRepository>().approveProduct(p.id);
      await load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${p.name} approved for customers'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AdminRepository.errorMessage(e)),
          backgroundColor: BytzGoTheme.danger,
        ),
      );
    }
  }

  Future<void> _reject(AdminPendingProduct p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Reject menu item?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "${p.name}" from the approval queue? The vendor can upload again.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: BytzGoTheme.danger),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AdminRepository>().rejectProduct(p.id);
      await load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${p.name} rejected'), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AdminRepository.errorMessage(e)),
          backgroundColor: BytzGoTheme.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: load,
      color: BytzGoTheme.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          AdminHeroHeader(
            title: 'Menu approval',
            subtitle: '${_items.length} items waiting',
            assetPath: 'assets/branding/hero_delivery.png',
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: BytzGoTheme.accent),
              ),
            )
          else if (_error != null)
            _card(_error!, isError: true)
          else if (_items.isEmpty)
            _card('No menu items waiting for approval.')
          else
            ..._items.map(_tile),
        ],
      ),
    );
  }

  Widget _card(String msg, {bool isError = false}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isError ? BytzGoTheme.danger : const Color(0xFF1E293B)),
        ),
        child: Text(msg, style: TextStyle(color: isError ? Colors.redAccent : Colors.white54)),
      );

  Widget _tile(AdminPendingProduct p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: dataUrlImage(p.imageUrl, height: 64),
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
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    if (p.vendorName != null)
                      Text(
                        p.vendorName!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                    Text(
                      '${p.category ?? 'Item'} · ${formatCedis(p.price)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _reject(p),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _approve(p),
                  style: FilledButton.styleFrom(
                    backgroundColor: BytzGoTheme.accent,
                    foregroundColor: const Color(0xFF022C22),
                  ),
                  child: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
