/// Display names for chat, notifications, and profile chips.
String displayPersonName(
  String? raw, {
  String? role,
  String fallback = 'Trip contact',
}) {
  var name = (raw ?? '').trim();
  final looksPlaceholder = name.isEmpty ||
      name.contains(r'$') ||
      RegExp(r'^(user|sender|test|guest)\d*$', caseSensitive: false).hasMatch(name) ||
      RegExp(r'^user[a-f0-9]{6,}$', caseSensitive: false).hasMatch(name);

  if (looksPlaceholder) {
    switch (role) {
      case 'rider':
        return 'Your biker';
      case 'customer':
        return 'Customer';
      case 'admin':
        return 'BytzGo Support';
      case 'vendor':
        return 'Shop partner';
      default:
        return fallback;
    }
  }

  if (name.contains('@')) {
    name = name
        .split('@')
        .first
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .trim();
    if (name.isEmpty ||
        RegExp(r'^(user|sender)\d*$', caseSensitive: false).hasMatch(name)) {
      return role == 'rider' ? 'Your biker' : fallback;
    }
  }

  return name
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) {
        if (w.length == 1) return w.toUpperCase();
        return '${w[0].toUpperCase()}${w.substring(1)}';
      })
      .join(' ');
}
