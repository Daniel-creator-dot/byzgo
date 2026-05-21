import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/location_service.dart';
import '../../features/orders/orders_repository.dart';
import '../../models/order.dart';
import '../pulse_guide.dart';
import '../theme.dart';

/// Customer activates Pulse Guide™ — live GPS pulse on the rider's map.
class PulseGuideButton extends StatefulWidget {
  const PulseGuideButton({
    super.key,
    required this.order,
    required this.onOrderUpdated,
  });

  final Order order;
  final ValueChanged<Order> onOrderUpdated;

  @override
  State<PulseGuideButton> createState() => _PulseGuideButtonState();
}

class _PulseGuideButtonState extends State<PulseGuideButton>
    with SingleTickerProviderStateMixin {
  bool _sending = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (isPulseGuideActive(widget.order)) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant PulseGuideButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (isPulseGuideActive(widget.order) && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!isPulseGuideActive(widget.order) && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final phase = pulseGuidePhase(widget.order);
    if (phase.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      final loc = context.read<LocationService>();
      final point = await loc.getCurrentLocation();
      if (point == null || !point.hasCoords) {
        throw Exception('Turn on location so Pulse Guide can show your exact spot');
      }
      if (!context.mounted) return;
      final updated = await context.read<OrdersRepository>().activatePulseGuide(
            orderId: widget.order.id,
            lat: point.lat,
            lng: point.lng,
            phase: phase,
          );
      if (!mounted) return;
      widget.onOrderUpdated(updated);
      _pulse.repeat();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            phase == 'pickup'
                ? 'Pulse Guide on — your biker sees your live pickup spot'
                : 'Pulse Guide on — your biker sees exactly where you are',
          ),
          backgroundColor: BytzGoTheme.brandBlue,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(OrdersRepository.errorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = isPulseGuideActive(widget.order);
    final phase = pulseGuidePhase(widget.order);
    if (phase.isEmpty) return const SizedBox.shrink();

    return ScaleTransition(
      scale: active
          ? Tween<double>(begin: 1.0, end: 1.03).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
            )
          : const AlwaysStoppedAnimation(1.0),
      child: Material(
        color: active
            ? const Color(0xFF0F172A)
            : BytzGoTheme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _sending ? null : _activate,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? const Color(0xFFEF4444)
                        : BytzGoTheme.accent,
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.55),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: _sending
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF020617),
                          ),
                        )
                      : Icon(
                          active ? Icons.gps_fixed : Icons.radar,
                          color: active ? Colors.white : const Color(0xFF020617),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        active ? 'Pulse Guide live' : 'Pulse Guide™',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: active ? Colors.white : BytzGoTheme.sheetText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        active
                            ? 'Your biker follows your live GPS — no more "where are you?" calls'
                            : phase == 'pickup'
                                ? 'Flash your real location at pickup — first-of-its-kind live meet pulse'
                                : 'Flash your real location for drop-off — guide your biker to your gate',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: active
                              ? Colors.white.withValues(alpha: 0.75)
                              : BytzGoTheme.sheetMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!active)
                  Icon(
                    Icons.chevron_right,
                    color: BytzGoTheme.sheetMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
