/// Resolves Supabase storage object keys to public CDN URLs for image widgets.
class ClientImageUrl {
  /// Fallback when `/api/health` is unreachable (matches production Supabase bucket).
  static const defaultPublicBase =
      'https://ypmiurbtmfiyzmrygonh.supabase.co/storage/v1/object/public/pictures';

  static String? _publicBase;

  static void setPublicBase(String? base) {
    final b = base?.trim();
    _publicBase = b != null && b.isNotEmpty ? b.replaceAll(RegExp(r'/$'), '') : null;
  }

  static String? get publicBase => _publicBase ?? defaultPublicBase;

  /// Load `media.publicBaseUrl` from `/api/health` (safe to call without auth).
  static Future<void> loadFromHealth(Map<String, dynamic>? healthJson) async {
    final media = healthJson?['media'];
    if (media is Map) {
      setPublicBase(media['publicBaseUrl']?.toString());
    }
  }

  /// Turn stored refs into something [NetworkImage] / [CachedNetworkImage] can load.
  static String? resolve(String? url) {
    if (url == null) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('data:')) {
      return trimmed;
    }
    final pathOnly = trimmed.split('?').first;
    if (_isObjectKey(pathOnly)) {
      return '${publicBase}/$pathOnly';
    }
    return trimmed;
  }

  static bool _isObjectKey(String value) {
    return RegExp(r'^(avatars|products|covers|stories|rider-documents)/').hasMatch(value);
  }
}
