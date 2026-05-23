import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/vendor_shop_promo.dart';
import '../../shared/theme.dart';
import 'vendor_repository.dart';

/// Vendor controls what customers see on the Shops tab (status + discount).
class VendorShopPromoEditor extends StatefulWidget {
  const VendorShopPromoEditor({super.key});

  @override
  State<VendorShopPromoEditor> createState() => _VendorShopPromoEditorState();
}

class _VendorShopPromoEditorState extends State<VendorShopPromoEditor> {
  bool _loading = true;
  bool _saving = false;
  String? _msg;
  String _openStatus = 'open';
  final _statusMsgCtrl = TextEditingController();
  final _discountLabelCtrl = TextEditingController();
  final _discountPctCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _statusMsgCtrl.dispose();
    _discountLabelCtrl.dispose();
    _discountPctCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _msg = null;
    });
    try {
      final promo = await context.read<VendorRepository>().fetchShopPromo();
      if (!mounted) return;
      _applyPromo(promo);
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _msg = VendorRepository.errorMessage(e);
      });
    }
  }

  void _applyPromo(VendorShopPromo promo) {
    _openStatus = promo.shopOpenStatus;
    _statusMsgCtrl.text = promo.shopStatusMessage ?? '';
    _discountLabelCtrl.text = promo.shopDiscountLabel ?? '';
    _discountPctCtrl.text = promo.shopDiscountPercent != null
        ? promo.shopDiscountPercent!.toStringAsFixed(
            promo.shopDiscountPercent! % 1 == 0 ? 0 : 1,
          )
        : '';
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _msg = null;
    });
    try {
      final pctText = _discountPctCtrl.text.trim();
      double? pct;
      if (pctText.isNotEmpty) {
        pct = double.tryParse(pctText);
        if (pct == null || pct < 0 || pct > 100) {
          throw Exception('Discount percent must be between 0 and 100');
        }
      }
      final promo = await context.read<VendorRepository>().updateShopPromo(
            shopOpenStatus: _openStatus,
            shopStatusMessage: _statusMsgCtrl.text.trim(),
            shopDiscountLabel: _discountLabelCtrl.text.trim(),
            shopDiscountPercent: pct,
            clearStatusMessage: _statusMsgCtrl.text.trim().isEmpty,
            clearDiscountLabel: _discountLabelCtrl.text.trim().isEmpty,
            clearDiscountPercent: pctText.isEmpty,
          );
      if (!mounted) return;
      _applyPromo(promo);
      setState(() {
        _saving = false;
        _msg = 'Live for customers on the Shops tab';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = VendorRepository.errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: BytzGoTheme.accent)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.campaign_outlined, color: BytzGoTheme.accent, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Customer visibility',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Customers see a floating update on Shops when you post status or a discount.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11),
          ),
          const SizedBox(height: 14),
          Text(
            'STORE STATUS',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'open', label: Text('Open'), icon: Icon(Icons.check_circle_outline)),
              ButtonSegment(value: 'busy', label: Text('Busy'), icon: Icon(Icons.schedule)),
              ButtonSegment(value: 'closed', label: Text('Closed'), icon: Icon(Icons.block)),
            ],
            selected: {_openStatus},
            onSelectionChanged: (s) => setState(() => _openStatus = s.first),
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.black;
                return Colors.white70;
              }),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return BytzGoTheme.accent;
                return const Color(0xFF1E293B);
              }),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _statusMsgCtrl,
            maxLength: 160,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Status message (optional)',
              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              hintText: 'e.g. Fresh jollof today · closes 9pm',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'DISCOUNT',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _discountLabelCtrl,
            maxLength: 80,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Discount headline',
              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              hintText: 'e.g. 15% off all orders today',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _discountPctCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Discount % (optional)',
              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5),
              ),
              suffixText: '%',
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (_msg != null) ...[
            const SizedBox(height: 10),
            Text(
              _msg!,
              style: TextStyle(
                color: _msg!.startsWith('Live')
                    ? const Color(0xFF4ADE80)
                    : BytzGoTheme.danger,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.publish_outlined),
            label: Text(_saving ? 'Publishing…' : 'Publish to customers'),
            style: FilledButton.styleFrom(
              backgroundColor: BytzGoTheme.accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
