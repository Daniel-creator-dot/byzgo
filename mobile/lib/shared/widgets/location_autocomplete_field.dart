import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/places_service.dart';
import '../../models/location_point.dart';
import '../theme.dart';

/// Address field with Ghana Places autocomplete (via backend).
class LocationAutocompleteField extends StatefulWidget {
  const LocationAutocompleteField({
    super.key,
    required this.icon,
    required this.hint,
    required this.controller,
    required this.onLocation,
    this.onAddressEdited,
    this.onTap,
    this.showUseMyLocation = false,
    this.onUseMyLocation,
    this.locating = false,
    this.resolving = false,
  });

  final Widget icon;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<LocationPoint> onLocation;
  final ValueChanged<String>? onAddressEdited;
  final VoidCallback? onTap;
  final bool showUseMyLocation;
  final Future<void> Function()? onUseMyLocation;
  final bool locating;
  final bool resolving;

  @override
  State<LocationAutocompleteField> createState() =>
      _LocationAutocompleteFieldState();
}

class _LocationAutocompleteFieldState extends State<LocationAutocompleteField> {
  final _focus = FocusNode();
  List<PlaceSuggestion> _suggestions = [];
  Timer? _debounce;
  bool _loading = false;
  bool _suppressSearch = false;

  PlacesService get _places => context.read<PlacesService>();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onTextChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) {
      setState(() => _suggestions = []);
    }
  }

  void _onTextChanged() {
    if (_suppressSearch) return;
    widget.onAddressEdited?.call(widget.controller.text);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      final q = widget.controller.text.trim();
      if (q.length < 2) {
        if (mounted) setState(() => _suggestions = []);
        return;
      }
      if (!mounted) return;
      setState(() => _loading = true);
      final list = await _places.autocomplete(q);
      if (!mounted) return;
      setState(() {
        _suggestions = list;
        _loading = false;
      });
    });
  }

  Future<void> _selectSuggestion(PlaceSuggestion s) async {
    setState(() {
      _suggestions = [];
      _loading = true;
    });
    final loc = await _places.placeDetails(s.placeId);
    if (!mounted) return;
    setState(() => _loading = false);
    if (loc == null) return;
    _suppressSearch = true;
    widget.controller.text = loc.address;
    _suppressSearch = false;
    widget.onLocation(loc);
    _focus.unfocus();
  }

  Future<void> _useMyLocation() async {
    if (widget.onUseMyLocation != null) {
      await widget.onUseMyLocation!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            widget.icon,
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                onTap: widget.onTap,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: BytzGoTheme.sheetText,
                ),
                decoration: InputDecoration(
                  hintText: widget.locating
                      ? 'Getting your location…'
                      : widget.resolving
                          ? 'Finding address…'
                          : widget.hint,
                  hintStyle: TextStyle(
                    color: BytzGoTheme.sheetMuted.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  suffixIcon: widget.showUseMyLocation
                      ? IconButton(
                          tooltip: 'Use my location',
                          onPressed: (widget.locating || widget.resolving)
                              ? null
                              : _useMyLocation,
                          icon: (widget.locating || widget.resolving)
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(
                                  Icons.my_location,
                                  size: 20,
                                  color: BytzGoTheme.accentDark,
                                ),
                        )
                      : (_loading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null),
                ),
              ),
            ),
          ],
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(left: 24, right: 8, bottom: 4),
            decoration: BoxDecoration(
              color: BytzGoTheme.sheetBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: BytzGoTheme.sheetDivider),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: BytzGoTheme.sheetDivider.withValues(alpha: 0.6),
              ),
              itemBuilder: (context, i) {
                final s = _suggestions[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.place_outlined,
                    size: 20,
                    color: BytzGoTheme.sheetMuted,
                  ),
                  title: Text(
                    s.description,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: BytzGoTheme.sheetText,
                    ),
                  ),
                  onTap: () => _selectSuggestion(s),
                );
              },
            ),
          ),
      ],
    );
  }
}
