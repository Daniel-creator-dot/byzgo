import 'package:flutter/material.dart';

import '../../shared/theme.dart';
import '../../features/support/support_tickets_screen.dart';

/// Shared entry row for Help & Support across role shells.
class HelpSupportTile extends StatelessWidget {
  const HelpSupportTile({super.key, this.dark = false});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    if (dark) {
      return _DarkTile(onTap: () => _open(context));
    }
    return _LightTile(onTap: () => _open(context));
  }

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SupportTicketsScreen(),
      ),
    );
  }
}

class _LightTile extends StatelessWidget {
  const _LightTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: BytzGoTheme.brandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.support_agent_outlined,
                  color: BytzGoTheme.brandBlue,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Help & support',
                      style: BytzGoTheme.sheetTitle(15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Chat with our team · track your cases',
                      style: BytzGoTheme.sheetBody(12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: BytzGoTheme.sheetMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _DarkTile extends StatelessWidget {
  const _DarkTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0F172A),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: BytzGoTheme.brandBlue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.support_agent_outlined,
                  color: BytzGoTheme.brandBlueBright,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Help & support',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      'Chat with our team · track your cases',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}
