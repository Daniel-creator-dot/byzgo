import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

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

Widget dataUrlImage(String? dataUrl, {double? height, BoxFit fit = BoxFit.cover}) {
  final bytes = decodeDataUrlImage(dataUrl);
  if (bytes == null) {
    return Container(
      height: height,
      color: const Color(0xFF1E293B),
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported, color: Color(0xFF64748B)),
    );
  }
  return Image.memory(bytes, height: height, fit: fit, width: double.infinity);
}
