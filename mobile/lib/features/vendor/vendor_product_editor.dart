import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../shared/data_url_image.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import 'vendor_repository.dart';

/// Add or edit a menu item with photo upload.
Future<bool?> showVendorProductEditor(
  BuildContext context, {
  Product? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _VendorProductEditorSheet(existing: existing),
  );
}

class _VendorProductEditorSheet extends StatefulWidget {
  const _VendorProductEditorSheet({this.existing});

  final Product? existing;

  @override
  State<_VendorProductEditorSheet> createState() =>
      _VendorProductEditorSheetState();
}

class _VendorProductEditorSheetState extends State<_VendorProductEditorSheet> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _picker = ImagePicker();

  String _category = 'Pharmacy';
  String? _imageUrl;
  String? _localImagePath;
  bool _uploading = false;
  bool _saving = false;
  String? _error;

  static const _categories = [
    'Pharmacy',
    'Analgesics',
    'Antibiotics',
    'Antacids',
    'Vitamins',
    'Food',
    'Drinks',
    'Grocery',
    'Other',
  ];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    if (p != null) {
      _name.text = p.name;
      _description.text = p.description ?? '';
      _price.text = p.price.toStringAsFixed(2);
      _category = p.category ?? 'Pharmacy';
      _imageUrl = p.imageUrl;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (file == null) return;
      setState(() {
        _localImagePath = file.path;
        _uploading = true;
        _error = null;
      });
      final url = await context.read<VendorRepository>().uploadImage(file.path);
      if (!mounted) return;
      setState(() {
        _imageUrl = url;
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = VendorRepository.errorMessage(e);
      });
    }
  }

  Future<void> _delete() async {
    final p = widget.existing;
    if (p == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Remove item?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "${p.name}" from your menu?',
          style: const TextStyle(color: Colors.white70),
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
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<VendorRepository>().deleteProduct(p.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = VendorRepository.errorMessage(e);
      });
    }
  }

  Future<void> _save() async {
    final price = double.tryParse(_price.text.replaceAll(',', '').trim());
    if (_name.text.trim().isEmpty || price == null || price <= 0) {
      setState(() => _error = 'Name and a valid price are required');
      return;
    }
    if (_imageUrl == null || _imageUrl!.isEmpty) {
      setState(() => _error = 'Add a product photo');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = context.read<VendorRepository>();
      if (_isEdit) {
        await repo.updateProduct(
          productId: widget.existing!.id,
          name: _name.text.trim(),
          description: _description.text.trim(),
          price: price,
          category: _category,
          imageUrl: _imageUrl!,
        );
      } else {
        await repo.createProduct(
          name: _name.text.trim(),
          description: _description.text.trim(),
          price: price,
          category: _category,
          imageUrl: _imageUrl!,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = VendorRepository.errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF0B1220),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEdit ? 'Edit menu item' : 'Add menu item',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white54),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 160,
                        width: double.infinity,
                        child: _localImagePath != null && _uploading
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    File(_localImagePath!),
                                    fit: BoxFit.cover,
                                  ),
                                  const ColoredBox(
                                    color: Color(0x88000000),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: BytzGoTheme.accent,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : dataUrlImage(_imageUrl, height: 160),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _uploading
                                ? null
                                : () => _pickImage(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_outlined, size: 18),
                            label: const Text('Camera'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _uploading
                                ? null
                                : () => _pickImage(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined, size: 18),
                            label: const Text('Gallery'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _field(_name, 'Item name'),
                    _field(_description, 'Description (optional)', maxLines: 2),
                    _field(_price, 'Price (₵)', keyboard: TextInputType.number),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _categories.contains(_category) ? _category : 'Pharmacy',
                      dropdownColor: const Color(0xFF0F172A),
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDeco('Category'),
                      items: _categories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => _category = v ?? 'Pharmacy'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'New items need admin approval before customers see them in Shops.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    ],
                    const SizedBox(height: 14),
                    if (_isEdit) ...[
                      OutlinedButton.icon(
                        onPressed: _saving || _uploading ? null : _delete,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remove from menu'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    FilledButton(
                      onPressed: _saving || _uploading ? null : _save,
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
                          : Text(_isEdit ? 'Save changes' : 'Add to menu'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1E293B)),
        ),
      );

  Widget _field(
    TextEditingController ctrl,
    String label, {
    int maxLines = 1,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.white),
        decoration: _inputDeco(label),
      ),
    );
  }
}
