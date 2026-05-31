import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/trip_chat_unread.dart';

import '../../core/session.dart';
import '../../models/order.dart';
import '../../shared/customer_trip.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../models/location_point.dart';
import '../../shared/delivery_pricing.dart';
import '../../shared/widgets/biker_search_radar.dart';
import '../../shared/widgets/bolt_eta_pill.dart';
import '../../shared/trip_contact.dart';
import '../../shared/pulse_guide.dart';
import '../../shared/widgets/pulse_guide_button.dart';
import '../../shared/widgets/ride_ui.dart';
import '../../shared/driver_tier.dart';
import '../orders/orders_repository.dart';
import '../wallet/wallet_repository.dart';

/// Live delivery status timeline + pay-at-arrival + PIN reveal.
class CustomerDeliveryTracker extends StatelessWidget {
  const CustomerDeliveryTracker({
    super.key,
    required this.order,
    required this.onOrderUpdated,
    this.etaPhrase,
    this.etaMinutes,
    this.etaDistanceText,
    this.etaExpiresAt,
    this.pickupLabel,
    this.dropoffLabel,
    this.riderPosition,
    this.navTarget,
    this.searching = false,
    this.nearbyCount = 0,
    this.omitPayment = false,
    this.mapHudActive = false,
  });

  final Order order;
  final ValueChanged<Order> onOrderUpdated;
  final String? etaPhrase;
  final int? etaMinutes;
  final String? etaDistanceText;
  final DateTime? etaExpiresAt;
  final String? pickupLabel;
  final String? dropoffLabel;
  final LocationPoint? riderPosition;
  final LocationPoint? navTarget;
  final bool searching;
  final int nearbyCount;
  /// Payment card is pinned in the sheet footer during the arrived phase.
  final bool omitPayment;
  /// Status HUD on the map — hide duplicate hero blocks in the sheet.
  final bool mapHudActive;

  double? get _riderDistanceKm {
    if (riderPosition == null || navTarget == null) return null;
    if (!riderPosition!.hasCoords || !navTarget!.hasCoords) return null;
    return haversineDistanceKm(
      riderPosition!.lat,
      riderPosition!.lng,
      navTarget!.lat,
      navTarget!.lng,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (order.status == 'cancelled') {
      return const _CancelledTripBanner();
    }
    if (order.status == 'delivered') {
      return RateDriverCard(order: order, onOrderUpdated: onOrderUpdated);
    }
    if (order.status == 'arrived') {
      return _ArrivedTrackingBody(
        order: order,
        onOrderUpdated: onOrderUpdated,
        omitPayment: omitPayment,
      );
    }
    return _InTransitTrackingBody(
      order: order,
      onOrderUpdated: onOrderUpdated,
      searching: searching,
      nearbyCount: nearbyCount,
      mapHudActive: mapHudActive,
      etaPhrase: etaPhrase,
      etaMinutes: etaMinutes,
      etaDistanceText: etaDistanceText,
      etaExpiresAt: etaExpiresAt,
    );
  }
}

/// Compact in-transit sheet — progress dots + contact only (status lives on the map HUD).
class _InTransitTrackingBody extends StatelessWidget {
  const _InTransitTrackingBody({
    required this.order,
    required this.onOrderUpdated,
    required this.searching,
    required this.nearbyCount,
    required this.mapHudActive,
    this.etaPhrase,
    this.etaMinutes,
    this.etaDistanceText,
    this.etaExpiresAt,
  });

  final Order order;
  final ValueChanged<Order> onOrderUpdated;
  final bool searching;
  final int nearbyCount;
  final bool mapHudActive;
  final String? etaPhrase;
  final int? etaMinutes;
  final String? etaDistanceText;
  final DateTime? etaExpiresAt;

