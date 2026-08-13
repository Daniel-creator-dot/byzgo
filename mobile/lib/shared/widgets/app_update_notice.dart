import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config_repository.dart';
import '../../models/app_update_notice.dart';
import '../theme.dart';

/// Full-screen update / announcement dialog for every role.
class AppUpdateNoticeHost extends StatefulWidget {
  const AppUpdateNoticeHost({super.key, required this.child});

  final Widget child;

  @override
  State<AppUpdateNoticeHost> createState() => _AppUpdateNoticeHostState();
}

class _AppUpdateNoticeHostState extends State<AppUpdateNoticeHost> {
  static const _dismissKey = 'bytzgo_app_update_dismissed';
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_check());
    });
  }

  Future<void> _check() async {
    if (!mounted) return;
    final config = await context.read<ConfigRepository>().fetchAppUpdateNotice();
    if (!mounted || config == null) return;
    PackageInfo? info;
    try {
      info = await PackageInfo.fromPlatform();
    } catch (_) {}
    final version = info?.version ?? '';
    final build = int.tryParse(info?.buildNumber ?? '') ?? 0;
    if (!config.shouldShowFor(currentVersion: version, currentBuild: build)) {
      return;
    }
    if (!config.force) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getString(_dismissKey) == config.id) return;
      } catch (_) {}
    }
    if (!mounted || _dialogOpen) return;
    _dialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: !config.force,
      builder: (ctx) => _UpdateDialog(
        config: config,
        onLater: config.force
            ? null
            : () async {
                try {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString(_dismissKey, config.id);
                } catch (_) {}
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
      ),
    );
    _dialogOpen = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.config, this.onLater});

  final AppUpdateNoticeConfig config;
  final Future<void> Function()? onLater;

  Future<void> _openStore() async {
    final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final raw = isIos ? config.iosUrl : config.androidUrl;
    final url = Uri.tryParse(raw);
    if (url == null) return;
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'APP UPDATE',
            style: TextStyle(
              color: BytzGoTheme.accent,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            config.title.isEmpty ? 'New BytzGo update' : config.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
      content: Text(
        config.message,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.78),
          fontSize: 14,
          height: 1.4,
        ),
      ),
      actions: [
        if (onLater != null)
          TextButton(
            onPressed: () => unawaited(onLater!()),
            child: const Text('Later'),
          ),
        FilledButton(
          onPressed: () => unawaited(_openStore()),
          style: FilledButton.styleFrom(backgroundColor: BytzGoTheme.brandBlue),
          child: const Text('Update now'),
        ),
      ],
    );
  }
}
