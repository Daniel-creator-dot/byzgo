import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/trip_chat_unread.dart';
import '../../models/order.dart';
import '../../shared/format.dart';
import '../../shared/rider_trip.dart';
import '../../shared/theme.dart';
import '../../shared/trip_contact.dart';
import '../orders/orders_repository.dart';

/// Compact active-trip sheet body — horizontal progress + contact only.
class RiderActiveTripBody extends StatelessWidget {
  const RiderActiveTripBody({
    super.key,
    required this.order,
  });

  final Order order;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        RiderCompactProgressBar(order: order),
        if (tripAllowsContact(order)) ...[
          const SizedBox(height: 10),
          _CompactCustomerRow(order: order),
        ],
      ],
    );
  }
}

class _CompactCustomerRow extends StatelessWidget {
  const _CompactCustomerRow({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final name = order.customerName.isNotEmpty ? order.customerName : 'Customer';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BytzGoTheme.sheetDivider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: BytzGoTheme.sheetText,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Consumer<TripChatUnread>(
            builder: (context, unread, _) => TripContactActions(
              order: order,
              phone: order.customerPhone,
              label: 'Contact',
              chatTitle: 'Chat with $name',
              compact: true,
              unreadCount: unread.countFor(order.id),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal progress only — no vertical timeline.
class RiderCompactProgressBar extends StatelessWidget {
  const RiderCompactProgressBar({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final steps = riderTripSteps(order);
    final current = steps.where((s) => s.current).map((s) => s.label).firstOrNull ??
        steps.lastWhere((s) => s.active, orElse: () => steps.first).label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: List.generate(steps.length, (i) {
            final step = steps[i];
            return Expanded(
              child: _ProgressSegment(
                active: step.active,
                current: step.current,
                marginRight: i < steps.length - 1 ? 3 : 0,
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              current,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: BytzGoTheme.accentDark,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: BytzGoTheme.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                order.status.replaceAll('_', ' ').toUpperCase(),
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: BytzGoTheme.accentDark,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProgressSegment extends StatefulWidget {
  const _ProgressSegment({
    required this.active,
    required this.current,
    required this.marginRight,
  });

  final bool active;
  final bool current;
  final double marginRight;

  @override
  State<_ProgressSegment> createState() => _ProgressSegmentState();
}

class _ProgressSegmentState extends State<_ProgressSegment>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.current) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _ProgressSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.current && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.current) {
      _ctrl.stop();
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final glow = widget.current ? 0.55 + _ctrl.value * 0.45 : 1.0;
        return Container(
          height: 4,
          margin: EdgeInsets.only(right: widget.marginRight),
          decoration: BoxDecoration(
            color: widget.active
                ? BytzGoTheme.accent.withValues(alpha: glow)
                : BytzGoTheme.sheetDivider,
            borderRadius: BorderRadius.circular(2),
            boxShadow: widget.current
                ? [
                    BoxShadow(
                      color: BytzGoTheme.accent.withValues(alpha: 0.35 * _ctrl.value),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

/// Pinned footer — collect payment status + enter PIN to complete delivery.
class RiderDeliveryPinCard extends StatefulWidget {
  const RiderDeliveryPinCard({
    super.key,
    required this.order,
    required this.onCompleted,
    this.pinned = false,
    this.embedded = false,
  });

  final Order order;
  final VoidCallback onCompleted;
  final bool pinned;
  final bool embedded;

  @override
  State<RiderDeliveryPinCard> createState() => _RiderDeliveryPinCardState();
}

class _RiderDeliveryPinCardState extends State<RiderDeliveryPinCard> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit PIN from the customer.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    var order = widget.order;
    try {
      final orders = await context.read<OrdersRepository>().fetchOrders();
      final fresh = orders.where((o) => o.id == order.id).firstOrNull;
      if (fresh != null) order = fresh;
    } catch (_) {}

    if (order.status != 'arrived') {
      if (!mounted) return;
      setState(() {
        _error = 'Tap "I\'ve arrived" before completing delivery.';
        _loading = false;
      });
      return;
    }
    if (!isPaymentReady(order)) {
      if (!mounted) return;
      setState(() {
        _error =
            'Customer must confirm payment in the app first, then share their PIN.';
        _loading = false;
      });
      return;
    }

    try {
      await context.read<OrdersRepository>().completeDelivery(
            orderId: order.id,
            code: code,
          );
      if (!mounted) return;
      widget.onCompleted();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = formatCompleteError(OrdersRepository.errorMessage(e));
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final paymentReady = isPaymentReady(order);
    final paid = order.paymentStatus == 'paid';
    final collectCash = !paid &&
        (order.customerPaymentAck == 'cash' ||
            order.paymentMethod == 'pay_on_delivery' ||
            order.paymentStatus == 'cash_on_delivery');
    final pinned = widget.pinned;
    final embedded = widget.embedded;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(pinned ? 18 : 20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: paymentReady
              ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
              : [BytzGoTheme.warning.withValues(alpha: 0.12), BytzGoTheme.sheetBg],
        ),
        border: Border.all(
          color: paymentReady
              ? BytzGoTheme.accent.withValues(alpha: 0.45)
              : BytzGoTheme.warning.withValues(alpha: 0.35),
        ),
        boxShadow: pinned
            ? [
                BoxShadow(
                  color: BytzGoTheme.accent.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      padding: EdgeInsets.all(pinned ? 14 : (embedded ? 12 : 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: paymentReady
                      ? BytzGoTheme.accent.withValues(alpha: 0.2)
                      : BytzGoTheme.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  paymentReady ? Icons.pin_rounded : Icons.hourglass_top_rounded,
                  color: paymentReady ? BytzGoTheme.accent : BytzGoTheme.warning,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paymentReady
                          ? 'Enter customer PIN'
                          : 'Waiting for customer payment',
                      style: TextStyle(
                        fontSize: pinned ? 14 : 15,
                        fontWeight: FontWeight.w900,
                        color: paymentReady ? Colors.white : BytzGoTheme.sheetText,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatCedis(order.total),
                      style: TextStyle(
                        fontSize: pinned ? 22 : 26,
                        fontWeight: FontWeight.w900,
                        color: paymentReady ? BytzGoTheme.accent : BytzGoTheme.sheetText,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (collectCash && paymentReady)
                      Text(
                        'Collect cash from customer',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (!paymentReady) ...[
            const SizedBox(height: 10),
            Text(
              'Ask the customer to open Activity, pay or tap "I\'ll pay cash", then share their PIN.',
              style: BytzGoTheme.sheetBody(12),
            ),
          ] else ...[
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              enabled: !_loading,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: pinned ? 22 : 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
                color: paymentReady ? Colors.white : BytzGoTheme.sheetText,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '6-digit PIN',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  letterSpacing: 4,
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: FilledButton.icon(
                onPressed: _loading ? null : _submit,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Complete delivery'),
                style: FilledButton.styleFrom(
                  backgroundColor: BytzGoTheme.accent,
                  foregroundColor: const Color(0xFF020617),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: paymentReady ? const Color(0xFFFCA5A5) : BytzGoTheme.danger,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