  @override
  Widget build(BuildContext context) {
    final showEta = !searching &&
        order.riderId != null &&
        (etaExpiresAt != null || etaMinutes != null || etaPhrase != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CompactTripProgressBar(order: order, searching: searching),
        if (showEta) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              if (etaExpiresAt != null || etaMinutes != null)
                BoltEtaPill(
                  minutes: etaMinutes,
                  expiresAt: etaExpiresAt,
                  subtitle: etaDistanceText,
                  compact: true,
                  label: 'route ETA',
                )
              else if (etaPhrase != null && etaPhrase!.isNotEmpty)
                Expanded(
                  child: Text(
                    etaPhrase!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: BytzGoTheme.brandBlue,
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (tripAllowsContact(order)) ...[
          const SizedBox(height: 10),
          _CompactContactRow(order: order),
        ],
        if (orderAllowsPulseGuide(order)) ...[
          const SizedBox(height: 8),
          PulseGuideButton(
            order: order,
            onOrderUpdated: onOrderUpdated,
          ),
        ],
        if (customerCanCancelOrder(order)) ...[
          const SizedBox(height: 8),
          CustomerCancelRequestButton(
            order: order,
            onOrderUpdated: onOrderUpdated,
          ),
        ],
      ],
    );
  }
}

/// Arrived phase — slim body; payment is pinned in the sheet footer.
class _ArrivedTrackingBody extends StatelessWidget {
  const _ArrivedTrackingBody({
    required this.order,
    required this.onOrderUpdated,
    required this.omitPayment,
  });

  final Order order;
  final ValueChanged<Order> onOrderUpdated;
  final bool omitPayment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CompactTripProgressBar(order: order),
        const SizedBox(height: 10),
        if (tripAllowsContact(order)) _CompactContactRow(order: order),
        if (!omitPayment) ...[
          const SizedBox(height: 12),
          CustomerTripPaymentCard(
            order: order,
            onOrderUpdated: onOrderUpdated,
          ),
        ],
      ],
    );
  }
}

