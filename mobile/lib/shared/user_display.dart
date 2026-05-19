import '../models/auth_user.dart';

String userFirstName(AuthUser user) {
  final parts = user.name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return 'there';
  return parts.first;
}

String userInitials(AuthUser user) {
  final parts = user.name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
}
