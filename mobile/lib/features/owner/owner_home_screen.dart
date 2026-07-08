import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../models/vehicle.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/delete_account_button.dart';
import '../../shared/widgets/help_support_tile.dart';
import '../../shared/widgets/legal_links.dart';
import '../../shared/widgets/ops_stat_card.dart';
import '../../shared/widgets/ride_ui.dart';
import 'owner_repository.dart';

enum _OwnerTab { overview, vehicles }

class OwnerHomeScreen extends StatefulWidget {
  const OwnerHomeScreen({super.key});

  @override
  State<OwnerHomeScreen> createState() => _OwnerHomeScreenState();
}

class _OwnerHomeScreenState extends State<OwnerHomeScreen> {
  _OwnerTab _tab = _OwnerTab.overview;
  OwnerDashboard? _dash;
  bool _loading = true;
  String? _error;

  bool get _accountActive => _dash?.ownerStatus == 'active';

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
      final dash = await context.read<OwnerRepository>().fetchDashboard();
      if (!mounted) return;
      setState(() {
        _dash = dash;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = OwnerRepository.errorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await context.read<Session>().clear();
    if (mounted) context.go('/login');
  }

  Future<void> _openVehicleEditor([Vehicle? vehicle]) async {
    if (!_accountActive) {
      _snack('Your fleet owner account is pending admin approval.');
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _VehicleEditorSheet(vehicle: vehicle),
    );
    if (saved == true) await _load();
  }

  Future<void> _deleteVehicle(Vehicle vehicle) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove vehicle?'),
        content: Text('Delete ${vehicle.plateNumber} from your fleet?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: BytzGoTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<OwnerRepository>().deleteVehicle(vehicle.id);
      await _load();
      if (mounted) _snack('Vehicle removed', success: true);
    } catch (e) {
      if (mounted) _snack(OwnerRepository.errorMessage(e));
    }
  }

  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? BytzGoTheme.accentDark : BytzGoTheme.sheetText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user;
    final dash = _dash;

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: const Color(0xFF020617),
        foregroundColor: Colors.white,
        title: const Text('My fleet'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      floatingActionButton: _tab == _OwnerTab.vehicles && _accountActive
          ? FloatingActionButton.extended(
              onPressed: () => _openVehicleEditor(),
              backgroundColor: BytzGoTheme.accent,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add vehicle'),
            )
          : null,
      body: Column(
        children: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      user.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (dash?.ownerStatus != null)
                    _StatusChip(status: dash!.ownerStatus!),
                ],
              ),
            ),
          _tabBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: BytzGoTheme.accent))
                : _error != null
                    ? _errorPanel()
                    : dash == null
                        ? const SizedBox.shrink()
                        : _tab == _OwnerTab.overview
                            ? _overview(dash)
                            : _vehiclesList(dash.vehicles),
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          _tabChip('Overview', _OwnerTab.overview, Icons.dashboard_rounded),
          const SizedBox(width: 8),
          _tabChip('Vehicles', _OwnerTab.vehicles, Icons.two_wheeler_rounded),
        ],
      ),
    );
  }

  Widget _tabChip(String label, _OwnerTab tab, IconData icon) {
    final selected = _tab == tab;
    return Expanded(
      child: Material(
        color: selected ? BytzGoTheme.accent : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _tab = tab),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: selected ? Colors.black : Colors.white70),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorPanel() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            RidePrimaryButton(label: 'Try again', onPressed: _load),
          ],
        ),
      ),
    );
  }

  Widget _overview(OwnerDashboard dash) {
    final pending = !_accountActive;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (pending)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
            ),
            child: const Text(
              'Your fleet owner account is pending approval. Once approved, you can register vehicles and assign drivers.',
              style: TextStyle(color: Colors.white, height: 1.35),
            ),
          ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [
            OpsStatCard(
              label: 'Total vehicles',
              value: '${dash.stats.totalVehicles}',
              icon: Icons.two_wheeler_rounded,
            ),
            OpsStatCard(
              label: 'Active',
              value: '${dash.stats.activeVehicles}',
              icon: Icons.check_circle_outline_rounded,
            ),
            OpsStatCard(
              label: 'Assigned riders',
              value: '${dash.stats.assignedVehicles}',
              icon: Icons.person_outline_rounded,
            ),
            OpsStatCard(
              label: 'In maintenance',
              value: '${dash.stats.maintenanceVehicles}',
              icon: Icons.build_outlined,
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Manage motorcycles and bikes your riders use on BytzGo.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        const SizedBox(height: 20),
        const HelpSupportTile(dark: true),
        const SizedBox(height: 8),
        const LegalLinksRow(),
        const SizedBox(height: 16),
        const DeleteAccountButton(),
      ],
    );
  }

  Widget _vehiclesList(List<Vehicle> vehicles) {
    if (vehicles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.two_wheeler_outlined, size: 56, color: Colors.white.withValues(alpha: 0.35)),
              const SizedBox(height: 12),
              Text(
                _accountActive
                    ? 'No vehicles yet. Tap Add vehicle to register your first bike.'
                    : 'Vehicles can be added after your account is approved.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
      itemCount: vehicles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final v = vehicles[i];
        return _VehicleCard(
          vehicle: v,
          onEdit: () => _openVehicleEditor(v),
          onDelete: () => _deleteVehicle(v),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active' => BytzGoTheme.accent,
      'pending' => Colors.amber,
      'rejected' => BytzGoTheme.danger,
      _ => Colors.white54,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.onEdit,
    required this.onDelete,
  });

  final Vehicle vehicle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (vehicle.status) {
      'active' => BytzGoTheme.accent,
      'maintenance' => Colors.amber,
      'retired' => Colors.white54,
      _ => Colors.white54,
    };

    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.two_wheeler_rounded, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      vehicle.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                    onSelected: (v) {
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Remove')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${vehicle.vehicleType.replaceAll('_', ' ')} · ${vehicle.status}',
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              if (vehicle.assignedRiderName != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Rider: ${vehicle.assignedRiderName}'
                  '${vehicle.assignedRiderPhone != null ? ' · ${vehicle.assignedRiderPhone}' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ] else ...[
                const SizedBox(height: 6),
                const Text(
                  'No rider assigned',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleEditorSheet extends StatefulWidget {
  const _VehicleEditorSheet({this.vehicle});

  final Vehicle? vehicle;

  @override
  State<_VehicleEditorSheet> createState() => _VehicleEditorSheetState();
}

class _VehicleEditorSheetState extends State<_VehicleEditorSheet> {
  final _plateCtrl = TextEditingController();
  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _riderIdCtrl = TextEditingController();
  String _vehicleType = 'motorcycle';
  String _status = 'active';
  bool _saving = false;
  String? _error;

  bool get _editing => widget.vehicle != null;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    if (v != null) {
      _plateCtrl.text = v.plateNumber;
      _makeCtrl.text = v.make ?? '';
      _modelCtrl.text = v.model ?? '';
      _yearCtrl.text = v.year?.toString() ?? '';
      _colorCtrl.text = v.color ?? '';
      _notesCtrl.text = v.notes ?? '';
      _riderIdCtrl.text = v.assignedRiderId ?? '';
      _vehicleType = v.vehicleType;
      _status = v.status;
    }
  }

  @override
  void dispose() {
    _plateCtrl.dispose();
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _yearCtrl.dispose();
    _colorCtrl.dispose();
    _notesCtrl.dispose();
    _riderIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final plate = _plateCtrl.text.trim();
    if (plate.length < 3) {
      setState(() => _error = 'Enter plate number');
      return;
    }
    final year = int.tryParse(_yearCtrl.text.trim());
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = context.read<OwnerRepository>();
      final riderId = _riderIdCtrl.text.trim();
      if (_editing) {
        await repo.updateVehicle(
          id: widget.vehicle!.id,
          plateNumber: plate,
          make: _makeCtrl.text.trim(),
          model: _modelCtrl.text.trim(),
          year: year,
          color: _colorCtrl.text.trim(),
          vehicleType: _vehicleType,
          status: _status,
          notes: _notesCtrl.text.trim(),
          assignedRiderId: riderId.isEmpty ? null : riderId,
          clearAssignedRider: riderId.isEmpty,
        );
      } else {
        await repo.createVehicle(
          plateNumber: plate,
          make: _makeCtrl.text.trim().isEmpty ? null : _makeCtrl.text.trim(),
          model: _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
          year: year,
          color: _colorCtrl.text.trim().isEmpty ? null : _colorCtrl.text.trim(),
          vehicleType: _vehicleType,
          status: _status,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = OwnerRepository.errorMessage(e);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BytzGoTheme.sheetDecoration(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _editing ? 'Edit vehicle' : 'Add vehicle',
                style: BytzGoTheme.sheetTitle(20),
              ),
              const SizedBox(height: 16),
              _field(_plateCtrl, 'Plate number *'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _field(_makeCtrl, 'Make')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_modelCtrl, 'Model')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _field(_yearCtrl, 'Year', keyboard: TextInputType.number)),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_colorCtrl, 'Color')),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _vehicleType,
                decoration: _inputDeco('Vehicle type'),
                items: const [
                  DropdownMenuItem(value: 'motorcycle', child: Text('Motorcycle / Okada')),
                  DropdownMenuItem(value: 'keke', child: Text('Keke (tricycle)')),
                  DropdownMenuItem(value: 'bicycle', child: Text('Bicycle')),
                  DropdownMenuItem(value: 'car', child: Text('Car')),
                  DropdownMenuItem(value: 'van', child: Text('Van')),
                ],
                onChanged: (v) => setState(() => _vehicleType = v ?? 'motorcycle'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: _inputDeco('Status'),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'maintenance', child: Text('Maintenance')),
                  DropdownMenuItem(value: 'retired', child: Text('Retired')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'active'),
              ),
              if (_editing) ...[
                const SizedBox(height: 10),
                _field(
                  _riderIdCtrl,
                  'Assigned rider ID (optional)',
                  hint: 'Paste driver user ID from admin',
                ),
              ],
              const SizedBox(height: 10),
              _field(_notesCtrl, 'Notes', maxLines: 2),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: BytzGoTheme.danger)),
              ],
              const SizedBox(height: 18),
              RidePrimaryButton(
                label: _saving ? 'Saving…' : 'Save vehicle',
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    TextInputType? keyboard,
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      maxLines: maxLines,
      decoration: _inputDeco(label, hint: hint),
    );
  }

  InputDecoration _inputDeco(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF3F4F6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }
}
