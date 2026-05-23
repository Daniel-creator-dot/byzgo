import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/vendor_shop_promo.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/app_network_image.dart';
import 'vendor_repository.dart';

/// Vendor controls Shop Drops (flyer stories) + status + discount for customers.
class VendorShopPromoEditor extends StatefulWidget {
  const VendorShopPromoEditor({super.key});

  @override
  State<VendorShopPromoEditor> createState() => _VendorShopPromoEditorState();
}

class _VendorShopPromoEditorState extends State<VendorShopPromoEditor> {
  bool _loading = true;
  bool _saving = false;
  bool _uploadingFlyer = false;
  String? _msg;
  String _openStatus = 'open';
  String? _pendingFlyerUrl;
  String? _currentFlyerUrl;
  bool _clearStoryOnSave = false;
  final _statusMsgCtrl = TextEditingController();
  final _discountLabelCtrl = TextEditingController();
  final _discountPctCtrl = TextEditingController();
  final _picker = ImagePicker();

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
    _currentFlyerUrl = promo.shopStoryImage;
    _pendingFlyerUrl = null;
    _clearStoryOnSave = false;
    _statusMsgCtrl.text = promo.shopStatusMessage ?? '';
    _discountLabelCtrl.text = promo.shopDiscountLabel ?? '';
    _discountPctCtrl.text = promo.shopDiscountPercent != null
        ? promo.shopDiscountPercent!.toStringAsFixed(
            promo.shopDiscountPercent! % 1 == 0 ? 0 : 1,
          )
        : '';
  }

  String? get _previewFlyer => _pendingFlyerUrl ?? _currentFlyerUrl;

  Future<void> _pickFlyer() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1920,
      imageQuality: 88,
    );
    if (file == null || !mounted) return;
    setState(() {
      _uploadingFlyer = true;
      _msg = null;
    });
    try {
      final url = await context.read<VendorRepository>().uploadShopStoryFlyer(file.path);
      if (!mounted) return;
      setState(() {
        _pendingFlyerUrl = url;
        _clearStoryOnSave = false;
        _uploadingFlyer = false;
        _msg = 'Flyer ready — tap Publish to go live for 24h';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingFlyer = false;
        _msg = VendorRepository.errorMessage(e);
      });
    }
  }

  Future<void> _removeFlyer() async {
    setState(() {
      if (_currentFlyerUrl != null || _pendingFlyerUrl != null) {
        _clearStoryOnSave = true;
      }
      _pendingFlyerUrl = null;
      _currentFlyerUrl = null;
    });
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
      final repo = context.read<VendorRepository>();
      final promo = await repo.updateShopPromo(
        shopOpenStatus: _openStatus,
        shopStatusMessage: _statusMsgCtrl.text.trim(),
        shopDiscountLabel: _discountLabelCtrl.text.trim(),
        shopDiscountPercent: pct,
        shopStoryImage: _pendingFlyerUrl,
        clearStatusMessage: _statusMsgCtrl.text.trim().isEmpty,
        clearDiscountLabel: _discountLabelCtrl.text.trim().isEmpty,
        clearDiscountPercent: pctText.isEmpty,
        clearShopStory: _clearStoryOnSave && _previewFlyer == null,
      );
      if (!mounted) return;
      _applyPromo(promo);
      setState(() {
        _saving = false;
        _msg = 'Shop Drop is live — customers see your ring on Shops';
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
              Icon(Icons.auto_awesome, color: BytzGoTheme.accent, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Shop Drop',
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
            'Post a flyer like WhatsApp status. Customers tap your glowing ring on Shops to watch, then order.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11),
          ),
          const SizedBox(height: 14),
          AspectRatio(
            aspectRatio: 9 / 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                color: const Color(0xFF1E293B),
                child: _previewFlyer != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          AppNetworkImage(
                            url: _previewFlyer!,
                            fit: BoxFit.cover,
                            semanticLabel: 'Shop drop preview',
                          ),
                          if (_uploadingFlyer)
                            const ColoredBox(
                              color: Colors.black54,
                              child: Center(
                                child: CircularProgressIndicator(color: BytzGoTheme.accent),
                              ),
                            ),
                        ],
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 48,
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Portrait flyer works best',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _uploadingFlyer ? null : _pickFlyer,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(_previewFlyer == null ? 'Upload flyer' : 'Change flyer'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BytzGoTheme.accent,
                    side: const BorderSide(color: Color(0xFF334155)),
                  ),
                ),
              ),
              if (_previewFlyer != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _removeFlyer,
                  icon: const Icon(Icons.delete_outline, color: BytzGoTheme.danger),
                  tooltip: 'Remove flyer',
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'CAPTION & OFFERS',
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
          const SizedBox(height: 10),
          TextField(
            controller: _statusMsgCtrl,
            maxLength: 160,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Caption on the story',
              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              hintText: 'e.g. Weekend promo — free delivery over ₵100',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
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
                color: _msg!.contains('live') || _msg!.contains('ready')
                    ? const Color(0xFF4ADE80)
                    : BytzGoTheme.danger,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: (_saving || _uploadingFlyer) ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.bolt),
            label: Text(_saving ? 'Publishing…' : 'Publish Shop Drop'),
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
