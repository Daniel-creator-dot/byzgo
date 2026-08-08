import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../models/auth_user.dart';
import '../../models/rider_document.dart';
import '../../shared/data_url_image.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/ride_ui.dart';
import 'rider_documents_repository.dart';

const _docSlots = [
  ('license', 'Driver licence', Icons.badge_outlined),
  ('ghana_card', 'Ghana card', Icons.credit_card),
  ('photo', 'Profile photo', Icons.face),
];

/// Upload licence, Ghana card, and profile photo for admin approval.
class RiderVerificationSection extends StatefulWidget {
  const RiderVerificationSection({super.key, required this.user});

  final AuthUser user;

  @override
  State<RiderVerificationSection> createState() => _RiderVerificationSectionState();
}

class _RiderVerificationSectionState extends State<RiderVerificationSection> {
  final _picker = ImagePicker();
  List<RiderDocument> _documents = [];
  bool _loading = true;
  String? _uploadingType;
  bool _submitting = false;
  String? _error;

  bool get _docsComplete =>
      _docSlots.every((s) => _documents.any((d) => d.docType == s.$1));

  bool get _canSubmit =>
      _docsComplete &&
      (widget.user.status == 'pending' || widget.user.status == 'rejected');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RiderVerificationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.status != widget.user.status) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<RiderDocumentsRepository>();
      final state = await repo.fetchDocuments();
      if (!mounted) return;
      setState(() => _documents = state.documents);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = RiderDocumentsRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseSourceAndUpload(String docType) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const Text(
                'Add photo',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Use a clear photo of the document. Camera or gallery works.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined, color: BytzGoTheme.accent),
                title: const Text('Take photo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: BytzGoTheme.accent),
                title: const Text('Choose from gallery', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    await _pickAndUpload(docType, source);
  }

  Future<void> _pickAndUpload(String docType, ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
      requestFullMetadata: false,
    );
    if (picked == null || !mounted) return;

    final path = picked.path.toLowerCase();
    final name = picked.name.toLowerCase();
    final okExt = path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.webp') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp');
    // Camera captures on Android often have no extension — still allow upload.
    if (!okExt && source == ImageSource.gallery && path.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a JPG, PNG, or WEBP image')),
      );
      return;
    }

    setState(() => _uploadingType = docType);
    try {
      final repo = context.read<RiderDocumentsRepository>();
      final result = await repo.uploadDocument(docType: docType, filePath: picked.path);
      if (!mounted) return;
      await context.read<Session>().applyAuthResult(token: result.token, user: result.user);
      setState(() {
        _documents = _documents.where((d) => d.docType != docType).toList();
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo uploaded')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(RiderDocumentsRepository.errorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _uploadingType = null);
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final repo = context.read<RiderDocumentsRepository>();
      final result = await repo.submitForReview();
      if (!mounted) return;
      await context.read<Session>().applyAuthResult(token: result.token, user: result.user);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submitted for admin review')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(RiderDocumentsRepository.errorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _preview(String? url, String label) {
    if (url == null || url.trim().isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0B1220),
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.65,
              ),
              child: InteractiveViewer(child: dataUrlImage(url, fit: BoxFit.contain)),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'approved':
        return BytzGoTheme.accent;
      case 'rejected':
        return Colors.redAccent;
      default:
        return Colors.orangeAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Verification documents',
            style: BytzGoTheme.sheetTitle().copyWith(fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            'Upload clear photos of your licence, Ghana card, and your face. Tap a card to take a photo or pick from gallery. Admin must approve before you can go online.',
            style: BytzGoTheme.sheetBody().copyWith(fontSize: 11),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))
          else
            ..._docSlots.map((slot) {
              final type = slot.$1;
              final label = slot.$2;
              final icon = slot.$3;
              RiderDocument? doc;
              for (final d in _documents) {
                if (d.docType == type) {
                  doc = d;
                  break;
                }
              }
              final busy = _uploadingType == type;
              final status = doc?.reviewStatus ?? (doc != null ? 'pending' : null);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: busy || _uploadingType != null
                        ? null
                        : () => _chooseSourceAndUpload(type),
                    onLongPress:
                        doc != null ? () => _preview(doc!.imageUrl, label) : null,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 84,
                              height: 84,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (doc != null)
                                    dataUrlImage(doc.imageUrl, height: 84, width: 84)
                                  else
                                    ColoredBox(
                                      color: const Color(0xFF0F172A),
                                      child: Icon(icon, color: const Color(0xFF64748B), size: 32),
                                    ),
                                  if (busy)
                                    const ColoredBox(
                                      color: Color(0x990F172A),
                                      child: Center(
                                        child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      ),
                                    ),
                                  if (doc == null && !busy)
                                    const ColoredBox(
                                      color: Color(0x660F172A),
                                      child: Center(
                                        child: Icon(Icons.add_a_photo_outlined,
                                            color: Colors.white70, size: 28),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  busy
                                      ? 'Uploading…'
                                      : doc == null
                                          ? 'Tap to take photo or choose from gallery'
                                          : 'Tap to replace · long-press to preview',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 11,
                                  ),
                                ),
                                if (status != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _statusColor(status).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _statusColor(status).withValues(alpha: 0.45),
                                      ),
                                    ),
                                    child: Text(
                                      status.toUpperCase(),
                                      style: TextStyle(
                                        color: _statusColor(status),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                                if (doc?.reviewStatus == 'rejected' &&
                                    (doc?.rejectionReason?.isNotEmpty ?? false))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      doc!.rejectionReason!,
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          if (_canSubmit) ...[
            const SizedBox(height: 4),
            RidePrimaryButton(
              label: _submitting ? 'Submitting…' : 'Submit for admin review',
              onPressed: _submitting ? null : _submit,
            ),
          ],
          if (widget.user.status == 'active' && _docsComplete)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Verified — you can go online from Drive.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: BytzGoTheme.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
