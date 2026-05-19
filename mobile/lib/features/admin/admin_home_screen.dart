import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/ride_ui.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RideShell(
      topBar: Row(
        children: [
          Material(
            color: BytzGoTheme.sheetBg,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: () async {
                await context.read<Session>().clear();
                if (context.mounted) context.go('/login');
              },
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.arrow_back, color: BytzGoTheme.sheetText),
              ),
            ),
          ),
        ],
      ),
      sheet: RideSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Admin', style: BytzGoTheme.sheetTitle()),
            const SizedBox(height: 8),
            Text('Platform console — web admin for now', style: BytzGoTheme.sheetBody()),
            const SizedBox(height: 24),
            const Icon(Icons.admin_panel_settings_outlined, size: 64, color: BytzGoTheme.sheetMuted),
          ],
        ),
      ),
    );
  }
}
