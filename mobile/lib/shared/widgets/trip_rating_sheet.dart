import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/orders/orders_repository.dart';
import '../../models/order.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import 'ride_ui.dart';

enum TripRatingSheetMode { customer, rider }

/// Bolt-style delivery success + star rating (customer) or completion (rider).
class TripRatingSheet extends StatefulWidget {
  const TripRatingSheet._({
    required this.order,
    this.orders,
    required this.mode,
    this.onDone,
  });

  final Order order;
  final OrdersRepository? orders;
  final TripRatingSheetMode mode;
  final VoidCallback? onDone;

  static Future<void> showCustomerRating(
    BuildContext context, {
    required Order order,
    required OrdersRepository orders,
    VoidCallback? onDone,
  }) {
    if (order.rating != null && order.rating! > 0) {
      onDone?.call();
      return Future.value();
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => TripRatingSheet._(
        order: order,
        orders: orders,
        mode: TripRatingSheetMode.customer,
        onDone: onDone,
      ),
    );
  }

  static Future<void> showRiderCompletion(
    BuildContext context, {
    required Order order,
    VoidCallback? onDone,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TripRatingSheet._(
        order: order,
        mode: TripRatingSheetMode.rider,
        onDone: onDone,
      ),
    );
  }

  @override
  State<TripRatingSheet> createState() => _TripRatingSheetState();
}

class _TripRatingSheetState extends State<TripRatingSheet> {
  int _stars = 0;
  bool _submitting = false;
  final _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.of(context).pop();
    widget.onDone?.call();
  }

  Future<void> _submitRating() async {
    if (_stars < 1) {
      HapticFeedback.lightImpact();
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.orders!.rateOrder(
        orderId: widget.order.id,
        rating: _stars,
        comment: _commentCtrl.text.trim(),
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _close();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(OrdersRepository.errorMessage(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isCustomer = widget.mode == TripRatingSheetMode.customer;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: BytzGoTheme.sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 32,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: BytzGoTheme.sheetMuted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: BytzGoTheme.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: BytzGoTheme.accentDark,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isCustomer ? 'Delivery complete!' : 'Trip completed!',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: BytzGoTheme.sheetText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isCustomer
                  ? 'How was your trip with ${order.riderName ?? 'your biker'}?'
                  : 'You earned ${formatCedis((order.deliveryFee ?? 0) > 0 ? order.deliveryFee! : order.total)}',
              textAlign: TextAlign.center,
              style: BytzGoTheme.sheetBody(14),
            ),
            if (isCustomer) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final star = i + 1;
                  final filled = star <= _stars;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: IconButton(
                      onPressed: _submitting
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              setState(() => _stars = star);
                            },
                      icon: Icon(
                        filled ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 44,
                        color: filled ? const Color(0xFFFBBF24) : BytzGoTheme.sheetMuted,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _commentCtrl,
                maxLines: 2,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText: 'Add a note for your driver (optional)',
                  counterText: '',
                  filled: true,
                  fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              RidePrimaryButton(
                label: _stars > 0 ? 'Submit rating' : 'Select a rating',
                loading: _submitting,
                onPressed: _stars > 0 && !_submitting ? _submitRating : null,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _submitting ? null : _close,
                child: const Text(
                  'Skip for now',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ] else ...[
              const SizedBox(height: 24),
              RidePrimaryButton(
                label: 'Back to drive',
                icon: Icons.check,
                onPressed: _close,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