class _CompactContactRow extends StatelessWidget {
  const _CompactContactRow({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
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
              order.riderName != null && order.riderName!.isNotEmpty
                  ? order.riderName!
                  : 'Your biker',
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
              phone: order.riderPhone,
              label: 'Contact',
              chatTitle: order.riderName != null && order.riderName!.isNotEmpty
                  ? 'Chat with ${order.riderName}'
                  : 'Chat with your biker',
              compact: true,
              unreadCount: unread.countFor(order.id),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal progress only — no vertical timeline (saves ~120px of sheet height).
class CompactTripProgressBar extends StatelessWidget {
  const CompactTripProgressBar({
    super.key,
    required this.order,
    this.searching = false,
  });

  final Order order;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final steps = customerTripSteps(order);
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
              child: _AnimatedProgressSegment(
                active: step.active,
                pulse: searching && step.current,
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
              child: const Text(
                'LIVE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
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

/// Live shop pickup status — rider at vendor before delivery leg.
class _ShopPickupUpdateBanner extends StatelessWidget {
  const _ShopPickupUpdateBanner({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final shop = customerShopLabel(order);
    final pickedUp = order.status == 'picked_up';
    final headingToShop = !pickedUp &&
        order.riderId != null &&
        const {'ready', 'preparing', 'pending'}.contains(order.status);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pickedUp
            ? BytzGoTheme.accent.withValues(alpha: 0.14)
            : BytzGoTheme.brandBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: pickedUp
              ? BytzGoTheme.accent.withValues(alpha: 0.4)
              : BytzGoTheme.brandBlue.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            pickedUp ? Icons.check_circle_outline : Icons.storefront_outlined,
            size: 22,
            color: pickedUp ? BytzGoTheme.accentDark : BytzGoTheme.brandBlue,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pickedUp ? 'Picked up from shop' : 'Rider collecting at shop',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: BytzGoTheme.sheetText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  pickedUp
                      ? 'Your order was collected at $shop. Track the rider on the map — they are heading to you.'
                      : headingToShop
                          ? 'Your rider is on the way to $shop to pick up your items. You will get another update when they leave the shop.'
                          : 'Shop pickup in progress at $shop.',
                  style: BytzGoTheme.sheetBody(12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveMapHint extends StatelessWidget {
  const _LiveMapHint({
    required this.searching,
    required this.hasRider,
    required this.nearbyCount,
    this.distanceKm,
  });

  final bool searching;
  final bool hasRider;
  final int nearbyCount;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            BytzGoTheme.sheetText,
            BytzGoTheme.sheetText.withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            searching ? Icons.radar : Icons.map,
            color: searching ? BytzGoTheme.accent : BytzGoTheme.brandBlueBright,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  searching
                      ? 'Radar scan active'
                      : hasRider
                          ? 'Live biker on map'
                          : 'Track on map above',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  searching
                      ? (nearbyCount > 0
                          ? '$nearbyCount biker${nearbyCount == 1 ? '' : 's'} visible on radar'
                          : 'Pinging nearby riders…')
                      : hasRider && distanceKm != null
                          ? '${distanceKm!.toStringAsFixed(1)} km away — orange pin is your biker'
                          : 'Pinch the map · tap ↻ to re-center',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (searching)
            const BikerSearchRadar(size: 36, color: BytzGoTheme.accent)
          else if (hasRider)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.two_wheeler, color: Colors.orange, size: 22),
            ),
        ],
      ),
    );
  }
}

class _RiderLiveCard extends StatelessWidget {
  const _RiderLiveCard({
    required this.order,
    this.distanceKm,
    this.etaPhrase,
    this.etaMinutes,
    this.etaDistanceText,
    this.etaExpiresAt,
  });

  final Order order;
  final double? distanceKm;
  final String? etaPhrase;
  final int? etaMinutes;
  final String? etaDistanceText;
  final DateTime? etaExpiresAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BytzGoTheme.brandBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BytzGoTheme.brandBlue.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.5), width: 2),
            ),
            child: const Icon(Icons.two_wheeler, color: Colors.orange, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.riderName ?? 'Your biker',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: BytzGoTheme.sheetText,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: DriverTierBadge(
                    tier: driverTierForOrder(order),
                    avgRating: order.riderAvgRating,
                    ratingCount: order.riderRatingCount,
                    compact: true,
                  ),
                ),
                const SizedBox(height: 4),
                if (distanceKm != null)
                  Text(
                    '${distanceKm!.toStringAsFixed(1)} km · approaching on radar',
                    style: BytzGoTheme.sheetBody(12),
                  )
                else if (etaPhrase != null && etaPhrase!.isNotEmpty)
                  Text(etaPhrase!, style: BytzGoTheme.sheetBody(12)),
              ],
            ),
          ),
          if (etaExpiresAt != null || etaMinutes != null)
            BoltEtaPill(
              minutes: etaMinutes,
              expiresAt: etaExpiresAt,
              subtitle: etaDistanceText,
              compact: true,
              label: 'to arrival',
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'LIVE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AddressSummary extends StatelessWidget {
  const _AddressSummary({this.pickup, this.dropoff});

  final String? pickup;
  final String? dropoff;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pickup != null && pickup!.trim().isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                pickupDot(),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pickup!,
                    style: BytzGoTheme.sheetBody(12),
                  ),
                ),
              ],
            ),
          if (pickup != null &&
              dropoff != null &&
              pickup!.trim().isNotEmpty &&
              dropoff!.trim().isNotEmpty)
            const SizedBox(height: 8),
          if (dropoff != null && dropoff!.trim().isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                dropoffSquare(),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dropoff!,
                    style: BytzGoTheme.sheetBody(12),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({
    required this.order,
    this.etaPhrase,
    this.etaMinutes,
    this.etaDistanceText,
    this.etaExpiresAt,
    this.distanceKm,
    this.searching = false,
  });

  final Order order;
  final String? etaPhrase;
  final int? etaMinutes;
  final String? etaDistanceText;
  final DateTime? etaExpiresAt;
  final double? distanceKm;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final headline = customerTripHeadline(order);
    final sub = customerTripSubline(order, etaPhrase: etaPhrase);
    final isArrived = order.status == 'arrived';
    final isDelivered = order.status == 'delivered';
    final isSearching = searching || customerIsSearchingBiker(order);
    final showEta = !isSearching &&
        order.riderId != null &&
        (etaExpiresAt != null || etaMinutes != null);

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showEta) ...[
            Center(
              child: BoltEtaPill(
                minutes: etaMinutes,
                expiresAt: etaExpiresAt,
                subtitle: etaDistanceText ?? etaPhrase,
                label: 'until biker arrives',
              ),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: BytzGoTheme.sheetBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: isSearching
                    ? const BikerSearchRadar(size: 44, color: BytzGoTheme.brandBlue)
                    : Icon(
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
                    if (sub.isNotEmpty && !showEta) ...[
                      const SizedBox(height: 4),
                      Text(sub, style: BytzGoTheme.sheetBody(13)),
                    ],
                    if (distanceKm != null && order.riderId != null && !isSearching) ...[
                      const SizedBox(height: 6),
                      Text(
                        'On radar · ${distanceKm!.toStringAsFixed(1)} km to ${order.status == 'picked_up' ? 'you' : (customerOrderHasShopPickup(order) ? 'shop' : 'pickup')}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: BytzGoTheme.brandBlue,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
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
    final searching = customerIsSearchingBiker(order);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: List.generate(steps.length, (i) {
            final active = steps[i].active;
            final current = steps[i].current;
            return Expanded(
              child: _AnimatedProgressSegment(
                active: active,
                pulse: searching && current,
                marginRight: i < steps.length - 1 ? 4 : 0,
              ),
            );
          }),
        ),
        const SizedBox(height: 14),
        ...steps.map((step) => _TimelineRow(step: step, searching: searching)),
      ],
    );
  }
}

