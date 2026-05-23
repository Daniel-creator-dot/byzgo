import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/support_ticket.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/ride_ui.dart';
import 'support_repository.dart';

class CreateSupportTicketScreen extends StatefulWidget {
  const CreateSupportTicketScreen({super.key});

  @override
  State<CreateSupportTicketScreen> createState() =>
      _CreateSupportTicketScreenState();
}

class _CreateSupportTicketScreenState extends State<CreateSupportTicketScreen> {
  static const _categories = [
    'order',
    'payment',
    'account',
    'delivery',
    'shop',
    'other',
  ];

  String _category = 'order';
  final _subjectCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _orderIdCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _descriptionCtrl.dispose();
    _orderIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final subject = _subjectCtrl.text.trim();
    final description = _descriptionCtrl.text.trim();
    if (subject.isEmpty || description.isEmpty) {
      setState(() => _error = 'Subject and description are required');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await context.read<SupportRepository>().createTicket(
            category: _category,
            subject: subject,
            description: description,
            relatedOrderId: _orderIdCtrl.text.trim().isEmpty
                ? null
                : _orderIdCtrl.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(result.ticket);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = SupportRepository.errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BytzGoTheme.sheetBg,
      appBar: AppBar(
        backgroundColor: BytzGoTheme.sheetBg,
        foregroundColor: BytzGoTheme.sheetText,
        elevation: 0,
        title: const Text(
          'Contact support',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'What do you need help with?',
            style: BytzGoTheme.sheetTitle(16),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categories.map((c) {
              final selected = c == _category;
              return FilterChip(
                label: Text(SupportTicket.categoryLabel(c)),
                selected: selected,
                onSelected: (_) => setState(() => _category = c),
                selectedColor: BytzGoTheme.brandBlue.withValues(alpha: 0.15),
                checkmarkColor: BytzGoTheme.brandBlue,
                labelStyle: TextStyle(
                  color: selected ? BytzGoTheme.brandBlue : BytzGoTheme.sheetText,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _subjectCtrl,
            style: const TextStyle(color: BytzGoTheme.sheetText),
            decoration: _decoration('Short subject'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionCtrl,
            style: const TextStyle(color: BytzGoTheme.sheetText),
            minLines: 4,
            maxLines: 8,
            decoration: _decoration('Describe the issue…'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _orderIdCtrl,
            style: const TextStyle(color: BytzGoTheme.sheetText),
            decoration: _decoration('Order ID (optional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: BytzGoTheme.danger, fontSize: 13),
            ),
          ],
          const SizedBox(height: 24),
          RidePrimaryButton(
            label: _submitting ? 'Submitting…' : 'Start support chat',
            loading: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
          const SizedBox(height: 12),
          Text(
            'You will get a ticket ID and can continue the conversation in-app.',
            style: BytzGoTheme.sheetBody(12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
