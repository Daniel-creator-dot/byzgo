import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../client_image_url.dart';
import '../data_url_image.dart' show decodeDataUrlImage;

/// Production image widget: HTTPS CDN URLs + legacy base64, with loading & error states.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.semanticLabel,
  });

  final String? url;
  final double? height;
  final double? width;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final trimmed = ClientImageUrl.resolve(url?.trim());
    if (trimmed == null || trimmed.isEmpty) {
      return _placeholder();
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final child = CachedNetworkImage(
        imageUrl: trimmed,
        height: height,
        width: width ?? double.infinity,
        fit: fit,
        memCacheWidth: width != null ? (width! * 2).round() : 800,
        placeholder: (_, __) => _loading(),
        errorWidget: (_, __, ___) => _placeholder(),
      );
      return _wrap(child);
    }

    final bytes = decodeDataUrlImage(trimmed);
    if (bytes != null) {
      return _wrap(
        Image.memory(
          bytes,
          height: height,
          width: width ?? double.infinity,
          fit: fit,
        ),
      );
    }
    return _placeholder();
  }

  Widget _wrap(Widget child) {
    if (borderRadius == null) return child;
    return ClipRRect(borderRadius: borderRadius!, child: child);
  }

  Widget _loading() {
    return Container(
      height: height,
      width: width,
      color: const Color(0xFF1E293B),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      height: height,
      width: width,
      color: const Color(0xFF1E293B),
      alignment: Alignment.center,
      child: Semantics(
        label: semanticLabel ?? 'Image unavailable',
        child: const Icon(Icons.image_not_supported, color: Color(0xFF64748B)),
      ),
    );
  }
}
