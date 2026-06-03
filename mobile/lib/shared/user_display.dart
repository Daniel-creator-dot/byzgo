import '../models/auth_user.dart';
import 'display_name.dart';

String userFirstName(AuthUser user) {
  final friendly = displayPersonName(user.name, role: user.role.name, fallback: '');
  if (friendly.isEmpty) return 'there';
  final parts = friendly.split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return 'there';
  final first = parts.first;
  if (first == 'Your' || first == 'BytzGo') return 'there';
  return first;
}

String userInitials(AuthUser user) {
  final parts = user.name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
}
