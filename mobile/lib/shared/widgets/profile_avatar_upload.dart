import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../features/auth/auth_repository.dart';
import '../../models/auth_user.dart';
import '../theme.dart';
import 'user_avatar.dart';

/// Tap to pick a photo, upload via `/api/upload`, save on profile as `avatar_url`.
class ProfileAvatarUpload extends StatefulWidget {
  const ProfileAvatarUpload({
    super.key,
    required this.user,
    this.radius = 44,
    this.onUpdated,
    this.dark = false,
  });

  final AuthUser user;
  final double radius;
  final void Function(AuthUser user)? onUpdated;
  final bool dark;

  @override
  State<ProfileAvatarUpload> createState() => _ProfileAvatarUploadState();
}

class _ProfileAvatarUploadState extends State<ProfileAvatarUpload> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final auth = context.read<AuthRepository>();
      final url = await auth.uploadProfileImage(picked.path);
      final result = await auth.updateProfile(avatarUrl: url);
      if (!mounted) return;
      await context.read<Session>().setSession(
            token: result.token,
            user: result.user,
          );
      widget.onUpdated?.call(result.user);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated'),
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

    return Stack(
      alignment: Alignment.center,
      children: [
        UserAvatar(
          user: user,
          radius: widget.radius,
          backgroundColor: widget.dark
              ? const Color(0xFF1E293B)
              : BytzGoTheme.brandBlue.withValues(alpha: 0.15),
        ),
        if (_uploading)
          SizedBox(
            width: widget.radius * 2,
            height: widget.radius * 2,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Material(
            color: BytzGoTheme.brandBlue,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _uploading ? null : _pickAndUpload,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  _uploading ? Icons.hourglass_empty : Icons.camera_alt,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        if (!_uploading)
          Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _pickAndUpload,
              child: SizedBox(
                width: widget.radius * 2,
                height: widget.radius * 2,
              ),
            ),
          ),
      ],
    );
  }
}
