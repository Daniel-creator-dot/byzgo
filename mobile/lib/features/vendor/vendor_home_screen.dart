import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/ride_ui.dart';

class VendorHomeScreen extends StatelessWidget {
  const VendorHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user!;

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
            Text('Store', style: BytzGoTheme.sheetTitle()),
            const SizedBox(height: 8),
            Text(
              '${user.name} — vendor dashboard coming soon',
              style: BytzGoTheme.sheetBody(),
            ),
            const SizedBox(height: 24),
            const Icon(Icons.storefront_outlined, size: 64, color: BytzGoTheme.sheetMuted),
          ],
        ),
      ),
    );
  }
}
