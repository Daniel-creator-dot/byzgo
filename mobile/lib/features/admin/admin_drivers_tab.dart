import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/rider_document.dart';
import '../../shared/data_url_image.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/ride_ui.dart';
import '../../shared/widgets/rider_vehicle_type_picker.dart';
import 'admin_repository.dart';
import 'widgets/admin_hero_header.dart';

class AdminDriversTab extends StatefulWidget {
  const AdminDriversTab({super.key, this.onPendingCount});

  final ValueChanged<int>? onPendingCount;

  @override
  State<AdminDriversTab> createState() => AdminDriversTabState();
}

class AdminDriversTabState extends State<AdminDriversTab> {
  List<PendingRiderApplication> _riders = [];
  bool _loading = true;
  String? _error;
  String? _rejectingId;
  final _rejectReason = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _rejectReason.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<AdminRepository>().fetchPendingRiders();
      if (!mounted) return;
      setState(() => _riders = list);
      widget.onPendingCount?.call(list.length);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AdminRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(String id, String name) async {
    try {
      await context.read<AdminRepository>().approveRider(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name approved'),
          backgroundColor: BytzGoTheme.accent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminRepository.errorMessage(e))),
      );
    }
  }

  Future<void> _confirmReject() async {
    final id = _rejectingId;
    if (id == null) return;
    try {
      await context.read<AdminRepository>().rejectRider(
        id,
        reason: _rejectReason.text.trim(),
      );
      if (!mounted) return;
      setState(() => _rejectingId = null);
      await load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminRepository.errorMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: load,
      color: BytzGoTheme.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          AdminHeroHeader(
            title: 'Driver KYC',
            subtitle: 'Verify & approve',
            assetPath: 'assets/branding/hero_rider.png',
            trailing: IconButton(
              onPressed: _loading ? null : load,
              icon: const Icon(Icons.refresh, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(color: BytzGoTheme.accent)),
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.redAccent))
          else if (_riders.isEmpty)
            _emptyState()
          else
            ..._riders.map(_riderCard),
          if (_rejectingId != null) ...[
            const SizedBox(height: 20),
            _rejectPanel(),
          ],
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        children: [
          Image.asset('assets/branding/hero_rider.png', height: 80, fit: BoxFit.contain),
          const SizedBox(height: 12),
          const Text(
            'All caught up',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            'No driver applications waiting for review.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _rejectPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Reject application',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _rejectReason,
            maxLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Reason (optional)',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
              filled: true,
              fillColor: const Color(0xFF020617),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _rejectingId = null),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _confirmReject,
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Reject'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _riderCard(PendingRiderApplication r) {
    const labels = {
      'license': 'Licence',
      'ghana_card': 'Ghana card',
      'photo': 'Photo',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: r.status == 'rejected'
              ? Colors.red.withValues(alpha: 0.35)
              : BytzGoTheme.warning.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: BytzGoTheme.brandBlue.withValues(alpha: 0.3),
                child: Text(
                  r.name.isNotEmpty ? r.name[0].toUpperCase() : '?',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(r.email, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                    if (r.riderVehicleType != null && r.riderVehicleType!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Vehicle: ${RiderVehicleTypePicker.labelFor(r.riderVehicleType)}',
                          style: const TextStyle(
                            color: BytzGoTheme.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _statusChip(r.status ?? 'pending'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: ['license', 'ghana_card', 'photo'].map((type) {
              RiderDocument? doc;
              for (final d in r.documents) {
                if (d.docType == type) {
                  doc = d;
                  break;
                }
              }
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    children: [
                      Text(
                        labels[type] ?? type,
                        style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8)),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: doc != null
                              ? dataUrlImage(doc.imageUrl)
                              : const ColoredBox(
                                  color: Color(0xFF1E293B),
                                  child: Icon(Icons.image_outlined, color: Color(0xFF64748B), size: 20),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: RidePrimaryButton(
                  label: 'Approve',
                  onPressed: () => _approve(r.id, r.name),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _rejectingId = r.id;
                      _rejectReason.clear();
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final rejected = status == 'rejected';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (rejected ? Colors.red : BytzGoTheme.warning).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: rejected ? Colors.redAccent : BytzGoTheme.warning,
        ),
      ),
    );
  }
}
