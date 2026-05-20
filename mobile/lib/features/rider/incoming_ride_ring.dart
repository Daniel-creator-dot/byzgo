import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

/// Repeating ring + vibration while an incoming ride offer is shown (web parity).
class IncomingRideRing {
  IncomingRideRing._();

  static bool _active = false;
  static Timer? _pulseTimer;

  static Future<void> start() async {
    if (_active) return;
    _active = true;

    try {
      if (!kIsWeb) {
        await FlutterRingtonePlayer().play(
          android: AndroidSounds.ringtone,
          ios: IosSounds.bell,
          looping: true,
          volume: 1.0,
          asAlarm: true,
        );
      }
    } catch (e) {
      debugPrint('IncomingRideRing: play failed ($e)');
    }

    await _hapticPulse();
    _pulseTimer?.cancel();
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (_active) _hapticPulse();
    });
  }

  static Future<void> _hapticPulse() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await HapticFeedback.mediumImpact();
  }

  static void stop() {
    _active = false;
    _pulseTimer?.cancel();
    _pulseTimer = null;
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {}
  }
}
