import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/order.dart';
import 'theme.dart';
import 'trip_contact.dart';

/// Full-screen in-app call UI — connects via the phone network (native dialer).
Future<void> showTripCallSheet(
  BuildContext context, {
  required Order order,
  String? phone,
  String contactLabel = 'Trip contact',
}) async {
  final normalized = normalizePhone(phone);
  if (normalized == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No phone number available for this trip'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _TripCallSheet(
      order: order,
      phone: normalized,
      contactLabel: contactLabel,
    ),
  );
}

class _TripCallSheet extends StatefulWidget {
  const _TripCallSheet({
    required this.order,
    required this.phone,
    required this.contactLabel,
  });

  final Order order;
  final String phone;
  final String contactLabel;

  @override
  State<_TripCallSheet> createState() => _TripCallSheetState();
}

class _TripCallSheetState extends State<_TripCallSheet> {
  bool _calling = false;

  Future<void> _startCall() async {
    setState(() => _calling = true);
    HapticFeedback.mediumImpact();
    final ok = await launchPhoneCall(widget.phone);
    if (!mounted) return;
    setState(() => _calling = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0B1220),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 28),
          CircleAvatar(
            radius: 44,
            backgroundColor: BytzGoTheme.brandBlue.withValues(alpha: 0.2),
            child: const Icon(Icons.person, size: 48, color: BytzGoTheme.brandBlue),
          ),
          const SizedBox(height: 16),
          Text(
            widget.contactLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.phone,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Order #${widget.order.id.substring(0, 8)}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
          ),
          const SizedBox(height: 12),
          Text(
            'Calls use your phone line. Keep the app open for chat and trip updates.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ActionCircle(
                icon: Icons.close,
                label: 'Close',
                color: Colors.white24,
                onTap: () => Navigator.of(context).pop(),
              ),
              _ActionCircle(
                icon: Icons.phone,
                label: _calling ? 'Calling…' : 'Call',
                color: const Color(0xFF22C55E),
                size: 72,
                onTap: _calling ? null : _startCall,
              ),
              _ActionCircle(
                icon: Icons.sms_outlined,
                label: 'Text',
                color: BytzGoTheme.brandBlue,
                onTap: () async {
                  await launchSms(widget.phone);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionCircle extends StatelessWidget {
  const _ActionCircle({
    required this.icon,
    required this.label,
    required this.color,
    this.size = 56,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: Colors.white, size: size * 0.42),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
      ],
    );
  }
}
