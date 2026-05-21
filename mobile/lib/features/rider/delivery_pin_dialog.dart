import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/order.dart';
import '../../shared/rider_trip.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/ride_ui.dart';
import '../orders/orders_repository.dart';

class DeliveryPinDialog extends StatefulWidget {
  const DeliveryPinDialog({
    super.key,
    required this.order,
    required this.orders,
    required this.onCompleted,
  });

  final Order order;
  final OrdersRepository orders;
  final VoidCallback onCompleted;

  static Future<void> show(
    BuildContext context, {
    required Order order,
    required OrdersRepository orders,
    required VoidCallback onCompleted,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DeliveryPinDialog(
        order: order,
        orders: orders,
        onCompleted: onCompleted,
      ),
    );
  }

  @override
  State<DeliveryPinDialog> createState() => _DeliveryPinDialogState();
}

class _DeliveryPinDialogState extends State<DeliveryPinDialog> {
  final _controller = TextEditingController();
  bool _submitting = false;
  bool _refreshing = true;
  String? _error;
  late Order _order;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _refreshOrder();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refreshOrder() async {
    try {
      final orders = await widget.orders.fetchOrders();
      final fresh = orders.where((o) => o.id == widget.order.id).firstOrNull;
      if (fresh != null && mounted) {
        setState(() => _order = fresh);
      }
    } catch (_) {
      /* keep passed-in order */
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _submit() async {
    final code = _controller.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit PIN from the customer.');
      return;
    }
    if (_order.status != 'arrived') {
      setState(() => _error = 'Tap "Arrived" on the trip before completing delivery.');
      return;
    }
    if (!isPaymentReady(_order)) {
      setState(() => _error =
          'Customer must confirm payment in the app first (pay or tap "I\'ll pay cash"), then share their PIN.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.orders.completeDelivery(
        orderId: _order.id,
        code: code,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onCompleted();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = formatCompleteError(OrdersRepository.errorMessage(e));
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final paid = order.paymentStatus == 'paid';
    final paymentReady = isPaymentReady(order);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        decoration: BytzGoTheme.sheetDecoration(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Complete delivery', style: BytzGoTheme.sheetTitle()),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Order #${order.id.length > 4 ? order.id.substring(order.id.length - 4) : order.id}',
              style: BytzGoTheme.sheetBody(),
            ),
            if (!paymentReady) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BytzGoTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Waiting for customer payment confirmation before PIN is valid.',
                  style: BytzGoTheme.sheetBody(13),
                ),
              ),
            ] else if (!paid) ...[
              const SizedBox(height: 8),
              Text(
                'Collect cash if needed, then enter the customer PIN.',
                style: BytzGoTheme.sheetBody(13),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                counterText: '',
                hintText: '6-digit PIN',
                filled: true,
                fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 8,
              ),
              textAlign: TextAlign.center,
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            RideAccentButton(
              label: 'Complete delivery',
              loading: _submitting || _refreshing,
              onPressed: _submitting || _refreshing ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
