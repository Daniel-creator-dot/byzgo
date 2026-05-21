import 'package:flutter/material.dart';

import '../data_url_image.dart';
import '../theme.dart';
/// Avatar for trip contacts (customer/rider) from order fields.
class ContactAvatar extends StatelessWidget {
  const ContactAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.radius = 22,
    this.backgroundColor,
  });

  final String name;
  final String? avatarUrl;
  final double radius;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? BytzGoTheme.brandBlue.withValues(alpha: 0.15);
    final url = avatarUrl?.trim();
    ImageProvider? provider;
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('http://') || url.startsWith('https://')) {
        provider = NetworkImage(url);
      } else {
        final bytes = decodeDataUrlImage(url);
        if (bytes != null) provider = MemoryImage(bytes);
      }
    }

    if (provider != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        backgroundImage: provider,
      );
    }

    final initials = name.trim().isEmpty
        ? '?'
        : userInitialsFromParts(name.trim().split(RegExp(r'\s+')));
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: radius * 0.58,
          fontWeight: FontWeight.w900,
          color: BytzGoTheme.brandBlue,
        ),
      ),
    );
  }
}

String userInitialsFromParts(List<String> parts) {
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final p = parts[0];
    return p.length >= 2 ? p.substring(0, 2).toUpperCase() : p.toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
