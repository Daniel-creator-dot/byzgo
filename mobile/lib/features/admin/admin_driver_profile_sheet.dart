import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/json_parse.dart';
import '../../core/maps_runtime_config.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import 'admin_repository.dart';

/// Full driver dossier for admin (map tap / fleet).
Future<void> showAdminDriverProfileSheet(
  BuildContext context, {
  required String riderId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0B1220),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (_, scroll) => _AdminDriverProfileBody(
        riderId: riderId,
        scrollController: scroll,
      ),
    ),
  );
}

class _AdminDriverProfileBody extends StatefulWidget {
  const _AdminDriverProfileBody({
    required this.riderId,
    required this.scrollController,
  });

  final String riderId;
  final ScrollController scrollController;

  @override
  State<_AdminDriverProfileBody> createState() => _AdminDriverProfileBodyState();
}

class _AdminDriverProfileBodyState extends State<_AdminDriverProfileBody> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<AdminRepository>().fetchRiderProfile(widget.riderId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AdminRepository.errorMessage(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<MapsRuntimeConfig>();
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
          child: Row(
            children: [
              const Text(
                'DRIVER PROFILE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white54),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: BytzGoTheme.accent),
                )
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                            const SizedBox(height: 12),
                            FilledButton(onPressed: _load, child: const Text('Retry')),
                          ],
                        ),
                      ),
                    )
                  : _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final driver = Map<String, dynamic>.from(_data!['driver'] as Map? ?? {});
    final stats = Map<String, dynamic>.from(_data!['stats'] as Map? ?? {});
    final policy = Map<String, dynamic>.from(_data!['commission_policy'] as Map? ?? {});
    final totals = Map<String, dynamic>.from(_data!['commission_totals'] as Map? ?? {});
    final docs = (_data!['documents'] as List?) ?? [];
    final trips = (_data!['recent_trips'] as List?) ?? [];
    final settlements = (_data!['settlements'] as List?) ?? [];

    final liveLat = parseJsonDouble(driver['live_lat']);
    final liveLng = parseJsonDouble(driver['live_lng']);
    final hasLive = driver['has_live_location'] == true && liveLat != null && liveLng != null;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: BytzGoTheme.accent.withValues(alpha: 0.2),
              child: Text(
                (driver['name']?.toString() ?? '?').isNotEmpty
                    ? driver['name'].toString()[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: BytzGoTheme.accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    driver['name']?.toString() ?? 'Driver',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    driver['phone']?.toString() ?? driver['email']?.toString() ?? '',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      _chip(
                        driver['is_online'] == true ? 'ONLINE' : 'OFFLINE',
                        driver['is_online'] == true ? BytzGoTheme.accent : Colors.white38,
                      ),
                      _chip(
                        (driver['status']?.toString() ?? 'unknown').toUpperCase(),
                        BytzGoTheme.brandBlueBright,
                      ),
                      if (driver['region'] != null)
                        _chip(driver['region'].toString(), Colors.white38),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _statRow([
          _stat('Trips', '${stats['trips_delivered'] ?? 0}'),
          _stat('Rating', _formatRating(stats)),
          _stat('Balance', formatCedis(parseJsonDouble(driver['balance']) ?? 0)),
        ]),
        _statRow([
          _stat('Active', '${stats['trips_active'] ?? 0}'),
          _stat('Earnings', formatCedis(parseJsonDouble(stats['delivery_earnings']) ?? 0)),
          _stat(
            'Commission',
            formatCedis(parseJsonDouble(totals['commission_accrued']) ?? 0),
          ),
        ]),
        const SizedBox(height: 12),
        Text(
          'Commission policy: ${policy['totalPercent'] ?? policy['total_percent'] ?? '10'}% '
          '(${policy['insurancePercent'] ?? policy['insurance_percent'] ?? '3'}% insurance · '
          '${policy['platformPercent'] ?? policy['platform_percent'] ?? '7'}% BytzGo)',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11),
        ),
        Text(
          'Insurance accrued: ${formatCedis(parseJsonDouble(totals['insurance_accrued']) ?? 0)} · '
          'Platform: ${formatCedis(parseJsonDouble(totals['platform_accrued']) ?? 0)}',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10),
        ),
        if (hasLive) ...[
          const SizedBox(height: 16),
          Text(
            'LIVE GPS',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 160,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(liveLat, liveLng),
                  zoom: 14,
                ),
                markers: {
                  Marker(
                    markerId: MarkerId(driver['id']?.toString() ?? 'rider'),
                    position: LatLng(liveLat, liveLng),
                  ),
                },
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                liteModeEnabled: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${liveLat.toStringAsFixed(5)}, ${liveLng.toStringAsFixed(5)}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10),
                ),
              ),
              TextButton(
                onPressed: () => _openMaps(liveLat, liveLng),
                child: const Text('Open in Maps'),
              ),
            ],
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'No live GPS — driver offline or location not reported.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
            ),
          ),
        if (docs.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle('KYC DOCUMENTS'),
          ...docs.map((d) {
            final m = Map<String, dynamic>.from(d as Map);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                m['doc_type']?.toString().replaceAll('_', ' ').toUpperCase() ?? 'DOC',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
              ),
              subtitle: Text(
                'Status: ${m['review_status'] ?? 'pending'}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
              ),
            );
          }),
        ],
        if (settlements.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionTitle('COMMISSION SETTLEMENTS'),
          ...settlements.take(7).map((s) {
            final m = Map<String, dynamic>.from(s as Map);
            final owed = parseJsonDouble(m['amount_owed']) ?? 0;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                m['settlement_date']?.toString() ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              trailing: Text(
                owed > 0.01 ? formatCedis(owed) : 'Paid',
                style: TextStyle(
                  color: m['status'] == 'overdue' ? Colors.redAccent : BytzGoTheme.accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                m['status']?.toString() ?? '',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
              ),
            );
          }),
        ],
        if (trips.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionTitle('RECENT TRIPS'),
          ...trips.take(8).map((t) {
            final m = Map<String, dynamic>.from(t as Map);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                '#${(m['id']?.toString() ?? '').substring(0, 8)} · ${m['status']}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              subtitle: Text(
                m['address']?.toString() ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatCedis(parseJsonDouble(m['total']) ?? 0),
                    style: const TextStyle(
                      color: BytzGoTheme.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  if (m['rating'] != null)
                    Text(
                      '★ ${m['rating']}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10),
                    ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  String _formatRating(Map<String, dynamic> stats) {
    final avg = parseJsonDouble(stats['avg_rating']) ?? 0;
    final count = stats['rating_count'] ?? 0;
    if (count == 0) return '—';
    return '${avg.toStringAsFixed(1)} ($count)';
  }

  Future<void> _openMaps(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      );

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900),
        ),
      );

  Widget _statRow(List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: children[i]),
            ],
          ],
        ),
      );

  Widget _stat(String label, String value) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
}
