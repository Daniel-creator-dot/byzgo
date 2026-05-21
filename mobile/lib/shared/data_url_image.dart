import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'widgets/app_network_image.dart';

/// Decodes a `data:image/...;base64,...` URL for [Image.memory].
Uint8List? decodeDataUrlImage(String? dataUrl) {
  if (dataUrl == null || dataUrl.isEmpty) return null;
  final comma = dataUrl.indexOf(',');
  if (comma < 0) return null;
  try {
    return base64Decode(dataUrl.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

/// Displays Supabase/CDN https URLs or legacy inline base64 images.
Widget dataUrlImage(
  String? dataUrl, {
  double? height,
  double? width,
  BoxFit fit = BoxFit.cover,
  BorderRadius? borderRadius,
}) {
  return AppNetworkImage(
    url: dataUrl,
    height: height,
    width: width,
    fit: fit,
    borderRadius: borderRadius,
  );
}
