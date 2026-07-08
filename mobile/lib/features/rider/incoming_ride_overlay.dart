import 'dart:async';
import 'package:flutter/material.dart';

import '../../models/ride_service.dart';
import '../../models/order.dart';
import '../../models/vendor.dart';
import '../../shared/format.dart';
import '../../shared/rider_trip.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/ride_ui.dart';
import 'incoming_ride_alert.dart';

/// Full-screen incoming call UI (parity with web `IncomingRideCallModal`).
class IncomingRideOverlay extends StatefulWidget {
  const IncomingRideOverlay({
    super.key,
    required this.order,
    required this.vendors,
    required this.onAccept,
    required this.onDecline,
    required this.onOfferExpired,
    this.accepting = false,
  });

  final Order order;
  final List<Vendor> vendors;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  /// Timer ran out — dismiss UI only (server already expired the wave).
  final VoidCallback onOfferExpired;
  final bool accepting;

  @override
  State<IncomingRideOverlay> createState() => _IncomingRideOverlayState();
}

class _IncomingRideOverlayState extends State<IncomingRideOverlay>
    with TickerProviderStateMixin {
  Timer? _tick;
  int? _secs;
  late final AnimationController _pulseCtrl;
  late final AnimationController _phoneCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _phoneCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _syncSecs();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    if (!mounted) return;
    final secs = offerSecondsRemaining(widget.order);
    if (secs != null && secs <= 0) {
      widget.onOfferExpired();
      return;
    }
    setState(() => _secs = secs);
  }

  void _syncSecs() {
    _secs = offerSecondsRemaining(widget.order);
  }

  void _handleDecline() {
    widget.onDecline();
  }

  void _handleAccept() {
    widget.onAccept();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulseCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  String get _pickupLabel {
    final order = widget.order;
    if (order.isCourier) {
      return order.pickupAddress ?? order.pickup ?? 'Pickup location';
    }
    for (final v in widget.vendors) {
      if (v.id == order.vendorId) {
        return v.name.isNotEmpty ? v.name : (v.address ?? 'Vendor pickup');
      }
    }
    return 'Vendor pickup';
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final fee = order.deliveryFee ?? order.total;
    final offerTtl = _secs ?? 30;
    final ringMax = IncomingRideAlert.callRingDuration.inSeconds;

    return ValueListenableBuilder<int>(
      valueListenable: IncomingRideAlert.ringSecondsLeft,
      builder: (context, ringLeft, _) {
        final ringing = ringLeft > 0;
        final progress = ringing
            ? (ringLeft / ringMax).clamp(0.0, 1.0)
            : (offerTtl > 0 ? (offerTtl / 30.0).clamp(0.0, 1.0) : 0.0);

        return Material(
      color: const Color(0xFF020617).withValues(alpha: 0.96),
      child: SafeArea(
        child: Stack(
          children: [
            ...List.generate(3, (i) {
              return AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, _) {
                  final t = (_pulseCtrl.value + i * 0.33) % 1.0;
                  final size = 120.0 + t * 200;
                  return Positioned.fill(
                    child: Center(
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: BytzGoTheme.accent.withValues(alpha: (1 - t) * 0.45),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
            Column(
              children: [
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: Colors.white12,
                  color: BytzGoTheme.accent,
                ),
                const Spacer(),
                ScaleTransition(
                  scale: Tween(begin: 1.0, end: 1.08).animate(
                    CurvedAnimation(parent: _phoneCtrl, curve: Curves.easeInOut),
                  ),
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: BytzGoTheme.accent.withValues(alpha: 0.2),
                      border: Border.all(color: BytzGoTheme.accent, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: BytzGoTheme.accent.withValues(alpha: 0.45),
                          blurRadius: 32,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.phone_in_talk,
                      size: 44,
                      color: BytzGoTheme.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'INCOMING RIDE',
                  style: TextStyle(
                    color: BytzGoTheme.accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  order.isPassengerRide
                      ? '${order.rideServiceLabel} passenger'
                      : (order.isCourier ? 'Courier mission' : 'Delivery pickup'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (order.isPassengerRide &&
                    (order.passengerCount ?? 0) > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${order.passengerCount} passenger${order.passengerCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                if (order.offerDistanceKm != null && order.offerDistanceKm! > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${order.offerDistanceKm!.toStringAsFixed(1)} km to pickup',
                      style: const TextStyle(
                        color: BytzGoTheme.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                Text(
                  ringing
                      ? '#${order.id.length > 6 ? order.id.substring(order.id.length - 6).toUpperCase() : order.id.toUpperCase()} · $ringLeft s ringing'
                      : '#${order.id.length > 6 ? order.id.substring(order.id.length - 6).toUpperCase() : order.id.toUpperCase()} · ${offerTtl}s to answer',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'YOU EARN',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white.withValues(alpha: 0.45),
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatCedis(fee),
                        style: const TextStyle(
                          color: BytzGoTheme.accent,
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _PaymentChip(order: order),
                      const SizedBox(height: 12),
                      _stopRow(Icons.location_on, 'Pickup', _pickupLabel),
                      const SizedBox(height: 12),
                      _stopRow(Icons.navigation, 'Drop-off', order.address),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: widget.accepting ? null : _handleDecline,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Color(0xFF475569)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Decline',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: RideAccentButton(
                          label: 'Accept ride',
                          loading: widget.accepting,
                          onPressed: _handleAccept,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
        );
      },
    );
  }

  Widget _stopRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: BytzGoTheme.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: BytzGoTheme.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.4),
                  letterSpacing: 1,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaymentChip extends StatelessWidget {
  const _PaymentChip({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final paid = order.paymentStatus == 'paid';
    final cod = order.paymentMethod == 'pay_on_delivery' ||
        order.paymentStatus == 'cash_on_delivery';
    final label = paid ? 'Prepaid · collect at drop-off only' : (cod ? 'Cash on delivery' : 'Pay at delivery');
    final color = paid ? BytzGoTheme.accent : BytzGoTheme.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
