import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../features/auth/auth_repository.dart';
import '../theme.dart';

/// Google Play: in-app account deletion.
class DeleteAccountButton extends StatelessWidget {
  const DeleteAccountButton({super.key, this.dark = false});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _confirmDelete(context),
      icon: Icon(
        Icons.delete_forever_outlined,
        color: dark ? Colors.redAccent : BytzGoTheme.danger,
        size: 20,
      ),
      label: Text(
        'Delete account',
        style: TextStyle(
          color: dark ? Colors.redAccent : BytzGoTheme.danger,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently removes your profile, documents, and login. '
          'You cannot delete while you have active orders.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: BytzGoTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await context.read<AuthRepository>().deleteAccount();
      if (!context.mounted) return;
      await context.read<Session>().clear();
      if (context.mounted) context.go('/login');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AuthRepository.errorMessage(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
