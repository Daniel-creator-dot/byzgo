import 'package:flutter/material.dart';

import '../theme.dart';

/// Branded empty state for light sheets and dark screens.
class BytzEmptyState extends StatelessWidget {
  const BytzEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.light = false,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final iconColor = light ? BytzGoTheme.sheetMuted : BytzGoTheme.textMuted;
    final titleStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: light ? BytzGoTheme.sheetText : BytzGoTheme.textPrimary,
    );
    final subtitleStyle = TextStyle(
      color: light ? BytzGoTheme.sheetMuted : BytzGoTheme.textMuted,
      height: 1.35,
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: iconColor.withValues(alpha: 0.85)),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: titleStyle),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, textAlign: TextAlign.center, style: subtitleStyle),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: BytzGoTheme.brandBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(actionLabel!, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error panel with optional retry — use instead of raw red text.
class BytzErrorPanel extends StatelessWidget {
  const BytzErrorPanel({
    super.key,
    required this.message,
    this.title = 'Something went wrong',
    this.onRetry,
    this.light = true,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final bg = light
        ? BytzGoTheme.danger.withValues(alpha: 0.08)
        : BytzGoTheme.danger.withValues(alpha: 0.15);
    final border = light
        ? BytzGoTheme.danger.withValues(alpha: 0.25)
        : BytzGoTheme.danger.withValues(alpha: 0.4);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: BytzGoTheme.danger, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: light ? BytzGoTheme.sheetText : BytzGoTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: TextStyle(
                          color: light ? BytzGoTheme.sheetMuted : BytzGoTheme.textMuted,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Try again'),
                  style: TextButton.styleFrom(foregroundColor: BytzGoTheme.brandBlue),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Router / full-page not found.
class BytzRouteErrorScreen extends StatelessWidget {
  const BytzRouteErrorScreen({super.key, this.detail});

  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BytzGoTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.explore_off_outlined, size: 56, color: BytzGoTheme.textMuted),
              const SizedBox(height: 16),
              const Text(
                'Page not available',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: BytzGoTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                detail ?? 'This link may be outdated. Go back to the home screen.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: BytzGoTheme.textMuted, height: 1.35),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: FilledButton.styleFrom(
                  backgroundColor: BytzGoTheme.brandBlue,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Go back', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmSignOut(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Theme(
      data: BytzGoTheme.sheetTheme(),
      child: AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to book or drive.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out', style: TextStyle(color: BytzGoTheme.danger)),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

void showLegalLinkError(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Could not open link. Check your connection and try again.'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
