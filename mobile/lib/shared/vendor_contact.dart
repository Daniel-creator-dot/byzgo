import 'package:url_launcher/url_launcher.dart';

import '../models/vendor.dart';

/// Open vendor location in Google Maps (same pin customers/riders see).
Future<bool> openVendorInGoogleMaps(Vendor vendor) async {
  final lat = vendor.lat;
  final lng = vendor.lng;
  if (lat != null && lng != null) {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
  final q = Uri.encodeComponent(
    '${vendor.name} ${vendor.address ?? "Accra"}',
  );
  final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<bool> callVendorPhone(String? phone) async {
  if (phone == null || phone.trim().isEmpty) return false;
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 9) return false;
  final uri = Uri(scheme: 'tel', path: digits);
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

String formatVendorPhone(String? phone) {
  if (phone == null || phone.trim().isEmpty) return '';
  final d = phone.replaceAll(RegExp(r'\s+'), '');
  if (d.length == 10 && d.startsWith('0')) {
    return '${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6)}';
  }
  return d;
}
