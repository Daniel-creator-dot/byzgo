import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/theme.dart';
import 'admin_repository.dart';

class AdminUpdateNoticeTab extends StatefulWidget {
  const AdminUpdateNoticeTab({super.key});

  @override
  State<AdminUpdateNoticeTab> createState() => _AdminUpdateNoticeTabState();
}

class _AdminUpdateNoticeTabState extends State<AdminUpdateNoticeTab> {
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _versionCtrl = TextEditingController();
  final _buildCtrl = TextEditingController();
  final _iosCtrl = TextEditingController();
  final _androidCtrl = TextEditingController();
  bool _enabled = false;
  bool _force = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    _versionCtrl.dispose();
    _buildCtrl.dispose();
    _iosCtrl.dispose();
    _androidCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notice = await context.read<AdminRepository>().fetchUpdateNotice();
      if (!mounted) return;
      setState(() {
        _enabled = notice.enabled;
        _force = notice.force;
        _titleCtrl.text = notice.title;
        _messageCtrl.text = notice.message;
        _versionCtrl.text = notice.minVersion;
        _buildCtrl.text = notice.minBuild > 0 ? '${notice.minBuild}' : '';
        _iosCtrl.text = notice.iosUrl;
        _androidCtrl.text = notice.androidUrl;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AdminRepository.errorMessage(e);
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AdminRepository>().saveUpdateNotice(
            enabled: _enabled,
            title: _titleCtrl.text.trim(),
            message: _messageCtrl.text.trim(),
            minVersion: _versionCtrl.text.trim(),
            minBuild: _buildCtrl.text.trim(),
            iosUrl: _iosCtrl.text.trim(),
            androidUrl: _androidCtrl.text.trim(),
            force: _force,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update notice saved — everyone will see it')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminRepository.errorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.white70)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show to everyone', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          subtitle: const Text(
            'Customers, riders, vendors, and admin see a popup',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          value: _enabled,
          activeColor: BytzGoTheme.accent,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        const SizedBox(height: 8),
        _field(_titleCtrl, 'Title', 'New BytzGo update'),
        _field(_messageCtrl, 'Message', 'What is new…', maxLines: 5),
        _field(_versionCtrl, 'Min version (optional)', '1.0.61'),
        _field(_buildCtrl, 'Min build (optional)', '86'),
        _field(_iosCtrl, 'iPhone update link', 'https://apps.apple.com/...'),
        _field(_androidCtrl, 'Android update link', 'https://play.google.com/store/apps/details?id=com.bytzgo.bytzgoMobile'),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Force update', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          subtitle: const Text('Hide Later — they must tap Update', style: TextStyle(color: Colors.white54, fontSize: 12)),
          value: _force,
          activeColor: Colors.orange,
          onChanged: (v) => setState(() => _force = v),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: BytzGoTheme.brandBlue,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(_saving ? 'Saving…' : 'Save & show notice'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label, String hint, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: Colors.white54),
          hintStyle: const TextStyle(color: Colors.white24),
          filled: true,
          fillColor: const Color(0xFF111827),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
