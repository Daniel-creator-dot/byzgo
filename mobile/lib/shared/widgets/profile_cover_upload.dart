import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../features/auth/auth_repository.dart';
import '../../models/auth_user.dart';
import '../theme.dart';
import 'app_network_image.dart';

/// Shop cover for customer browse — upload via `/api/upload` + `cover_image` on profile.
class ProfileCoverUpload extends StatefulWidget {
  const ProfileCoverUpload({
    super.key,
    required this.user,
    this.height = 140,
    this.onUpdated,
  });

  final AuthUser user;
  final double height;
  final void Function(AuthUser user)? onUpdated;

  @override
  State<ProfileCoverUpload> createState() => _ProfileCoverUploadState();
}

class _ProfileCoverUploadState extends State<ProfileCoverUpload> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1200,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final auth = context.read<AuthRepository>();
      final url = await auth.uploadCoverImage(picked.path);
      final result = await auth.updateProfile(coverImage: url);
      if (!mounted) return;
      await context.read<Session>().setSession(
            token: result.token,
            user: result.user,
          );
      widget.onUpdated?.call(result.user);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shop cover updated'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AuthRepository.errorMessage(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user ?? widget.user;
    final cover = user.coverImage;

    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: double.infinity,
            height: widget.height,
            child: cover != null && cover.isNotEmpty
                ? AppNetworkImage(
                    url: cover,
                    width: double.infinity,
                    height: widget.height,
                    fit: BoxFit.cover,
                    semanticLabel: 'Shop cover',
                  )
                : Container(
                    color: const Color(0xFF1E293B),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.storefront_outlined,
                      size: 48,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
          ),
        ),
        if (_uploading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        Positioned(
          right: 12,
          bottom: 12,
          child: Material(
            color: BytzGoTheme.brandBlue,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _uploading ? null : _pickAndUpload,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.camera_alt, size: 20, color: Colors.white),
              ),
            ),
          ),
        ),
        if (!_uploading)
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _pickAndUpload,
              ),
            ),
          ),
      ],
    );
  }
}
