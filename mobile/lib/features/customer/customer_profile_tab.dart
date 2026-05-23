import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../shared/ghana_regions.dart';
import '../../shared/theme.dart';
import '../../shared/user_display.dart';
import '../../shared/widgets/help_support_tile.dart';
import '../../shared/widgets/profile_avatar_upload.dart';
import '../../shared/widgets/delete_account_button.dart';
import '../../shared/widgets/legal_links.dart';
import '../../shared/widgets/bytz_scaffold.dart';
import '../../shared/widgets/ride_ui.dart';
import '../auth/auth_repository.dart';

class CustomerProfileTab extends StatefulWidget {
  const CustomerProfileTab({super.key});

  @override
  State<CustomerProfileTab> createState() => _CustomerProfileTabState();
}

class _CustomerProfileTabState extends State<CustomerProfileTab> {
  final _phoneCtrl = TextEditingController();
  String? _region;
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final user = context.read<Session>().user;
    _phoneCtrl.text = user?.phone ?? '';
    _region = user?.region;
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final result = await context.read<AuthRepository>().updateProfile(
            phone: _phoneCtrl.text.trim(),
            region: _region,
          );
      if (!mounted) return;
      await context.read<Session>().setSession(
            token: result.token,
            user: result.user,
          );
      setState(() => _message = 'Profile saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = AuthRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    if (!await confirmSignOut(context)) return;
    await context.read<Session>().clear();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user!;
    final firstName = userFirstName(user);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Center(
          child: ProfileAvatarUpload(user: user, radius: 44),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Tap photo to change',
            style: BytzGoTheme.sheetBody(11),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            user.name,
            style: BytzGoTheme.sheetTitle(20),
            textAlign: TextAlign.center,
          ),
        ),
        Center(
          child: Text(
            'Hey $firstName — manage your account',
            style: BytzGoTheme.sheetBody(13),
          ),
        ),
        const SizedBox(height: 24),
        _infoTile(Icons.email_outlined, 'Email', user.email),
        if (user.address != null && user.address!.isNotEmpty)
          _infoTile(Icons.location_on_outlined, 'Address', user.address!),
        const SizedBox(height: 16),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'Phone',
            prefixIcon: const Icon(Icons.phone_outlined),
            filled: true,
            fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _region,
          decoration: InputDecoration(
            labelText: 'Region',
            prefixIcon: const Icon(Icons.map_outlined),
            filled: true,
            fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
          items: ghanaRegions
              .map((r) => DropdownMenuItem(value: r, child: Text(r)))
              .toList(),
          onChanged: (v) => setState(() => _region = v),
        ),
        const SizedBox(height: 20),
        RidePrimaryButton(
          label: 'Save changes',
          loading: _saving,
          onPressed: _save,
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(
            _message!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _message == 'Profile saved'
                  ? BytzGoTheme.accentDark
                  : BytzGoTheme.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 28),
        const HelpSupportTile(),
        const SizedBox(height: 12),
        _actionRow(
          icon: Icons.shield_outlined,
          label: 'Delivery PIN',
          subtitle: 'Riders confirm handoff with your 6-digit PIN',
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'When your order arrives, share the PIN shown in trip tracking with your rider.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
        _actionRow(
          icon: Icons.notifications_outlined,
          label: 'Push notifications',
          subtitle: 'Enabled for live trip & order updates',
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Allow notifications when prompted so you get rider arrival alerts.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        const ProfileLegalSection(),
        const SizedBox(height: 16),
        const Center(child: DeleteAccountButton()),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout, color: BytzGoTheme.danger),
          label: const Text(
            'Sign out',
            style: TextStyle(
              color: BytzGoTheme.danger,
              fontWeight: FontWeight.w800,
            ),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            side: const BorderSide(color: BytzGoTheme.danger),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: BytzGoTheme.sheetMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: BytzGoTheme.sheetBody(11),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: BytzGoTheme.sheetText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, color: BytzGoTheme.brandBlue),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: BytzGoTheme.sheetText,
                        ),
                      ),
                      Text(subtitle, style: BytzGoTheme.sheetBody(12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: BytzGoTheme.sheetMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
