import '../core/json_parse.dart';

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.amount,
    required this.type,
    this.status,
    this.reference,
    this.createdAt,
  });

  final String id;
  final double amount;
  final String type;
  final String? status;
  final String? reference;
  final String? createdAt;

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    return WalletTransaction(
      id: json['id']?.toString() ?? '',
      amount: parseJsonDoubleOrZero(json['amount']),
      type: json['type']?.toString() ?? '',
      status: json['status']?.toString(),
      reference: json['reference']?.toString(),
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString(),
    );
  }

  bool get isCredit => amount > 0;
}
