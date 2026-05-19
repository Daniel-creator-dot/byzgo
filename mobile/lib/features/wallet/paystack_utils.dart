import '../../models/auth_user.dart';

/// Paystack requires an email — same rules as web `paystackPaymentEmail`.
String paystackPaymentEmail(AuthUser user) {
  final email = user.email.trim();
  if (email.contains('@')) return email;
  final digits = user.phone?.replaceAll(RegExp(r'\D'), '') ?? '';
  if (digits.length >= 9) return 'user$digits@bytzgo.app';
  return 'user${user.id.replaceAll('-', '').substring(0, 12)}@bytzgo.app';
}

String? extractPaystackReference(Uri uri) {
  final ref = uri.queryParameters['reference']?.trim() ??
      uri.queryParameters['trxref']?.trim();
  if (ref != null && ref.isNotEmpty) return ref;
  return null;
}

bool isPaystackCallbackUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('reference=') ||
      lower.contains('trxref=') ||
      lower.contains('/paystack/callback');
}