class _AnimatedProgressSegment extends StatefulWidget {
  const _AnimatedProgressSegment({
    required this.active,
    required this.pulse,
    required this.marginRight,
  });

  final bool active;
  final bool pulse;
  final double marginRight;

  @override
  State<_AnimatedProgressSegment> createState() => _AnimatedProgressSegmentState();
}

class _AnimatedProgressSegmentState extends State<_AnimatedProgressSegment>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.pulse) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _AnimatedProgressSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.pulse) {
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
        final glow = widget.pulse ? 0.55 + _ctrl.value * 0.45 : 1.0;
        return Container(
          height: 4,
          margin: EdgeInsets.only(right: widget.marginRight),
          decoration: BoxDecoration(
            color: widget.active
                ? BytzGoTheme.accent.withValues(alpha: glow)
                : BytzGoTheme.sheetDivider,
            borderRadius: BorderRadius.circular(2),
            boxShadow: widget.pulse
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

class _TimelineRow extends StatefulWidget {
  const _TimelineRow({required this.step, required this.searching});

  final CustomerTripStep step;
  final bool searching;

  @override
  State<_TimelineRow> createState() => _TimelineRowState();
}

class _TimelineRowState extends State<_TimelineRow> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.step.current && widget.searching) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _TimelineRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.step.current && widget.searching) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.reset();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final scale = step.current && widget.searching
                  ? 1 + _pulse.value * 0.12
                  : 1.0;
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
            child: Container(
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
              child: step.current && widget.searching
                  ? const Padding(
                      padding: EdgeInsets.all(4),
                      child: BikerSearchRadar(size: 20, showIcon: false),
                    )
                  : Icon(
                      step.active ? Icons.check : Icons.circle_outlined,
                      size: step.active ? 16 : 14,
                      color: step.active
                          ? (step.current ? BytzGoTheme.accentOn : BytzGoTheme.accentDark)
                          : BytzGoTheme.sheetMuted,
                    ),
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
    this.pinned = false,
  });

  final Order order;
  final ValueChanged<Order> onOrderUpdated;
  /// Pinned sheet footer — tighter layout, always visible without scrolling.
  final bool pinned;

  @override
  State<CustomerTripPaymentCard> createState() => _CustomerTripPaymentCardState();
}

