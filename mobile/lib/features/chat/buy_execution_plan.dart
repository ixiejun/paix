import 'package:flutter/foundation.dart';

@immutable
class BuyExecutionPlan {
  const BuyExecutionPlan({
    required this.type,
    required this.amount,
    required this.tokenInSymbol,
    required this.tokenOutSymbol,
    required this.raw,
  });

  final String type;
  final String amount;
  final String tokenInSymbol;
  final String tokenOutSymbol;
  final Map<String, dynamic> raw;

  bool get isBuy => type == 'buy_token';
  bool get isSell => type == 'sell_token';

  static BuyExecutionPlan? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    final tRaw = json['type'];
    final t = (tRaw is String) ? tRaw.trim() : '';
    if (t != 'buy_token' && t != 'sell_token') return null;

    if (t == 'buy_token') {
      final amount = _coerceAmount(json['amount_in_pas'] ?? json['amount']);
      final tokenOutSymbol = _readTokenSymbol(json['token_out'] ?? json['token']);
      if (amount == null || tokenOutSymbol == null) return null;
      return BuyExecutionPlan(
        type: t,
        amount: amount,
        tokenInSymbol: 'PAS',
        tokenOutSymbol: tokenOutSymbol,
        raw: json,
      );
    }

    final amount = _coerceAmount(json['amount_in_token'] ?? json['amount']);
    final tokenInSymbol = _readTokenSymbol(json['token_in'] ?? json['token']);
    final tokenOutSymbol = _readTokenSymbol(json['token_out']) ?? 'PAS';
    if (amount == null || tokenInSymbol == null) return null;

    return BuyExecutionPlan(
      type: t,
      amount: amount,
      tokenInSymbol: tokenInSymbol,
      tokenOutSymbol: tokenOutSymbol,
      raw: json,
    );
  }
}

String? _readTokenSymbol(Object? v) {
  if (v is Map) {
    final s = v['symbol'];
    if (s is String && s.trim().isNotEmpty) return s.trim();
  }
  if (v is String && v.trim().isNotEmpty) return v.trim();
  return null;
}

String? _coerceAmount(Object? v) {
  if (v is num) return v.toString();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(s);
    return (m != null) ? m.group(1) : s;
  }
  return null;
}
