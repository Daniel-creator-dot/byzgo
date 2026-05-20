import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config_repository.dart';
import '../../core/session.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/ride_ui.dart';
import '../../shared/widgets/sheet_theme_scope.dart';
import '../wallet/paystack_checkout_screen.dart';
import '../wallet/wallet_repository.dart';

Future<void> showCustomerWalletSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: BytzGoTheme.sheetBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const SheetThemeScope(child: _CustomerWalletSheet()),
  );
}

class _CustomerWalletSheet extends StatefulWidget {
  const _CustomerWalletSheet();

  @override
  State<_CustomerWalletSheet> createState() => _CustomerWalletSheetState();
}

class _CustomerWalletSheetState extends State<_CustomerWalletSheet> {
  var _tab = 0;
  final _amountCtrl = TextEditingController(text: '50');
  final _referenceCtrl = TextEditingController();
  final _withdrawAmountCtrl = TextEditingController();
  final _withdrawPhoneCtrl = TextEditingController();
  bool _loading = false;
  bool _showManualRef = false;
  String? _message;
  bool _success = false;

  static const _presets = ['20', '50', '100', '200'];

  @override
  void dispose() {
    _amountCtrl.dispose();
    _referenceCtrl.dispose();
    _withdrawAmountCtrl.dispose();
    _withdrawPhoneCtrl.dispose();
    super.dispose();
  }

  double? get _topupAmount {
    final n = double.tryParse(_amountCtrl.text.trim());
    if (n == null || n < 1) return null;
    return n;
  }

  Future<void> _payWithPaystack() async {
    final amount = _topupAmount;
    if (amount == null) {
      setState(() {
        _message = 'Enter at least ₵1 to top up';
        _success = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final publicKey =
          await context.read<ConfigRepository>().fetchPaystackPublicKey();
      if (publicKey.isEmpty || !publicKey.startsWith('pk_')) {
        throw Exception(
          'Paystack is not configured. Ask admin to add keys in Admin → Settings.',
        );
      }

      final wallet = context.read<WalletRepository>();
      final session = await wallet.initializeTopup(amount);
      if (!context.mounted) return;

      final reference = await PaystackCheckoutScreen.open(
        context,
        authorizationUrl: session.authorizationUrl,
        reference: session.reference,
      );

      if (!mounted) return;
      if (reference == null || reference.isEmpty) {
        setState(() {
          _message = 'Payment was not completed';
          _success = false;
        });
        return;
      }

      final balance = await wallet.creditTopup(reference);
      if (!mounted) return;
      context.read<Session>().patchBalance(balance);
      setState(() {
        _success = true;
        _message = 'Wallet topped up — ${formatCedis(balance)} available';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _success = false;
        _message = WalletRepository.errorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _creditTopupManual() async {
    final ref = _referenceCtrl.text.trim();
    if (ref.isEmpty) {
      setState(() {
        _message = 'Paste your Paystack payment reference';
        _success = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final balance =
          await context.read<WalletRepository>().creditTopup(ref);
      if (!mounted) return;
      context.read<Session>().patchBalance(balance);
      setState(() {
        _success = true;
        _message = 'Wallet credited — ${formatCedis(balance)} available';
        _referenceCtrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _success = false;
        _message = WalletRepository.errorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _withdraw() async {
    final amount = double.tryParse(_withdrawAmountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() {
        _message = 'Enter a valid amount';
        _success = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final balance = await context.read<WalletRepository>().withdraw(
            amount: amount,
            phone: _withdrawPhoneCtrl.text.trim(),
          );
      if (!mounted) return;
      context.read<Session>().patchBalance(balance);
      setState(() {
        _success = true;
        _message = 'Withdrawal submitted';
        _withdrawAmountCtrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _success = false;
        _message = WalletRepository.errorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user!;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: BytzGoTheme.sheetDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Wallet', style: BytzGoTheme.sheetTitle(24)),
          const SizedBox(height: 4),
          Text(
            formatCedis(user.balance),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: BytzGoTheme.accentDark,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _tabChip('Top up', 0),
              const SizedBox(width: 8),
              _tabChip('Withdraw', 1),
            ],
          ),
          const SizedBox(height: 16),
          if (_tab == 0) ...[
            Text(
              'Top up with Mobile Money (MTN, Telecel, AirtelTigo) or debit card via Paystack.',
              style: BytzGoTheme.sheetBody(13),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presets.map((val) {
                final selected = _amountCtrl.text.trim() == val;
                return ChoiceChip(
                  label: Text('₵$val'),
                  selected: selected,
                  onSelected: (_) => setState(() => _amountCtrl.text = val),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Amount (GHS)',
                filled: true,
                fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            RidePrimaryButton(
              label: 'Pay with MoMo or Card',
              icon: Icons.payments_outlined,
              loading: _loading,
              onPressed: _payWithPaystack,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _showManualRef = !_showManualRef),
              child: Text(
                _showManualRef ? 'Hide manual reference' : 'Already paid? Paste reference',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: BytzGoTheme.brandBlue,
                ),
              ),
            ),
            if (_showManualRef) ...[
              Text(
                'Only if you already completed Paystack checkout elsewhere.',
                style: BytzGoTheme.sheetBody(12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _referenceCtrl,
                decoration: InputDecoration(
                  labelText: 'Paystack reference',
                  hintText: 'e.g. T1234567890 or bytzgo_…',
                  filled: true,
                  fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _loading ? null : _creditTopupManual,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  side: const BorderSide(color: BytzGoTheme.brandBlue),
                ),
                child: const Text(
                  'Credit wallet',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: BytzGoTheme.brandBlue,
                  ),
                ),
              ),
            ],
          ] else ...[
            TextField(
              controller: _withdrawAmountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Amount (GHS)',
                filled: true,
                fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _withdrawPhoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'MoMo number',
                hintText: user.phone ?? 'e.g. 024XXXXXXX',
                filled: true,
                fillColor: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            RidePrimaryButton(
              label: 'Withdraw',
              icon: Icons.account_balance,
              loading: _loading,
              onPressed: _withdraw,
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              style: TextStyle(
                color: _success ? BytzGoTheme.accentDark : BytzGoTheme.danger,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tabChip(String label, int index) {
    final selected = _tab == index;
    return Expanded(
      child: Material(
        color: selected
            ? BytzGoTheme.brandBlue.withValues(alpha: 0.12)
            : BytzGoTheme.sheetDivider.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => setState(() => _tab = index),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: selected ? BytzGoTheme.brandBlue : BytzGoTheme.sheetMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
