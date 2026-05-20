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

/// Upload licence, Ghana card, and JPEG photo for admin approval.
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

  Future<void> _pickAndUpload(String docType) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1920,
    );
    if (picked == null || !mounted) return;

    final path = picked.path.toLowerCase();
    if (!path.endsWith('.jpg') && !path.endsWith('.jpeg')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a JPEG image (.jpg)')),
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
        const SnackBar(content: Text('Document uploaded')),
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
            'Upload JPEG photos of your licence, Ghana card, and a clear profile picture. Admin must approve before you can go online.',
            style: BytzGoTheme.sheetBody().copyWith(fontSize: 11),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(strokeWidth: 2),
            ))
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
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: doc != null
                            ? dataUrlImage(doc.imageUrl, height: 64)
                            : ColoredBox(
                                color: const Color(0xFF1E293B),
                                child: Icon(icon, color: const Color(0xFF64748B)),
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
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          if (doc?.reviewStatus == 'rejected' &&
                              (doc?.rejectionReason?.isNotEmpty ?? false))
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                doc!.rejectionReason!,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: busy || _uploadingType != null
                                ? null
                                : () => _pickAndUpload(type),
                            icon: busy
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.upload, size: 16),
                            label: Text(
                              busy ? 'Uploading…' : (doc != null ? 'Replace' : 'Upload JPEG'),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Color(0xFF334155)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
