import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/ride_ui.dart';

/// Returns true when a customer session exists; otherwise routes to sign-in.
bool requireCustomerAuth(BuildContext context, {String? message}) {
  if (context.read<Session>().isAuthenticated) return true;
  if (message != null && message.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  context.push('/login');
  return false;
}

/// Inline prompt shown for guest-only tabs (activity, profile).
class GuestSignInPrompt extends StatelessWidget {
  const GuestSignInPrompt({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 48,
              color: BytzGoTheme.brandBlue.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: BytzGoTheme.sheetTitle(20),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: BytzGoTheme.sheetBody(14),
            ),
            const SizedBox(height: 24),
            RidePrimaryButton(
              label: 'Sign in',
              icon: Icons.login_rounded,
              onPressed: () => context.push('/login'),
            ),
          ],
        ),
      ),
    );
  }
}
