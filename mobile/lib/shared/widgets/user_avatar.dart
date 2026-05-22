import 'package:flutter/material.dart';

import '../../models/auth_user.dart';
import '../client_image_url.dart';
import '../data_url_image.dart';
import '../theme.dart';
import '../user_display.dart';

/// Profile photo from [AuthUser.avatarUrl] (data URL or https), else initials.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.radius = 44,
    this.backgroundColor,
  });

  final AuthUser user;
  final double radius;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final url = ClientImageUrl.resolve(user.avatarUrl);
    final bg = backgroundColor ?? BytzGoTheme.brandBlue.withValues(alpha: 0.15);

    ImageProvider? provider;
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('http://') || url.startsWith('https://')) {
        provider = NetworkImage(url);
      } else {
        final bytes = decodeDataUrlImage(url);
        if (bytes != null) {
          provider = MemoryImage(bytes);
        }
      }
    }

    if (provider != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        backgroundImage: provider,
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: Text(
        userInitials(user),
        style: TextStyle(
          fontSize: radius * 0.62,
          fontWeight: FontWeight.w900,
          color: BytzGoTheme.brandBlue,
        ),
      ),
    );
  }
}
