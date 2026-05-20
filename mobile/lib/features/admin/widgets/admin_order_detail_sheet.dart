import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/places_service.dart';
import '../../../models/order.dart';
import '../../../shared/customer_trip.dart';
import '../../../shared/format.dart';
import '../../../shared/ghana_location.dart';
import '../../../shared/rider_trip.dart';
import '../../../shared/theme.dart';
import '../../../shared/trip_contact.dart';
import '../../customer/customer_trip_tracking.dart';

/// Full trip breakdown when admin taps an order in the Operations list.
Future<void> showAdminOrderDetailSheet(
  BuildContext context, {
  required Order order,
  ValueChanged<Order>? onOrderUpdated,
  VoidCallback? onViewRiderOnMap,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AdminOrderDetailSheet(
      order: order,
      onOrderUpdated: onOrderUpdated,
      onViewRiderOnMap: onViewRiderOnMap,
    ),
  );
}

class _AdminOrderDetailSheet extends StatefulWidget {
  const _AdminOrderDetailSheet({
    required this.order,
    this.onOrderUpdated,
    this.onViewRiderOnMap,
  });

  final Order order;
  final ValueChanged<Order>? onOrderUpdated;
  final VoidCallback? onViewRiderOnMap;

  @override
  State<_AdminOrderDetailSheet> createState() => _AdminOrderDetailSheetState();
}

