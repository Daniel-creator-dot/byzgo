import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/order.dart';
import '../../shared/format.dart';
import '../../shared/rider_trip.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/ride_ui.dart';

/// Full-screen incoming job alert (parity with web `IncomingRideCallModal`).
class IncomingRideOverlay extends StatefulWidget {
  const IncomingRideOverlay({
    super.key,
    required this.order,
    required this.onAccept,
    required this.onDecline,
    this.accepting = false,
  });

  final Order order;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final bool accepting;

  @override
  State<IncomingRideOverlay> createState() => _IncomingRideOverlayState();
}

class _IncomingRideOverlayState extends State<IncomingRideOverlay> {
  Timer? _tick;
  int? _secs;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _syncSecs();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    if (!mounted) return;
    final secs = offerSecondsRemaining(widget.order);
    if (secs != null && secs <= 0) {
      widget.onDecline();
      return;
    }
    setState(() => _secs = secs);
  }

  void _syncSecs() {
    _secs = offerSecondsRemaining(widget.order);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final fee = order.deliveryFee ?? order.total;

    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: BytzGoTheme.accent.withValues(alpha: 0.5), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: BytzGoTheme.accent.withValues(alpha: 0.25),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.bolt, color: BytzGoTheme.warning, size: 28),
                        const SizedBox(width: 10),
                        const Text(
                          'NEW RIDE',
                          style: TextStyle(
                            color: BytzGoTheme.warning,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const Spacer(),
                        if (_secs != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: BytzGoTheme.warning.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_secs}s',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: BytzGoTheme.warning,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      formatCedis(fee),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (order.isCourier && order.pickup != null) ...[
                      const SizedBox(height: 12),
                      Text('Pickup: ${order.pickup}', style: _body),
                    ],
                    const SizedBox(height: 8),
                    Text('Drop-off: ${order.address}', style: _body),
                    if (order.dispatchWave != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Dispatch wave ${order.dispatchWave}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: widget.accepting ? null : widget.onDecline,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Color(0xFF475569)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: RideAccentButton(
                            label: 'Accept ride',
                            loading: widget.accepting,
                            onPressed: widget.onAccept,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  static const _body = TextStyle(color: Colors.white70, fontSize: 14, height: 1.35);
}
