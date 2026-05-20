import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/order.dart';
import 'theme.dart';
import 'trip_call_sheet.dart';
import 'trip_chat_sheet.dart';

const _contactStatuses = {'pending', 'preparing', 'ready', 'picked_up', 'arrived'};

bool tripAllowsContact(Order order) {
  if (order.riderId == null || order.riderId!.isEmpty) return false;
  return _contactStatuses.contains(order.status);
}

String? normalizePhone(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 9) return null;
  if (trimmed.startsWith('+')) return trimmed;
  if (digits.startsWith('233')) return '+$digits';
  if (digits.startsWith('0')) return '+233${digits.substring(1)}';
  return trimmed;
}

Uri? phoneDialUri(String? phone) {
  final normalized = normalizePhone(phone);
  if (normalized == null) return null;
  final digits = normalized.replaceAll(RegExp(r'\D'), '');
  return Uri(scheme: 'tel', path: digits);
}

Uri? smsUri(String? phone) {
  final normalized = normalizePhone(phone);
  if (normalized == null) return null;
  final digits = normalized.replaceAll(RegExp(r'\D'), '');
  return Uri(scheme: 'sms', path: digits);
}

Future<bool> launchPhoneCall(String? phone) async {
  final uri = phoneDialUri(phone);
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<bool> launchSms(String? phone) async {
  final uri = smsUri(phone);
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Call, SMS, and in-app chat during an active trip.
class TripContactActions extends StatelessWidget {
  const TripContactActions({
    super.key,
    required this.order,
    this.phone,
    this.label = 'Contact',
    this.chatTitle = 'Trip chat',
    this.compact = false,
  });

  final Order order;
  final String? phone;
  final String label;
  final String chatTitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final normalized = normalizePhone(phone);
    final hasPhone = normalized != null;

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasPhone) ...[
            IconButton.filled(
              tooltip: 'In-app call',
              onPressed: () => showTripCallSheet(
                context,
                order: order,
                phone: normalized,
                contactLabel: label,
              ),
              icon: const Icon(Icons.phone, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: BytzGoTheme.brandBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size(40, 40),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: 'Text (SMS)',
              onPressed: () => launchSms(normalized),
              icon: const Icon(Icons.sms_outlined, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: BytzGoTheme.sheetDivider,
                foregroundColor: BytzGoTheme.sheetText,
                minimumSize: const Size(40, 40),
              ),
            ),
            const SizedBox(width: 6),
          ],
          IconButton.filled(
            tooltip: 'Chat',
            onPressed: () => showTripChatSheet(context, order: order, title: chatTitle),
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            style: IconButton.styleFrom(
              backgroundColor: BytzGoTheme.accent,
              foregroundColor: const Color(0xFF020617),
              minimumSize: const Size(40, 40),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: BytzGoTheme.sheetBody(12).copyWith(
            fontWeight: FontWeight.w700,
            color: BytzGoTheme.sheetMuted,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (hasPhone) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showTripCallSheet(
                    context,
                    order: order,
                    phone: normalized,
                    contactLabel: label,
                  ),
                  icon: const Icon(Icons.phone, size: 18),
                  label: const Text('Call'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BytzGoTheme.sheetText,
                    side: const BorderSide(color: BytzGoTheme.sheetDivider),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => launchSms(normalized),
                  icon: const Icon(Icons.sms_outlined, size: 18),
                  label: const Text('Text'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BytzGoTheme.sheetText,
                    side: const BorderSide(color: BytzGoTheme.sheetDivider),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: FilledButton.icon(
                onPressed: () =>
                    showTripChatSheet(context, order: order, title: chatTitle),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Chat'),
                style: FilledButton.styleFrom(
                  backgroundColor: BytzGoTheme.brandBlue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
