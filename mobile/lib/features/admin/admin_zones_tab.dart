import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/delivery_pricing_config.dart';
import '../../models/delivery_zone.dart';
import '../../shared/format.dart';
import '../../shared/ghana_regions.dart';
import '../../shared/theme.dart';
import 'admin_repository.dart';

/// Region min/max delivery fee caps (uses global ₵/km rate).
class AdminZonesTab extends StatefulWidget {
  const AdminZonesTab({super.key});

  @override
  State<AdminZonesTab> createState() => _AdminZonesTabState();
}

class _AdminZonesTabState extends State<AdminZonesTab> {
  List<DeliveryZone> _zones = [];
  bool _loading = true;
  String? _error;
  bool _showForm = false;
  DeliveryZone? _editing;

  final _nameCtrl = TextEditingController();
  final _minCtrl = TextEditingController(text: '5');
  final _maxCtrl = TextEditingController();
  String _region = ghanaRegions.first;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<AdminRepository>().fetchDeliveryZones();
      if (!mounted) return;
      setState(() {
        _zones = list;
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

  void _openForm({DeliveryZone? zone}) {
    _editing = zone;
    if (zone != null) {
      _nameCtrl.text = zone.name;
      _region = zone.region;
      _minCtrl.text = zone.minPrice.toStringAsFixed(2);
      _maxCtrl.text =
          zone.maxPrice != null ? zone.maxPrice!.toStringAsFixed(2) : '';
    } else {
      _nameCtrl.clear();
      _region = ghanaRegions.first;
      _minCtrl.text = '5';
      _maxCtrl.clear();
    }
    setState(() => _showForm = true);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Enter a zone name');
      return;
    }
    final min = double.tryParse(_minCtrl.text.trim());
    if (min == null || min <= 0) {
      _snack('Enter a valid minimum fee');
      return;
    }
    final maxRaw = _maxCtrl.text.trim();
    double? max;
    if (maxRaw.isNotEmpty) {
      max = double.tryParse(maxRaw);
      if (max == null || max <= 0) {
        _snack('Maximum fee must be a positive number or empty');
        return;
      }
      if (max < min) {
        _snack('Maximum must be ≥ minimum');
        return;
      }
    }

    final rate = context.read<DeliveryPricingConfig>().basePricePerKm;
    final zone = DeliveryZone(
      id: _editing?.id ?? '',
      name: name,
      region: _region,
      minPrice: min,
      maxPrice: max,
      isActive: _editing?.isActive ?? true,
    );

    try {
      final repo = context.read<AdminRepository>();
      if (_editing != null) {
        await repo.updateDeliveryZone(
          _editing!.id,
          zone,
          globalRatePerKm: rate,
        );
      } else {
        await repo.createDeliveryZone(zone, globalRatePerKm: rate);
      }
      await context.read<DeliveryPricingConfig>().refresh();
      if (!mounted) return;
      setState(() => _showForm = false);
      _snack('Zone saved', success: true);
      await _load();
    } catch (e) {
      _snack(AdminRepository.errorMessage(e));
    }
  }

  Future<void> _toggleActive(DeliveryZone zone) async {
    final rate = context.read<DeliveryPricingConfig>().basePricePerKm;
    try {
      await context.read<AdminRepository>().updateDeliveryZone(
            zone.id,
            DeliveryZone(
              id: zone.id,
              name: zone.name,
              region: zone.region,
              minPrice: zone.minPrice,
              maxPrice: zone.maxPrice,
              isActive: !zone.isActive,
            ),
            globalRatePerKm: rate,
          );
      await context.read<DeliveryPricingConfig>().refresh();
      await _load();
    } catch (e) {
      _snack(AdminRepository.errorMessage(e));
    }
  }

  Future<void> _delete(DeliveryZone zone) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete zone?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove ${zone.name} (${zone.region})?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await context.read<AdminRepository>().deleteDeliveryZone(zone.id);
      await context.read<DeliveryPricingConfig>().refresh();
      await _load();
      if (mounted) _snack('Zone deleted', success: true);
    } catch (e) {
      _snack(AdminRepository.errorMessage(e));
    }
  }

  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? BytzGoTheme.accent : Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: BytzGoTheme.accent),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(
          'Fee = distance × global ₵/km, then clamped to min/max for the customer\'s region.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
        ),
        const SizedBox(height: 12),
        if (_showForm) ...[
          _formCard(),
          const SizedBox(height: 12),
        ] else
          OutlinedButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Add delivery zone'),
            style: OutlinedButton.styleFrom(
              foregroundColor: BytzGoTheme.accent,
              side: BorderSide(color: BytzGoTheme.accent.withValues(alpha: 0.5)),
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        const SizedBox(height: 12),
        if (_zones.isEmpty && !_showForm)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'No zones yet — global min/max apply everywhere.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
        ..._zones.map(_zoneCard),
      ],
    );
  }

  Widget _formCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BytzGoTheme.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _editing == null ? 'New zone' : 'Edit zone',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          _field(_nameCtrl, 'Zone name', 'Accra Metro'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _region,
            dropdownColor: const Color(0xFF1E293B),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            decoration: _inputDecoration('Region'),
            items: ghanaRegions
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _region = v);
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _field(_minCtrl, 'Minimum fee (₵)', '8')),
              const SizedBox(width: 8),
              Expanded(
                child: _field(_maxCtrl, 'Maximum fee (₵)', 'Optional'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: BytzGoTheme.accent,
                    foregroundColor: BytzGoTheme.sheetText,
                  ),
                  child: Text(_editing == null ? 'Create' : 'Update'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() => _showForm = false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _zoneCard(DeliveryZone zone) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: zone.isActive
              ? Colors.white12
              : Colors.redAccent.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zone.name,
                      style: TextStyle(
                        color: zone.isActive ? Colors.white : Colors.white54,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      zone.region,
                      style: TextStyle(
                        color: BytzGoTheme.accent.withValues(alpha: 0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: zone.isActive,
                onChanged: (_) => _toggleActive(zone),
                activeThumbColor: BytzGoTheme.accent,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _chip('Min', formatCedis(zone.minPrice)),
              const SizedBox(width: 8),
              _chip(
                'Max',
                zone.maxPrice != null ? formatCedis(zone.maxPrice!) : 'No cap',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _openForm(zone: zone),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: () => _delete(zone),
                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                label: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      decoration: _inputDecoration(label, hint: hint),
    );
  }

  InputDecoration _inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
      filled: true,
      fillColor: const Color(0xFF0F172A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}
