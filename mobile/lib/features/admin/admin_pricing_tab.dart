import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/admin_pricing_settings.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import 'admin_repository.dart';
import 'widgets/admin_hero_header.dart';

/// Admin controls for delivery rate per km and surge window (Ghana time).
class AdminPricingTab extends StatefulWidget {
  const AdminPricingTab({super.key});

  @override
  State<AdminPricingTab> createState() => _AdminPricingTabState();
}

class _AdminPricingTabState extends State<AdminPricingTab> {
  final _rateCtrl = TextEditingController();
  final _multCtrl = TextEditingController();
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();

  bool _surgeEnabled = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _surgeActiveNow = false;
  String? _ghanaTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _rateCtrl.dispose();
    _multCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await context.read<AdminRepository>().fetchPricingSettings();
      if (!mounted) return;
      setState(() {
        _rateCtrl.text = s.deliveryPricePerKm;
        _multCtrl.text = s.surgeMultiplier.toStringAsFixed(2);
        _startCtrl.text = s.surgeStartTime;
        _endCtrl.text = s.surgeEndTime;
        _surgeEnabled = s.surgeEnabled;
        _surgeActiveNow = s.surgeActiveNow;
        _ghanaTime = s.ghanaTime;
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

  Future<void> _save() async {
    final rate = double.tryParse(_rateCtrl.text.trim());
    if (rate == null || rate <= 0) {
      _snack('Enter a valid price per km');
      return;
    }
    final mult = double.tryParse(_multCtrl.text.trim());
    if (mult == null || mult < 1) {
      _snack('Surge multiplier must be at least 1.0');
      return;
    }
    if (!_isValidTime(_startCtrl.text) || !_isValidTime(_endCtrl.text)) {
      _snack('Use HH:MM for surge times (e.g. 17:00)');
      return;
    }

    setState(() => _saving = true);
    try {
      final body = AdminPricingSettings(
        deliveryPricePerKm: rate.toString(),
        surgeEnabled: _surgeEnabled,
        surgeMultiplier: mult,
        surgeStartTime: _startCtrl.text.trim(),
        surgeEndTime: _endCtrl.text.trim(),
      );
      await context.read<AdminRepository>().savePricingSettings(body);
      if (!mounted) return;
      _snack('Pricing saved', success: true);
      await _load();
    } catch (e) {
      _snack(AdminRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _isValidTime(String t) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t.trim());
    if (m == null) return false;
    final h = int.tryParse(m.group(1) ?? '');
    final min = int.tryParse(m.group(2) ?? '');
    return h != null && min != null && h >= 0 && h <= 23 && min >= 0 && min <= 59;
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AdminHeroHeader(
          title: 'Delivery pricing',
          subtitle: _surgeActiveNow
              ? 'Surge ON now · ${_ghanaTime ?? 'Ghana time'}'
              : 'Base rates · ${_ghanaTime ?? 'Ghana time (GMT)'}',
          assetPath: 'assets/branding/hero_delivery.png',
          trailing: _surgeActiveNow
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'SURGE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 16),
        _sectionTitle('Price per kilometre'),
        _field(
          controller: _rateCtrl,
          label: 'Rate (₵ / km)',
          hint: '4.00',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          suffix: '₵/km',
        ),
        Text(
          'Fees = distance (km) × this rate. If a delivery zone has a minimum fee (e.g. ₵8), short trips use that minimum instead of distance × rate.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
        ),
        const SizedBox(height: 20),
        _sectionTitle('Surge pricing'),
        SwitchListTile(
          value: _surgeEnabled,
          onChanged: (v) => setState(() => _surgeEnabled = v),
          title: const Text(
            'Enable surge window',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            'Multiply delivery fee during peak hours (Ghana time)',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
          ),
          activeThumbColor: BytzGoTheme.accent,
          tileColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        const SizedBox(height: 10),
        _field(
          controller: _multCtrl,
          label: 'Surge multiplier',
          hint: '1.50',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          suffix: '×',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _field(
                controller: _startCtrl,
                label: 'Start time',
                hint: '17:00',
                keyboard: TextInputType.datetime,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                controller: _endCtrl,
                label: 'End time',
                hint: '21:00',
                keyboard: TextInputType.datetime,
              ),
            ),
          ],
        ),
        Text(
          'Overnight windows supported (e.g. 22:00 → 06:00). Times are Ghana (GMT), no daylight saving.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
        ),
        if (_surgeEnabled && _surgeActiveNow) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bolt, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Surge is active right now. Customers see ${formatCedis(double.tryParse(_rateCtrl.text) ?? 4)} × ${_multCtrl.text} per km.',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: BytzGoTheme.accent,
            foregroundColor: BytzGoTheme.sheetText,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(
            _saving ? 'Saving…' : 'Save pricing',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t.toUpperCase(),
          style: const TextStyle(
            color: BytzGoTheme.accent,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboard,
    String? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixText: suffix,
          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
          filled: true,
          fillColor: const Color(0xFF1E293B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
