import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/delivery_pricing_config.dart';
import '../../models/admin_pricing_settings.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import 'admin_repository.dart';
import 'admin_zones_tab.dart';
import 'widgets/admin_hero_header.dart';

/// Admin delivery pricing: global rate, min/max, surge, and regional zones.
class AdminPricingTab extends StatefulWidget {
  const AdminPricingTab({super.key});

  @override
  State<AdminPricingTab> createState() => _AdminPricingTabState();
}

class _AdminPricingTabState extends State<AdminPricingTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  final _rateCtrl = TextEditingController();
  final _minFeeCtrl = TextEditingController();
  final _maxFeeCtrl = TextEditingController();
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
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _rateCtrl.dispose();
    _minFeeCtrl.dispose();
    _maxFeeCtrl.dispose();
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
        _minFeeCtrl.text = s.deliveryMinFee;
        _maxFeeCtrl.text = s.deliveryMaxFee;
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
    final minRaw = _minFeeCtrl.text.trim();
    if (minRaw.isNotEmpty) {
      final min = double.tryParse(minRaw);
      if (min == null || min <= 0) {
        _snack('Global minimum must be a positive number or empty');
        return;
      }
    }
    final maxRaw = _maxFeeCtrl.text.trim();
    if (maxRaw.isNotEmpty) {
      final max = double.tryParse(maxRaw);
      if (max == null || max <= 0) {
        _snack('Global maximum must be a positive number or empty');
        return;
      }
      if (minRaw.isNotEmpty && max < (double.tryParse(minRaw) ?? 0)) {
        _snack('Global maximum must be ≥ minimum');
        return;
      }
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
        deliveryMinFee: minRaw,
        deliveryMaxFee: maxRaw,
        surgeEnabled: _surgeEnabled,
        surgeMultiplier: mult,
        surgeStartTime: _startCtrl.text.trim(),
        surgeEndTime: _endCtrl.text.trim(),
      );
      await context.read<AdminRepository>().savePricingSettings(body);
      await context.read<DeliveryPricingConfig>().refresh();
      if (!mounted) return;
      _snack('Pricing saved — live on all apps', success: true);
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: AdminHeroHeader(
            title: 'Delivery pricing',
            subtitle: _surgeActiveNow
                ? 'Surge ON · ${_ghanaTime ?? 'Ghana time'}'
                : 'Rates & caps · ${_ghanaTime ?? 'Ghana (GMT)'}',
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
        ),
        TabBar(
          controller: _tabs,
          labelColor: BytzGoTheme.accent,
          unselectedLabelColor: Colors.white54,
          indicatorColor: BytzGoTheme.accent,
          tabs: const [
            Tab(text: 'GLOBAL RATE'),
            Tab(text: 'ZONE MIN/MAX'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _globalTab(),
              const AdminZonesTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _globalTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _sectionTitle('Rate per kilometre'),
        _field(
          controller: _rateCtrl,
          label: 'Price (₵ / km)',
          hint: '4.00',
          suffix: '₵/km',
        ),
        Text(
          'All trips: fee = distance (km) × this rate, then min/max caps apply.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
        ),
        const SizedBox(height: 16),
        _sectionTitle('Global fee limits'),
        Row(
          children: [
            Expanded(
              child: _field(
                controller: _minFeeCtrl,
                label: 'Minimum fee (₵)',
                hint: 'Optional',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                controller: _maxFeeCtrl,
                label: 'Maximum fee (₵)',
                hint: 'Optional',
              ),
            ),
          ],
        ),
        Text(
          'Used when no regional zone matches, or as fallback. Leave empty for no cap.',
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
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                controller: _endCtrl,
                label: 'End time',
                hint: '21:00',
              ),
            ),
          ],
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
                    'Surge active: ${formatCedis(double.tryParse(_rateCtrl.text) ?? 4)} × ${_multCtrl.text} per km.',
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
            _saving ? 'Saving…' : 'Save global pricing',
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
    String? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
