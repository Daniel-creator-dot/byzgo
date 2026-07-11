import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/location_service.dart';
import '../../core/maps_runtime_config.dart';
import '../../core/places_service.dart';
import '../../core/session.dart';
import '../../models/auth_user.dart';
import '../../models/location_point.dart';
import '../../shared/ghana_location.dart';
import '../../shared/ghana_regions.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/location_autocomplete_field.dart';
import '../auth/auth_repository.dart';

/// Vendor store contact + Google map pin (saved to profile lat/lng).
class VendorStoreProfileEditor extends StatefulWidget {
  const VendorStoreProfileEditor({
    super.key,
    required this.user,
    this.onSaved,
  });

  final AuthUser user;
  final ValueChanged<String>? onSaved;

  @override
  State<VendorStoreProfileEditor> createState() => _VendorStoreProfileEditorState();
}

class _VendorStoreProfileEditorState extends State<VendorStoreProfileEditor> {
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  String? _region;
  double? _lat;
  double? _lng;
  bool _saving = false;
  bool _locating = false;
  bool _resolving = false;
  String? _error;
  String? _success;

  InputDecoration get _fieldDecoration => InputDecoration(
        filled: true,
        fillColor: const Color(0xFF0F172A),
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
        prefixIconColor: Colors.white54,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1E293B)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1E293B)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BytzGoTheme.accent),
        ),
      );

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _phoneCtrl = TextEditingController(text: user.phone ?? '');
    _addressCtrl = TextEditingController(text: user.address ?? '');
    _region = user.region;
    _lat = user.lat;
    _lng = user.lng;
    if ((_lat == null || _lng == null || _lat == 0 || _lng == 0) &&
        isInGhanaBounds(ghanaCenterLat, ghanaCenterLng)) {
      _lat ??= ghanaCenterLat;
      _lng ??= ghanaCenterLng;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MapsRuntimeConfig>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyPoint(LocationPoint point) async {
    setState(() {
      _lat = point.lat;
      _lng = point.lng;
      _addressCtrl.text = point.address;
      _resolving = false;
    });
  }

  Future<void> _resolvePin(double lat, double lng) async {
    setState(() {
      _lat = lat;
      _lng = lng;
      _resolving = true;
      _addressCtrl.text = 'Finding address…';
    });
    try {
      final label = await context.read<PlacesService>().resolveAddressLabel(
            lat,
            lng,
            existing: widget.user.address,
          );
      if (!mounted) return;
      setState(() {
        _addressCtrl.text = label;
        _resolving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _addressCtrl.text = formatCoordAddress(lat, lng);
        _resolving = false;
      });
    }
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final loc = await context.read<LocationService>().getCurrentLocation();
      if (loc == null) {
        setState(() => _error = 'Turn on location or search your address below.');
        return;
      }
      await _resolvePin(loc.lat, loc.lng);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    final phone = _phoneCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Add a shop phone number so customers can call you.');
      return;
    }
    if (address.isEmpty || _lat == null || _lng == null) {
      setState(() => _error = 'Search your address and pin your location on the map.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      final result = await context.read<AuthRepository>().updateProfile(
            phone: phone,
            address: address,
            lat: _lat,
            lng: _lng,
            region: _region,
          );
      if (!mounted) return;
      await context.read<Session>().setSession(
            token: result.token,
            user: result.user,
          );
      setState(() => _success = 'Contact & location saved — customers can call and find you.');
      widget.onSaved?.call(_success!);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AuthRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lat = _lat;
    final lng = _lng;
    final hasPin = lat != null && lng != null && lat != 0 && lng != 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'CONTACT & LOCATION',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Customers call your shop phone and see you on the map. Pin your exact Google location.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration.copyWith(
            labelText: 'Shop phone (customers can call)',
            prefixIcon: const Icon(Icons.phone_outlined),
            hintText: 'e.g. 0247904675',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _region != null && ghanaRegions.contains(_region) ? _region : null,
          dropdownColor: const Color(0xFF0F172A),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          decoration: _fieldDecoration.copyWith(
            labelText: 'Operating region',
            prefixIcon: const Icon(Icons.map_outlined),
          ),
          items: ghanaRegions
              .map(
                (r) => DropdownMenuItem(
                  value: r,
                  child: Text(r),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _region = v),
        ),
        const SizedBox(height: 12),
        LocationAutocompleteField(
          icon: const Icon(Icons.location_on_outlined, color: Colors.white54),
          hint: 'Search pharmacy address in Ghana',
          controller: _addressCtrl,
          locating: _locating,
          resolving: _resolving,
          showUseMyLocation: true,
          onUseMyLocation: _useMyLocation,
          onLocation: _applyPoint,
          onAddressEdited: (_) {},
        ),
        const SizedBox(height: 12),
        Text(
          'PIN ON MAP — tap to adjust',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 180,
            child: hasPin
                ? GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(lat!, lng!),
                      zoom: 16,
                    ),
                    markers: {
                      Marker(
                        markerId: const MarkerId('store'),
                        position: LatLng(lat, lng),
                      ),
                    },
                    onTap: (pos) => _resolvePin(pos.latitude, pos.longitude),
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: true,
                    mapToolbarEnabled: false,
                  )
                : Container(
                    color: const Color(0xFF0F172A),
                    alignment: Alignment.center,
                    child: Text(
                      'Search an address above to place your pin',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
          ),
        ),
        if (hasPin) ...[
          const SizedBox(height: 8),
          Text(
            '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: BytzGoTheme.danger, fontSize: 12)),
        ],
        if (_success != null) ...[
          const SizedBox(height: 10),
          Text(_success!, style: const TextStyle(color: BytzGoTheme.accent, fontSize: 12)),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving…' : 'Save contact & location'),
          style: FilledButton.styleFrom(
            backgroundColor: BytzGoTheme.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }
}