class _AdminOrderDetailSheetState extends State<_AdminOrderDetailSheet> {
  late Order _order;
  String? _pickupLabel;
  String? _dropoffLabel;
  bool _resolving = true;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _resolveLabels();
  }

  Future<void> _resolveLabels() async {
    final places = context.read<PlacesService>();
    String pickup = _order.pickupAddress?.trim().isNotEmpty == true
        ? _order.pickupAddress!.trim()
        : (_order.pickup?.trim() ?? '');
    String drop = _order.address.trim();

    if (_order.pickupLat != null &&
        _order.pickupLng != null &&
        hasValidCoords(_order.pickupLat!, _order.pickupLng!)) {
      pickup = await places.resolveAddressLabel(
        _order.pickupLat!,
        _order.pickupLng!,
        existing: pickup,
      );
    } else if (pickup.isNotEmpty) {
      pickup = displayLocationLabel(pickup, 0, 0);
    }

    if (_order.lat != null &&
        _order.lng != null &&
        hasValidCoords(_order.lat!, _order.lng!)) {
      drop = await places.resolveAddressLabel(
        _order.lat!,
        _order.lng!,
        existing: drop,
      );
    } else {
      drop = displayLocationLabel(drop, _order.lat ?? 0, _order.lng ?? 0);
    }

    if (!mounted) return;
    setState(() {
      _pickupLabel = pickup.isNotEmpty ? pickup : null;
      _dropoffLabel = drop.isNotEmpty ? drop : null;
      _resolving = false;
    });
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'delivered':
        return BytzGoTheme.accent;
      case 'cancelled':
        return BytzGoTheme.danger;
      case 'arrived':
        return const Color(0xFF34D399);
      case 'picked_up':
        return BytzGoTheme.brandBlueBright;
      case 'ready':
        return const Color(0xFFFBBF24);
      case 'preparing':
        return const Color(0xFFA78BFA);
      default:
        return const Color(0xFFFBBF24);
    }
  }

  Future<void> _copyId() async {
    await Clipboard.setData(ClipboardData(text: _order.id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Order ID copied'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openMaps(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final statusColor = _statusColor(_order.status);
    final shortId = _order.id.length > 8
        ? _order.id.substring(_order.id.length - 8)
        : _order.id;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0B1220),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: Color(0xFF1E293B))),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TRIP DETAILS',
                            style: TextStyle(
                              color: BytzGoTheme.accent.withValues(alpha: 0.9),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '#$shortId',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _copyId,
                      icon: const Icon(Icons.copy_outlined,
                          color: Colors.white54, size: 22),
                      tooltip: 'Copy full order ID',
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottom),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            statusColor.withValues(alpha: 0.22),
                            statusColor.withValues(alpha: 0.06),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _order.status.toUpperCase(),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  customerTripHeadline(_order),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (customerTripSubline(_order).isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    customerTripSubline(_order),
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.55),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Text(
                            formatCedis(_order.total),
                            style: const TextStyle(
                              color: BytzGoTheme.accent,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionTitle('Progress'),
                    const SizedBox(height: 10),
                    DeliveryProgressTimeline(order: _order),
                    const SizedBox(height: 20),
                    _SectionTitle('Route'),
                    const SizedBox(height: 10),
                    if (_resolving)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: BytzGoTheme.accent,
                            ),
                          ),
                        ),
                      )
                    else ...[
                      if (_pickupLabel != null)
                        _LocationRow(
                          icon: Icons.trip_origin,
                          iconColor: BytzGoTheme.brandBlueBright,
                          label: 'Pickup',
                          value: _pickupLabel!,
                          onMap: _order.pickupLat != null &&
                                  _order.pickupLng != null &&
                                  hasValidCoords(
                                      _order.pickupLat!, _order.pickupLng!)
                              ? () => _openMaps(_order.pickupLat!, _order.pickupLng!)
                              : null,
                        ),
                      if (_pickupLabel != null && _dropoffLabel != null)
                        const SizedBox(height: 10),
                      if (_dropoffLabel != null)
                        _LocationRow(
                          icon: Icons.place,
                          iconColor: BytzGoTheme.accent,
                          label: 'Drop-off',
                          value: _dropoffLabel!,
                          onMap: _order.lat != null &&
                                  _order.lng != null &&
                                  hasValidCoords(_order.lat!, _order.lng!)
                              ? () => _openMaps(_order.lat!, _order.lng!)
                              : null,
                        ),
                    ],
                    const SizedBox(height: 20),
                    _SectionTitle('Customer'),
                    const SizedBox(height: 10),
                    _InfoCard(
                      children: [
                        _DetailRow(
                          label: 'Name',
                          value: _order.customerName.isNotEmpty
                              ? _order.customerName
                              : '—',
                        ),
                        if (_order.customerPhone != null &&
                            _order.customerPhone!.trim().isNotEmpty)
                          _PhoneRow(phone: _order.customerPhone!),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SectionTitle('Driver'),
                    const SizedBox(height: 10),
                    _InfoCard(
                      children: [
                        _DetailRow(
                          label: 'Assigned',
                          value: _order.riderId != null
                              ? (_order.riderName?.isNotEmpty == true
                                  ? _order.riderName!
                                  : 'Rider #${_order.riderId!.length > 6 ? _order.riderId!.substring(_order.riderId!.length - 6) : _order.riderId}')
                              : 'Not assigned yet',
                        ),
                        if (_order.riderPhone != null &&
                            _order.riderPhone!.trim().isNotEmpty)
                          _PhoneRow(phone: _order.riderPhone!),
                        if (_order.riderId != null &&
                            widget.onViewRiderOnMap != null) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                widget.onViewRiderOnMap!();
                              },
                              icon: const Icon(Icons.radar, size: 18),
                              label: const Text('View on live map'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: BytzGoTheme.brandBlueBright,
                                side: BorderSide(
                                  color: BytzGoTheme.brandBlue
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SectionTitle('Payment & order'),
                    const SizedBox(height: 10),
                    _InfoCard(
                      children: [
                        _DetailRow(
                          label: 'Type',
                          value: _order.isCourier
                              ? 'Courier / package'
                              : 'Shop order',
                        ),
                        _DetailRow(
                          label: 'Payment',
                          value: _paymentLabel(),
                        ),
                        if (_order.status == 'cancelled')
                          _DetailRow(
                            label: 'Refund',
                            value: _refundAdminNote(),
                          ),
                        if (_order.deliveryFee != null && _order.deliveryFee! > 0)
                          _DetailRow(
                            label: 'Delivery fee',
                            value: formatCedis(_order.deliveryFee),
                          ),
                        _DetailRow(
                          label: 'Total',
                          value: formatCedis(_order.total),
                        ),
                        if (_order.deliveryCode != null &&
                            _order.deliveryCode!.isNotEmpty)
                          _DetailRow(
                            label: 'Delivery PIN',
                            value: _order.deliveryCode!,
                            mono: true,
                          ),
                        _DetailRow(
                          label: 'Placed',
                          value: _formatPlacedAt(_order.createdAt),
                        ),
                      ],
                    ),
                    if (_order.items.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _SectionTitle('Items (${_order.items.length})'),
                      const SizedBox(height: 10),
                      ..._order.items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _InfoCard(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    formatCedis(item.price * item.quantity),
                                    style: const TextStyle(
                                      color: BytzGoTheme.accent,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'Qty ${item.quantity} · ${formatCedis(item.price)} each',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _refundAdminNote() {
    final status = _order.paymentStatus?.trim() ?? '';
    if (status == 'paid') {
      return 'Prepaid — wallet should be credited on cancel (check wallet_transactions)';
    }
    if (status == 'cash_on_delivery') {
      return 'Pay on delivery — no wallet refund unless customer prepaid';
    }
    return 'Check payment_status & wallet_transactions for customer';
  }

  String _paymentLabel() {
    final method = _order.paymentMethod?.trim();
    final status = _order.paymentStatus?.trim();
    final parts = <String>[];
    if (status != null && status.isNotEmpty) parts.add(status);
    if (method != null && method.isNotEmpty) {
      parts.add(method.replaceAll('_', ' '));
    }
    if (_order.customerPaymentAck != null &&
        _order.customerPaymentAck!.isNotEmpty) {
      parts.add('ack: ${_order.customerPaymentAck}');
    }
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  String _formatPlacedAt(String raw) {
    if (raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final local = dt.toLocal();
    return '${local.day}/${local.month}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.4),
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneRow extends StatelessWidget {
  const _PhoneRow({required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const SizedBox(width: 100),
          Expanded(
            child: Text(
              phone,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: () => launchPhoneCall(phone),
            icon: const Icon(Icons.phone_outlined,
                color: BytzGoTheme.accent, size: 20),
            tooltip: 'Call',
          ),
        ],
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.onMap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback? onMap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (onMap != null)
            IconButton(
              onPressed: onMap,
              icon: const Icon(Icons.map_outlined,
                  color: BytzGoTheme.brandBlueBright, size: 22),
              tooltip: 'Open in Maps',
            ),
        ],
      ),
    );
  }
}