class _CustomerTripPaymentCardState extends State<CustomerTripPaymentCard> {
  final _referenceCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _showMomo = false;

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
    final pinned = widget.pinned;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(pinned ? 18 : 20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: showPay
              ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
              : [BytzGoTheme.accent.withValues(alpha: 0.12), BytzGoTheme.sheetBg],
        ),
        border: Border.all(
          color: showPay
              ? BytzGoTheme.accent.withValues(alpha: 0.45)
              : BytzGoTheme.accent.withValues(alpha: 0.35),
        ),
        boxShadow: showPay
            ? [
                BoxShadow(
                  color: BytzGoTheme.accent.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      padding: EdgeInsets.all(pinned ? 14 : 16),
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
                  color: showPay
                      ? BytzGoTheme.accent.withValues(alpha: 0.2)
                      : BytzGoTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  showPay ? Icons.lock_open_rounded : Icons.key_rounded,
                  color: showPay ? BytzGoTheme.accent : BytzGoTheme.accentDark,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showPay ? 'Driver arrived — pay to unlock PIN' : 'Share your delivery PIN',
                      style: TextStyle(
                        fontSize: pinned ? 14 : 15,
                        fontWeight: FontWeight.w900,
                        color: showPay ? Colors.white : BytzGoTheme.sheetText,
                        height: 1.2,
                      ),
                    ),
                    if (showPay) ...[
                      const SizedBox(height: 4),
                      Text(
                        formatCedis(order.total),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: BytzGoTheme.accent,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (showPay) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _PayMethodTile(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Wallet',
                    sub: formatCedis(user.balance),
                    enabled: !_loading && user.balance >= order.total,
                    primary: true,
                    onTap: user.balance < order.total
                        ? null
                        : () => _run(
                              () => context
                                  .read<OrdersRepository>()
                                  .payAtDeliveryWallet(order.id),
                            ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PayMethodTile(
                    icon: Icons.payments_outlined,
                    label: 'Cash',
                    sub: 'To driver',
                    enabled: !_loading,
                    onTap: () => _run(
                          () => context
                              .read<OrdersRepository>()
                              .ackCashPayment(order.id),
                        ),
                  ),
                ),
              ],
            ),
            if (user.balance < order.total) ...[
              const SizedBox(height: 6),
              Text(
                'Wallet low — use cash or MoMo below',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.65),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loading ? null : () => setState(() => _showMomo = !_showMomo),
              icon: Icon(
                _showMomo ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              label: Text(
                'Pay with MoMo / card',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
            if (_showMomo) ...[
              TextField(
                controller: _referenceCtrl,
                enabled: !_loading,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Paste payment reference',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
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
                  icon: const Icon(Icons.credit_card, size: 18),
                  label: const Text('Confirm MoMo / card'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
          if (showPin && code != null && code.length == 6) ...[
            if (showPay) ...[
              const SizedBox(height: 12),
              Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
              const SizedBox(height: 12),
            ],
            Text(
              'Delivery PIN',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: showPay ? Colors.white70 : BytzGoTheme.accentDark,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: code.split('').map((d) {
                return Container(
                  width: pinned ? 38 : 44,
                  height: pinned ? 46 : 52,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: showPay ? Colors.white : BytzGoTheme.sheetText,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: BytzGoTheme.accent.withValues(alpha: 0.55),
                      width: 2,
                    ),
                  ),
                  child: Text(
                    d,
                    style: TextStyle(
                      fontSize: pinned ? 20 : 24,
                      fontWeight: FontWeight.w900,
                      color: BytzGoTheme.accent,
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _copyPin(code),
              icon: Icon(Icons.copy, size: 16, color: showPay ? Colors.white70 : BytzGoTheme.accentDark),
              label: Text(
                'Copy PIN',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: showPay ? Colors.white70 : BytzGoTheme.accentDark,
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
                color: showPay ? const Color(0xFFFCA5A5) : BytzGoTheme.danger,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: BytzGoTheme.accent),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PayMethodTile extends StatelessWidget {
  const _PayMethodTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
    this.enabled = true,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback? onTap;
  final bool enabled;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary
          ? BytzGoTheme.accent
          : Colors.white.withValues(alpha: enabled ? 0.1 : 0.05),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Icon(
                icon,
                size: 22,
                color: primary
                    ? const Color(0xFF020617)
                    : Colors.white.withValues(alpha: enabled ? 0.9 : 0.4),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: primary
                      ? const Color(0xFF020617)
                      : Colors.white.withValues(alpha: enabled ? 0.95 : 0.4),
                ),
              ),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: primary
                      ? const Color(0xFF020617).withValues(alpha: 0.65)
                      : Colors.white.withValues(alpha: 0.55),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerCancelRequestButton extends StatefulWidget {
  const CustomerCancelRequestButton({
    super.key,
    required this.order,
    required this.onOrderUpdated,
  });

  final Order order;
  final ValueChanged<Order> onOrderUpdated;

  @override
  State<CustomerCancelRequestButton> createState() =>
      _CustomerCancelRequestButtonState();
}

class _CustomerCancelRequestButtonState extends State<CustomerCancelRequestButton> {
  bool _loading = false;

  Future<void> _confirmAndCancel() async {
    final order = widget.order;
    final shortId = order.id.length > 6 ? order.id.substring(order.id.length - 6) : order.id;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: BytzGoTheme.sheetTheme(),
        child: AlertDialog(
        title: const Text('Cancel request?'),
        content: Text(
          order.riderId != null
              ? 'Your biker will be notified. Trip #$shortId will be cancelled.'
              : 'Stop searching for a biker and cancel trip #$shortId?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep trip'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: BytzGoTheme.danger),
            child: const Text('Cancel request'),
          ),
        ],
      ),
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _loading = true);
    HapticFeedback.mediumImpact();
    try {
      final result =
          await context.read<OrdersRepository>().cancelOrder(order.id);
      if (!mounted) return;
      widget.onOrderUpdated(result.order);
      if (result.walletBalance != null) {
        context.read<Session>().patchBalance(result.walletBalance!);
      }
      final msg = result.refundMessage ??
          (result.refundCredited
              ? 'Refund credited to your wallet'
              : 'Trip cancelled');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          backgroundColor: result.refundCredited
              ? BytzGoTheme.accentDark
              : BytzGoTheme.sheetText,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(OrdersRepository.errorMessage(e)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: BytzGoTheme.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _loading ? null : _confirmAndCancel,
      icon: _loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.close_rounded, size: 20),
      label: Text(_loading ? 'Cancelling…' : 'Cancel request'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        foregroundColor: BytzGoTheme.danger,
        side: BorderSide(color: BytzGoTheme.danger.withValues(alpha: 0.45)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _CancelledTripBanner extends StatelessWidget {
  const _CancelledTripBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetMuted.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BytzGoTheme.sheetMuted.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.cancel_outlined, color: BytzGoTheme.sheetMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'This trip was cancelled. Pull down to refresh or book a new ride.',
              style: BytzGoTheme.sheetBody(13),
            ),
          ),
        ],
      ),
    );
  }
}

class RateDriverCard extends StatefulWidget {
  const RateDriverCard({
    super.key,
    required this.order,
    required this.onOrderUpdated,
  });

  final Order order;
  final ValueChanged<Order> onOrderUpdated;

  @override
  State<RateDriverCard> createState() => _RateDriverCardState();
}

class _RateDriverCardState extends State<RateDriverCard> {
  int _stars = 0;
  bool _submitting = false;
  String? _error;
  final _commentCtrl = TextEditingController();

  bool get _alreadyRated => (widget.order.rating ?? 0) > 0;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars < 1) {
      setState(() => _error = 'Tap a star to rate your driver');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final comment = _commentCtrl.text.trim();
      final updated = await context.read<OrdersRepository>().rateOrder(
            orderId: widget.order.id,
            rating: _stars,
            comment: comment.isNotEmpty ? comment : '',
          );
      if (!mounted) return;
      widget.onOrderUpdated(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanks for rating your driver!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: BytzGoTheme.accentDark,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = OrdersRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final given = _alreadyRated ? order.rating! : _stars;
    final driverName = order.riderName != null && order.riderName!.isNotEmpty
        ? order.riderName!
        : 'your driver';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            BytzGoTheme.accent.withValues(alpha: 0.16),
            BytzGoTheme.accent.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BytzGoTheme.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.celebration, color: BytzGoTheme.accentDark, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _alreadyRated ? 'Delivery complete — thank you!' : 'Delivered! Rate $driverName',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: BytzGoTheme.sheetText,
                  ),
                ),
              ),
              if (order.riderId != null)
                DriverTierBadge(
                  tier: driverTierForOrder(order),
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _alreadyRated
                ? 'You rated this trip ${order.rating} of 5 stars.'
                : 'More stars help great drivers reach Gold status.',
            style: BytzGoTheme.sheetBody(12),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < given;
              return GestureDetector(
                onTap: _alreadyRated || _submitting
                    ? null
                    : () => setState(() {
                          _stars = i + 1;
                          _error = null;
                        }),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 40,
                    color: filled ? const Color(0xFFF5B301) : BytzGoTheme.sheetMuted,
                  ),
                ),
              );
            }),
          ),
          if (!_alreadyRated) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _commentCtrl,
              enabled: !_submitting,
              maxLines: 2,
              maxLength: 500,
              style: BytzGoTheme.sheetBody(13),
              decoration: InputDecoration(
                hintText: 'Add a note for your driver (optional)',
                hintStyle: TextStyle(color: BytzGoTheme.sheetMuted, fontSize: 13),
                counterText: '',
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.6),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: BytzGoTheme.accent.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: BytzGoTheme.accent.withValues(alpha: 0.3)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            RidePrimaryButton(
              label: 'Submit rating',
              icon: Icons.send_rounded,
              loading: _submitting,
              onPressed: _stars < 1 ? null : _submit,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: BytzGoTheme.danger,
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
