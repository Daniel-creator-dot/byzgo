import 'package:flutter/material.dart';

import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/ride_ui.dart';
import 'rider_commission_repository.dart';

/// Trip commission summary + pay actions (mirrors web rider wallet section).
class RiderCommissionSection extends StatelessWidget {
  const RiderCommissionSection({
    super.key,
    required this.commission,
    required this.loading,
    required this.paying,
    required this.paystackPaying,
    required this.onPayFromWallet,
    required this.onPayWithPaystack,
  });

  final RiderCommissionSummary? commission;
  final bool loading;
  final bool paying;
  final bool paystackPaying;
  final VoidCallback onPayFromWallet;
  final VoidCallback onPayWithPaystack;

  @override
  Widget build(BuildContext context) {
    if (loading && commission == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: BytzGoTheme.accent),
          ),
        ),
      );
    }

    final c = commission;
    if (c == null) return const SizedBox.shrink();

    final borderColor = c.hasOverdue
        ? Colors.redAccent.withValues(alpha: 0.5)
        : const Color(0xFF334155);

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF0F172A),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'TRIP COMMISSION',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
          if (c.policy.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              c.policy,
              style: TextStyle(
                fontSize: 11,
                height: 1.45,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '${c.commissionPercent.toStringAsFixed(0)}% commission'
            ' (${c.platformPercent.toStringAsFixed(0)}% platform'
            ' + ${c.insurancePercent.toStringAsFixed(0)}% insurance)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
          if (c.hasOverdue) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
              ),
              child: Text(
                'Commission overdue — pay ${formatCedis(c.totalOwed)} before the 8:00 AM rule',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.redAccent,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Owed: ${formatCedis(c.totalOwed)}',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: c.hasOverdue ? Colors.redAccent : BytzGoTheme.accent,
            ),
          ),
          if (c.settlements.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...c.settlements.take(5).map((s) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatSettlementDayLabel(s.settlementDate),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    Text(
                      formatCedis(s.amountOwed),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: s.isOverdue ? Colors.redAccent : Colors.white70,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          if (c.totalOwed > 0.01) ...[
            const SizedBox(height: 16),
            RidePrimaryButton(
              label: paystackPaying
                  ? 'Opening payment…'
                  : 'Pay ${formatCedis(c.totalOwed)} with MoMo or Card',
              onPressed: (paying || paystackPaying) ? null : onPayWithPaystack,
            ),
            const SizedBox(height: 8),
            if (c.canPayFromWallet)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: (paying || paystackPaying) ? null : onPayFromWallet,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF334155)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    paying ? 'Paying…' : 'Pay from wallet balance',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                  ),
                ),
              )
            else
              Text(
                'Wallet balance ${formatCedis(c.walletBalance)} — not enough to cover commission. Pay with Mobile Money or card above.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
