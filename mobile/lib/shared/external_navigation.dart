import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/location_point.dart';
import '../models/vendor.dart';
import 'rider_trip.dart';
import 'vendor_contact.dart';

/// Apple Maps turn-by-turn URL (opens the native Maps app on iOS).
String appleMapsNavUrl(double destLat, double destLng, {LocationPoint? origin}) {
  final params = <String, String>{
    'daddr': '$destLat,$destLng',
    'dirflg': 'd',
  };
  if (origin != null && hasValidCoords(origin.lat, origin.lng)) {
    params['saddr'] = '${origin.lat},${origin.lng}';
  }
  return Uri(
    scheme: 'https',
    host: 'maps.apple.com',
    queryParameters: params,
  ).toString();
}

String appleMapsSearchUrl(String query) {
  return Uri(
    scheme: 'https',
    host: 'maps.apple.com',
    queryParameters: {'q': query},
  ).toString();
}

Future<bool> openAppleMapsNavigation(
  TripStop target, {
  LocationPoint? origin,
}) async {
  final url = hasValidCoords(target.lat, target.lng)
      ? appleMapsNavUrl(target.lat, target.lng, origin: origin)
      : appleMapsSearchUrl(target.label);
  return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

Future<bool> openVendorInAppleMaps(Vendor vendor) async {
  final lat = vendor.lat;
  final lng = vendor.lng;
  if (lat != null && lng != null && hasValidCoords(lat, lng)) {
    return launchUrl(
      Uri.parse(appleMapsNavUrl(lat, lng)),
      mode: LaunchMode.externalApplication,
    );
  }
  final q = '${vendor.name} ${vendor.address ?? "Accra"}'.trim();
  return launchUrl(
    Uri.parse(appleMapsSearchUrl(q)),
    mode: LaunchMode.externalApplication,
  );
}

/// On iOS, let the rider choose Apple Maps or Google Maps (App Store Guideline 4).
Future<bool> showExternalNavigationPicker(
  BuildContext context,
  TripStop target, {
  LocationPoint? origin,
}) async {
  if (!Platform.isIOS) {
    return openTurnByTurnNavigation(target, origin: origin);
  }

  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Open directions',
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              target.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Apple Maps'),
              subtitle: const Text('Recommended on iPhone & iPad'),
              onTap: () => Navigator.pop(ctx, 'apple'),
            ),
            ListTile(
              leading: const Icon(Icons.navigation_outlined),
              title: const Text('Google Maps'),
              onTap: () => Navigator.pop(ctx, 'google'),
            ),
          ],
        ),
      ),
    ),
  );

  switch (choice) {
    case 'apple':
      return openAppleMapsNavigation(target, origin: origin);
    case 'google':
      return openTurnByTurnNavigation(target, origin: origin);
    default:
      return false;
  }
}

Future<void> showVendorMapPicker(BuildContext context, Vendor vendor) async {
  if (!Platform.isIOS) {
    await openVendorInGoogleMaps(vendor);
    return;
  }

  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Open location',
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Apple Maps'),
              onTap: () => Navigator.pop(ctx, 'apple'),
            ),
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: const Text('Google Maps'),
              onTap: () => Navigator.pop(ctx, 'google'),
            ),
          ],
        ),
      ),
    ),
  );

  switch (choice) {
    case 'apple':
      await openVendorInAppleMaps(vendor);
    case 'google':
      await openVendorInGoogleMaps(vendor);
  }
}
