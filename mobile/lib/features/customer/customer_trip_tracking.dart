import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../models/order.dart';
import '../../shared/customer_trip.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/ride_ui.dart';
import '../orders/orders_repository.dart';
import '../wallet/wallet_repository.dart';

/// Live delivery status timeline + pay-at-arrival + PIN reveal.
class CustomerDeliveryTracker extends StatelessWidget {
  const CustomerDeliveryTracker({
    super.key,
    required this.order,
    required this.onOrderUpdated,
  });

  final Order order;
  final ValueChanged<Order> onOrderUpdated;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusHero(order: order),
        const SizedBox(height: 16),
        DeliveryProgressTimeline(order: order),
        if (order.status == 'arrived') ...[
          const SizedBox(height: 16),
          CustomerTripPaymentCard(
            order: order,
            onOrderUpdated: onOrderUpdated,
          ),
        ],
        if (order.status == 'delivered') ...[
          const SizedBox(height: 16),
          _DeliveredBanner(),
        ],
      ],
    );
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final headline = customerTripHeadline(order);
    final sub = customerTripSubline(order);
    final isArrived = order.status == 'arrived';
    final isDelivered = order.status == 'delivered';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDelivered
              ? [
                  BytzGoTheme.accent.withValues(alpha: 0.2),
                  BytzGoTheme.accent.withValues(alpha: 0.05),
                ]
              : isArrived
                  ? [
                      BytzGoTheme.warning.withValues(alpha: 0.15),
                      BytzGoTheme.warning.withValues(alpha: 0.04),
                    ]
                  : [
                      BytzGoTheme.brandBlue.withValues(alpha: 0.12),
                      BytzGoTheme.brandBlue.withValues(alpha: 0.04),
                    ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDelivered
              ? BytzGoTheme.accent.withValues(alpha: 0.4)
              : isArrived
                  ? BytzGoTheme.warning.withValues(alpha: 0.35)
                  : BytzGoTheme.brandBlue.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: BytzGoTheme.sheetBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isDelivered
                  ? Icons.check_circle
                  : isArrived
                      ? Icons.place
                      : order.status == 'picked_up'
                          ? Icons.two_wheeler
                          : order.riderId != null
                              ? Icons.person_pin_circle
                              : Icons.radar,
              color: isDelivered
                  ? BytzGoTheme.accentDark
                  : isArrived
                      ? BytzGoTheme.warning
                      : BytzGoTheme.brandBlue,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: BytzGoTheme.sheetText,
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(sub, style: BytzGoTheme.sheetBody(13)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DeliveryProgressTimeline extends StatelessWidget {
  const DeliveryProgressTimeline({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final steps = customerTripSteps(order);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: List.generate(steps.length, (i) {
            final active = steps[i].active;
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i < steps.length - 1 ? 4 : 0),
                decoration: BoxDecoration(
                  color: active ? BytzGoTheme.accent : BytzGoTheme.sheetDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 14),
        ...steps.map((step) => _TimelineRow(step: step)),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.step});

  final CustomerTripStep step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: step.active
                  ? (step.current
                      ? BytzGoTheme.accent
                      : BytzGoTheme.accent.withValues(alpha: 0.2))
                  : BytzGoTheme.sheetDivider.withValues(alpha: 0.5),
              shape: BoxShape.circle,
              border: step.current
                  ? Border.all(color: BytzGoTheme.accentDark, width: 2)
                  : null,
            ),
            child: Icon(
              step.active ? Icons.check : Icons.circle_outlined,
              size: step.active ? 16 : 14,
              color: step.active
                  ? (step.current ? BytzGoTheme.accentOn : BytzGoTheme.accentDark)
                  : BytzGoTheme.sheetMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              step.label,
              style: TextStyle(
                fontWeight: step.current ? FontWeight.w800 : FontWeight.w600,
                fontSize: 14,
                color: step.active ? BytzGoTheme.sheetText : BytzGoTheme.sheetMuted,
              ),
            ),
          ),
          if (step.current)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: BytzGoTheme.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Now',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: BytzGoTheme.accentDark,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CustomerTripPaymentCard extends StatefulWidget {
  const CustomerTripPaymentCard({
    super.key,
    required this.order,
    required this.onOrderUpdated,
  });

  final Order order;
  final ValueChanged<Order> onOrderUpdated;

  @override
  State<CustomerTripPaymentCard> createState() => _CustomerTripPaymentCardState();
}

class _CustomerTripPaymentCardState extends State<CustomerTripPaymentCard> {
  final _referenceCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _referenceCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Order> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final updated = await action();
      if (!mounted) return;
      widget.onOrderUpdated(updated);
      if (updated.paymentStatus == 'paid') {
        try {
          final balance =
              await context.read<WalletRepository>().fetchBalance();
          if (mounted) context.read<Session>().patchBalance(balance);
        } catch (_) {}
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = OrdersRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyPin(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PIN copied'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final user = context.watch<Session>().user!;
    final showPay = customerNeedsPayment(order);
    final showPin = customerCanShowDeliveryPin(order);
    final code = order.deliveryCode;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BytzGoTheme.warning.withValues(alpha: 0.45)),
        color: BytzGoTheme.warning.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showPay ? 'Complete payment' : 'Your delivery PIN',
                  style: BytzGoTheme.sheetTitle(17),
                ),
                const SizedBox(height: 4),
                Text(
                  showPay
                      ? 'Pay ${formatCedis(order.total)} — then give the 6-digit code to your driver.'
                      : 'Tell your driver this code so they can complete the delivery.',
                  style: BytzGoTheme.sheetBody(13),
                ),
              ],
            ),
          ),
          if (showPay) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                formatCedis(order.total),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: BytzGoTheme.sheetText,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: RidePrimaryButton(
                label: 'Pay with wallet',
                icon: Icons.account_balance_wallet_outlined,
                loading: _loading,
                onPressed: user.balance < order.total
                    ? null
                    : () => _run(
                          () => context
                              .read<OrdersRepository>()
                              .payAtDeliveryWallet(order.id),
                        ),
              ),
            ),
            if (user.balance < order.total) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Insufficient balance — top up wallet or use another method',
                  style: BytzGoTheme.sheetBody(12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: _loading
                    ? null
                    : () => _run(
                          () => context
                              .read<OrdersRepository>()
                              .ackCashPayment(order.id),
                        ),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('I\'ll pay cash to driver'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  side: BorderSide(color: BytzGoTheme.warning.withValues(alpha: 0.6)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _referenceCtrl,
                decoration: InputDecoration(
                  labelText: 'MoMo / card payment reference',
                  hintText: 'After paying online',
                  filled: true,
                  fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: _loading
                    ? null
                    : () {
                        final ref = _referenceCtrl.text.trim();
                        if (ref.isEmpty) {
                          setState(() => _error = 'Paste your payment reference');
                          return;
                        }
                        _run(
                          () => context.read<OrdersRepository>().payAtDeliveryReference(
                                orderId: order.id,
                                paymentReference: ref,
                              ),
                        );
                      },
                icon: const Icon(Icons.credit_card),
                label: const Text('Confirm card / MoMo payment'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (showPin && code != null && code.length == 6) ...[
            if (showPay) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.key, size: 18, color: BytzGoTheme.accentDark),
                      const SizedBox(width: 8),
                      Text(
                        'Delivery PIN',
                        style: BytzGoTheme.sheetBody(12).copyWith(
                          fontWeight: FontWeight.w800,
                          color: BytzGoTheme.accentDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: code.split('').map((d) {
                      return Container(
                        width: 44,
                        height: 52,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: BytzGoTheme.sheetText,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: BytzGoTheme.accent.withValues(alpha: 0.5),
                            width: 2,
                          ),
                        ),
                        child: Text(
                          d,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: BytzGoTheme.accent,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  TextButton.icon(
                    onPressed: () => _copyPin(code),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text(
                      'Copy PIN',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: BytzGoTheme.danger,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeliveredBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BytzGoTheme.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BytzGoTheme.accent.withValues(alpha: 0.35)),
      ),
      child: const Row(
        children: [
          Icon(Icons.celebration, color: BytzGoTheme.accentDark),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Delivery complete — thank you!',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: BytzGoTheme.accentDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
