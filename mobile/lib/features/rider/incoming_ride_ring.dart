import 'dart:async' show Timer, unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

/// Repeating ring + vibration while an incoming ride offer is shown (web parity).
class IncomingRideRing {
  IncomingRideRing._();

  static bool _active = false;
  static Timer? _pulseTimer;
  static Timer? _maxDurationTimer;

  /// [maxDuration] caps ring length (Bolt-style ~15s). Null = ring until [stop].
  static Future<void> start({
    Duration maxDuration = const Duration(seconds: 15),
  }) async {
    if (_active) {
      _replayRingtone();
      return;
    }
    _active = true;

    _replayRingtone();
    unawaited(_hapticPulse());
    _pulseTimer?.cancel();
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (_active) _hapticPulse();
    });

    _maxDurationTimer?.cancel();
    if (maxDuration > Duration.zero) {
      _maxDurationTimer = Timer(maxDuration, stop);
    }
  }

  static void _replayRingtone() {
    if (kIsWeb) return;
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {}
    try {
      FlutterRingtonePlayer().play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.bell,
        looping: true,
        volume: 1.0,
        asAlarm: true,
      );
    } catch (e) {
      debugPrint('IncomingRideRing: play failed ($e)');
    }
  }

  static Future<void> _hapticPulse() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await HapticFeedback.mediumImpact();
  }

  static void stop() {
    _active = false;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    _pulseTimer?.cancel();
    _pulseTimer = null;
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {}
  }
}
