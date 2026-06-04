import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Large live ETA countdown (Bolt-style MM:SS) or static minutes chip.
class BoltEtaPill extends StatefulWidget {
  const BoltEtaPill({
    super.key,
    this.minutes,
    this.expiresAt,
    this.subtitle,
    this.compact = false,
    this.label = 'remaining',
  });

  /// Static minutes when [expiresAt] is null.
  final int? minutes;

  /// Live countdown target; ticks every second until elapsed.
  final DateTime? expiresAt;
  final String? subtitle;
  final bool compact;
  final String label;

  @override
  State<BoltEtaPill> createState() => _BoltEtaPillState();
}

class _BoltEtaPillState extends State<BoltEtaPill> {
  Timer? _tick;
  int _remainingSec = 0;

  @override
  void initState() {
    super.initState();
    _syncRemaining();
    _startTicker();
  }

  @override
  void didUpdateWidget(BoltEtaPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expiresAt != widget.expiresAt ||
        oldWidget.minutes != widget.minutes) {
      _syncRemaining();
      _startTicker();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _tick?.cancel();
    if (widget.expiresAt == null) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = _secondsLeft();
      if (next != _remainingSec) setState(() => _remainingSec = next);
    });
  }

  void _syncRemaining() {
    _remainingSec = _secondsLeft();
  }

  int _secondsLeft() {
    final exp = widget.expiresAt;
    if (exp == null) {
      final m = widget.minutes;
      if (m == null) return 0;
      return (m < 1 ? 1 : m) * 60;
    }
    final sec = exp.difference(DateTime.now()).inSeconds;
    return sec < 0 ? 0 : sec;
  }

  String get _timeLabel {
    if (widget.expiresAt != null) {
      final s = _remainingSec;
      if (s <= 0) return '0:01';
      if (s >= 3600) {
        final h = s ~/ 3600;
        final m = (s % 3600) ~/ 60;
        return '$h:${m.toString().padLeft(2, '0')}';
      }
      final m = s ~/ 60;
      final sec = s % 60;
      return '$m:${sec.toString().padLeft(2, '0')}';
    }
    final m = widget.minutes;
    if (m == null) return '—';
    return m < 1 ? '1' : '$m';
  }

  bool get _showMinSuffix =>
      widget.expiresAt == null && widget.minutes != null;

  @override
  Widget build(BuildContext context) {
    final timeStyle = TextStyle(
      fontSize: widget.compact ? 18 : 40,
      fontWeight: FontWeight.w900,
      height: 1,
      color: widget.compact ? Colors.white : BytzGoTheme.brandBlue,
      letterSpacing: widget.compact ? 0 : -1,
      fontFeatures: widget.expiresAt != null
          ? const [FontFeature.tabularFigures()]
          : null,
    );

    if (widget.compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: BytzGoTheme.brandBlue,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_timeLabel, style: timeStyle),
                if (_showMinSuffix) ...[
                  const SizedBox(width: 4),
                  const Text(
                    'min',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
            if (widget.expiresAt != null)
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetBg.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BytzGoTheme.brandBlue.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_timeLabel, style: timeStyle),
              Text(
                widget.expiresAt != null ? widget.label : 'min',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: BytzGoTheme.sheetMuted,
                ),
              ),
            ],
          ),
          if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
            const SizedBox(width: 14),
            Container(
              width: 1,
              height: 44,
              color: BytzGoTheme.sheetDivider,
            ),
            const SizedBox(width: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                widget.subtitle!,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: BytzGoTheme.sheetText,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
