import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/admin_ride_promotion.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import 'admin_repository.dart';

/// Uber/Yango-style ride promotions: customer discounts + rider bonuses.
class AdminPromotionsTab extends StatefulWidget {
  const AdminPromotionsTab({super.key});

  @override
  State<AdminPromotionsTab> createState() => _AdminPromotionsTabState();
}

class _AdminPromotionsTabState extends State<AdminPromotionsTab> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<AdminRidePromotion> _promos = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<AdminRepository>().fetchRidePromotions();
      if (!mounted) return;
      setState(() {
        _promos = list;
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

  Future<void> _openEditor([AdminRidePromotion? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final codeCtrl = TextEditingController(text: existing?.code ?? '');
    final pctCtrl = TextEditingController(
      text: (existing?.customerDiscountPercent ?? 0).toString(),
    );
    final fixedCtrl = TextEditingController(
      text: (existing?.customerDiscountFixed ?? 0).toString(),
    );
    final bonusCtrl = TextEditingController(
      text: (existing?.riderBonusAmount ?? 0).toString(),
    );
    final regionCtrl = TextEditingController(text: existing?.targetRegion ?? '');
    final maxCtrl = TextEditingController(
      text: existing?.maxRedemptions?.toString() ?? '',
    );
    var okada = (existing?.serviceTypes ?? 'okada,keke,package').contains('okada');
    var keke = (existing?.serviceTypes ?? 'okada,keke,package').contains('keke');
    var package =
        (existing?.serviceTypes ?? 'okada,keke,package').contains('package');
    var enabled = existing?.enabled ?? true;
    var announceSms = existing == null;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      existing == null ? 'New promotion' : 'Edit promotion',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _sheetField(nameCtrl, 'Name', 'Evening Okada bonus'),
                    _sheetField(codeCtrl, 'Promo code (optional)', 'OKADA20'),
                    _sheetField(pctCtrl, 'Customer discount %', '10'),
                    _sheetField(fixedCtrl, 'Customer discount fixed ₵', '0'),
                    _sheetField(bonusCtrl, 'Rider bonus ₵', '5'),
                    _sheetField(regionCtrl, 'Target region (blank = all)', 'Accra'),
                    _sheetField(maxCtrl, 'Max redemptions (blank = unlimited)', '500'),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: okada,
                      onChanged: (v) => setSheetState(() => okada = v ?? false),
                      title: const Text('Okada', style: TextStyle(color: Colors.white70)),
                      activeColor: BytzGoTheme.accent,
                      dense: true,
                    ),
                    CheckboxListTile(
                      value: keke,
                      onChanged: (v) => setSheetState(() => keke = v ?? false),
                      title: const Text('Keke', style: TextStyle(color: Colors.white70)),
                      activeColor: BytzGoTheme.accent,
                      dense: true,
                    ),
                    CheckboxListTile(
                      value: package,
                      onChanged: (v) => setSheetState(() => package = v ?? false),
                      title: const Text('Package', style: TextStyle(color: Colors.white70)),
                      activeColor: BytzGoTheme.accent,
                      dense: true,
                    ),
                    SwitchListTile(
                      value: enabled,
                      onChanged: (v) => setSheetState(() => enabled = v),
                      title: const Text('Enabled', style: TextStyle(color: Colors.white)),
                      activeThumbColor: BytzGoTheme.accent,
                    ),
                    if (existing == null)
                      SwitchListTile(
                        value: announceSms,
                        onChanged: (v) => setSheetState(() => announceSms = v),
                        title: const Text('SMS announcement', style: TextStyle(color: Colors.white)),
                        subtitle: const Text(
                          'Text customers in target region (riders if bonus set)',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        activeThumbColor: BytzGoTheme.accent,
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: BytzGoTheme.accent,
                        foregroundColor: BytzGoTheme.sheetText,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('Save promotion'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (saved != true || !mounted) {
      nameCtrl.dispose();
      codeCtrl.dispose();
      pctCtrl.dispose();
      fixedCtrl.dispose();
      bonusCtrl.dispose();
      regionCtrl.dispose();
      maxCtrl.dispose();
      return;
    }

    final types = [
      if (okada) 'okada',
      if (keke) 'keke',
      if (package) 'package',
    ].join(',');
    if (types.isEmpty) {
      _snack('Select at least one service');
      return;
    }

    setState(() => _saving = true);
    try {
      final body = AdminRidePromotion(
        id: existing?.id ?? '',
        name: nameCtrl.text.trim(),
        code: codeCtrl.text.trim().isEmpty ? null : codeCtrl.text.trim(),
        serviceTypes: types,
        customerDiscountPercent: double.tryParse(pctCtrl.text) ?? 0,
        customerDiscountFixed: double.tryParse(fixedCtrl.text) ?? 0,
        riderBonusAmount: double.tryParse(bonusCtrl.text) ?? 0,
        targetRegion: regionCtrl.text.trim().isEmpty ? null : regionCtrl.text.trim(),
        enabled: enabled,
        redemptionCount: existing?.redemptionCount ?? 0,
        maxRedemptions: maxCtrl.text.trim().isEmpty
            ? null
            : int.tryParse(maxCtrl.text.trim()),
      );
      if (existing == null) {
        await context.read<AdminRepository>().createRidePromotion(body, announceSms: announceSms);
      } else {
        await context.read<AdminRepository>().updateRidePromotion(
              existing.id,
              body.toBody(),
            );
      }
      if (!mounted) return;
      _snack('Promotion saved', success: true);
      await _load();
    } catch (e) {
      _snack(AdminRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
      nameCtrl.dispose();
      codeCtrl.dispose();
      pctCtrl.dispose();
      fixedCtrl.dispose();
      bonusCtrl.dispose();
      regionCtrl.dispose();
      maxCtrl.dispose();
    }
  }

  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? BytzGoTheme.accent : Colors.redAccent,
      ),
    );
  }

  Widget _sheetField(TextEditingController c, String label, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: const Color(0xFF1E293B),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: BytzGoTheme.accent));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
          children: [
            Text(
              'Active promotions auto-apply by service & region. Rider bonuses credit on delivery.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_promos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No promotions yet. Tap + to create one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ..._promos.map(_promoCard),
          ],
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: FloatingActionButton.extended(
            onPressed: _saving ? null : () => _openEditor(),
            backgroundColor: BytzGoTheme.accent,
            foregroundColor: BytzGoTheme.sheetText,
            icon: const Icon(Icons.add),
            label: const Text('Promo'),
          ),
        ),
      ],
    );
  }

  Widget _promoCard(AdminRidePromotion p) {
    return Card(
      color: const Color(0xFF1E293B),
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(
          p.name,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            if (p.code != null && p.code!.isNotEmpty) 'Code: ${p.code}',
            p.serviceTypes,
            if (p.customerDiscountPercent > 0) '${p.customerDiscountPercent}% off',
            if (p.customerDiscountFixed > 0) '${formatCedis(p.customerDiscountFixed)} off',
            if (p.riderBonusAmount > 0) 'Rider +${formatCedis(p.riderBonusAmount)}',
            if (p.targetRegion != null) p.targetRegion!,
            '${p.redemptionCount}${p.maxRedemptions != null ? '/${p.maxRedemptions}' : ''} used',
          ].join(' · '),
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            if (action == 'announce') {
              await context.read<AdminRepository>().announceRidePromotion(p.id);
              await _load();
              if (mounted) _snack('Promotion SMS blast started', success: true);
            } else if (action == 'edit') {
              await _openEditor(p);
            } else if (action == 'toggle') {
              await context.read<AdminRepository>().updateRidePromotion(
                    p.id,
                    {'enabled': !p.enabled},
                  );
              await _load();
            } else if (action == 'delete') {
              await context.read<AdminRepository>().deleteRidePromotion(p.id);
              await _load();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'announce', child: Text('SMS blast')),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(p.enabled ? 'Disable' : 'Enable'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        leading: Icon(
          p.enabled ? Icons.local_offer : Icons.block,
          color: p.enabled ? BytzGoTheme.accent : Colors.white38,
        ),
      ),
    );
  }
}
