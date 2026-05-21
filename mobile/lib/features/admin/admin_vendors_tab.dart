import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/admin_vendor.dart';
import '../../shared/shop_categories.dart';
import '../../shared/theme.dart';
import 'admin_repository.dart';
import 'widgets/admin_hero_header.dart';

/// Admin — create merchant accounts and approve pending stores.
class AdminVendorsTab extends StatefulWidget {
  const AdminVendorsTab({super.key, this.onPendingCount});

  final ValueChanged<int>? onPendingCount;

  @override
  State<AdminVendorsTab> createState() => AdminVendorsTabState();
}

class AdminVendorsTabState extends State<AdminVendorsTab> {
  List<AdminVendor> _vendors = [];
  bool _loading = true;
  String? _error;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AdminVendor> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _vendors;
    return _vendors.where((v) {
      return v.name.toLowerCase().contains(q) ||
          v.email.toLowerCase().contains(q) ||
          (v.phone ?? '').toLowerCase().contains(q) ||
          (v.shopCategory ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<AdminRepository>().fetchVendors();
      if (!mounted) return;
      final pending = list.where((v) => v.isPending).length;
      widget.onPendingCount?.call(pending);
      setState(() {
        _vendors = list;
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

  Future<void> _setStatus(AdminVendor v, String status, {String? successMsg}) async {
    try {
      await context.read<AdminRepository>().setUserStatus(userId: v.id, status: status);
      await load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMsg ?? '${v.name} → $status'),
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

  Future<void> _confirmDelete(AdminVendor v) async {
    if (v.activeOrders > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot delete ${v.name}: ${v.activeOrders} active order(s). Disable the account or wait for orders to finish.',
          ),
          backgroundColor: BytzGoTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Delete store account?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Permanently remove "${v.name}" (${v.email})?\n\n'
          'All ${v.productCount} menu items will be deleted. Past orders stay in the system without this store.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: BytzGoTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AdminRepository>().deleteVendor(v.id);
      await load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${v.name} removed'),
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

  void _openCreateSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CreateVendorSheet(
        onCreated: (result) async {
          Navigator.pop(ctx);
          await load();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final pending = list.where((v) => v.isPending).toList();
    final active = list.where((v) => v.isActive).toList();
    final disabled = list.where((v) => v.isDisabled).toList();
    final other = list
        .where((v) => !v.isPending && !v.isActive && !v.isDisabled)
        .toList();

    return RefreshIndicator(
      onRefresh: load,
      color: BytzGoTheme.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          AdminHeroHeader(
            title: 'Store accounts',
            subtitle: '${_vendors.length} vendors · search, approve, delete',
            assetPath: 'assets/branding/hero_delivery.png',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _openCreateSheet,
            icon: const Icon(Icons.add_business),
            label: const Text('Create store account'),
            style: FilledButton.styleFrom(
              backgroundColor: BytzGoTheme.accent,
              foregroundColor: const Color(0xFF022C22),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Merchants log in on the BytzGo app as Vendor, then add menu photos and prices.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search stores by name, email, phone…',
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
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: BytzGoTheme.accent),
              ),
            )
          else if (_error != null)
            _messageCard(_error!, isError: true)
          else ...[
            if (pending.isNotEmpty) ...[
              _sectionLabel('Pending approval (${pending.length})'),
              ...pending.map((v) => _vendorTile(v, showApprove: true)),
              const SizedBox(height: 12),
            ],
            _sectionLabel('Active stores (${active.length})'),
            if (active.isEmpty && pending.isEmpty && disabled.isEmpty && other.isEmpty)
              _messageCard('No stores yet. Create the first merchant account above.')
            else
              ...active.map((v) => _vendorTile(v)),
            if (disabled.isNotEmpty) ...[
              const SizedBox(height: 8),
              _sectionLabel('Disabled / rejected (${disabled.length})'),
              ...disabled.map((v) => _vendorTile(v)),
            ],
            if (other.isNotEmpty) ...[
              const SizedBox(height: 8),
              _sectionLabel('Other (${other.length})'),
              ...other.map((v) => _vendorTile(v)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String t) => Padding(
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

  Widget _messageCard(String msg, {bool isError = false}) => Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isError ? BytzGoTheme.danger : const Color(0xFF1E293B),
          ),
        ),
        child: Text(
          msg,
          style: TextStyle(color: isError ? Colors.redAccent : Colors.white54),
        ),
      );

  Widget _vendorTile(AdminVendor v, {bool showApprove = false}) {
    final cat = ShopCategory.labelFor(v.shopCategory);
    final showApproveBtn = showApprove || v.isPending;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: v.isPending
              ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
              : const Color(0xFF1E293B),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFA78BFA).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.storefront, color: Color(0xFFA78BFA), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      v.status.toUpperCase(),
                      style: TextStyle(
                        color: v.isPending
                            ? const Color(0xFFFBBF24)
                            : BytzGoTheme.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '$cat · ${v.productCount} items'
                      '${v.pendingProducts > 0 ? ' · ${v.pendingProducts} pending menu' : ''}'
                      '${v.activeOrders > 0 ? ' · ${v.activeOrders} active orders' : ''}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white54),
                color: const Color(0xFF0F172A),
                onSelected: (action) async {
                  switch (action) {
                    case 'approve':
                      await _setStatus(
                        v,
                        'active',
                        successMsg: '${v.name} approved — can log in and upload menu',
                      );
                    case 'disable':
                      await _setStatus(v, 'disabled', successMsg: '${v.name} disabled');
                    case 'enable':
                      await _setStatus(v, 'active', successMsg: '${v.name} re-enabled');
                    case 'reject':
                      await _setStatus(v, 'rejected', successMsg: '${v.name} rejected');
                    case 'delete':
                      await _confirmDelete(v);
                  }
                },
                itemBuilder: (ctx) => [
                  if (v.isPending)
                    const PopupMenuItem(
                      value: 'approve',
                      child: Text('Approve account', style: TextStyle(color: Colors.white)),
                    ),
                  if (v.isActive || v.isPending)
                    const PopupMenuItem(
                      value: 'disable',
                      child: Text('Disable login', style: TextStyle(color: Colors.white)),
                    ),
                  if (v.isDisabled)
                    const PopupMenuItem(
                      value: 'enable',
                      child: Text('Re-enable account', style: TextStyle(color: Colors.white)),
                    ),
                  if (v.isPending)
                    const PopupMenuItem(
                      value: 'reject',
                      child: Text('Reject application', style: TextStyle(color: Colors.white)),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete account', style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            v.email,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
          ),
          if (v.phone != null && v.phone!.isNotEmpty)
            Text(
              v.phone!,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
            ),
          if (showApproveBtn) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _setStatus(
                v,
                'active',
                successMsg: '${v.name} approved — can log in and upload menu',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: BytzGoTheme.accent,
                foregroundColor: const Color(0xFF022C22),
              ),
              child: const Text('Approve — allow login & menu uploads'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CreateVendorSheet extends StatefulWidget {
  const _CreateVendorSheet({required this.onCreated});

  final ValueChanged<CreateVendorResult> onCreated;

  @override
  State<_CreateVendorSheet> createState() => _CreateVendorSheetState();
}

class _CreateVendorSheetState extends State<_CreateVendorSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _address = TextEditingController();
  String _category = 'food';
  bool _activate = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _password.text.length < 6) {
      setState(() => _error = 'Name, email, and password (6+ chars) are required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await context.read<AdminRepository>().createVendor(
            name: _name.text,
            email: _email.text,
            password: _password.text,
            phone: _phone.text,
            shopCategory: _category,
            address: _address.text,
            activate: _activate,
          );
      widget.onCreated(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AdminRepository.errorMessage(e);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0B1220),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'New store account',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Share the email/phone and password with the shop owner. They sign in as Vendor on the app.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              _field(_name, 'Store name', Icons.store),
              _field(_email, 'Email (login)', Icons.email_outlined),
              _field(_phone, 'Ghana phone (login)', Icons.phone_outlined),
              _field(_password, 'Password', Icons.lock_outline, obscure: true),
              _field(_address, 'Shop address (optional)', Icons.location_on_outlined),
              const SizedBox(height: 8),
              Text(
                'SHOP CATEGORY',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ShopCategory.ordered.map((c) {
                  final selected = _category == c.id;
                  return FilterChip(
                    label: Text(c.label),
                    selected: selected,
                    onSelected: (_) => setState(() => _category = c.id),
                    selectedColor: c.accent.withValues(alpha: 0.25),
                  );
                }).toList(),
              ),
              SwitchListTile(
                value: _activate,
                onChanged: _saving ? null : (v) => setState(() => _activate = v),
                title: const Text(
                  'Activate immediately',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  _activate
                      ? 'Merchant can log in and upload menu right away'
                      : 'Stay pending until you approve',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
                ),
                activeThumbColor: BytzGoTheme.accent,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: BytzGoTheme.accent,
                  foregroundColor: const Color(0xFF022C22),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create account'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          prefixIcon: Icon(icon, color: Colors.white38, size: 20),
          filled: true,
          fillColor: const Color(0xFF0F172A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1E293B)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1E293B)),
          ),
        ),
      ),
    );
  }
}
