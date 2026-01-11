import 'package:flutter/foundation.dart';

enum BuyExecutionPhase {
  idle,
  signing,
  submitting,
  confirming,
  submitted,
  confirmed,
  failed,
}

@immutable
class BuyExecutionStatus {
  const BuyExecutionStatus({
    required this.phase,
    this.stepIndex,
    this.logs,
    this.txHash,
    this.receivedTokenAmount,
    this.tokenBalance,
    this.error,
  });

  final BuyExecutionPhase phase;
  final int? stepIndex;
  final List<String>? logs;
  final String? txHash;
  final String? receivedTokenAmount;
  final String? tokenBalance;
  final String? error;

  BuyExecutionStatus copyWith({
    BuyExecutionPhase? phase,
    int? stepIndex,
    List<String>? logs,
    String? txHash,
    String? receivedTokenAmount,
    String? tokenBalance,
    String? error,
  }) {
    return BuyExecutionStatus(
      phase: phase ?? this.phase,
      stepIndex: stepIndex ?? this.stepIndex,
      logs: logs ?? this.logs,
      txHash: txHash ?? this.txHash,
      receivedTokenAmount: receivedTokenAmount ?? this.receivedTokenAmount,
      tokenBalance: tokenBalance ?? this.tokenBalance,
      error: error ?? this.error,
    );
  }

  BuyExecutionStatus appendLog(String line, {int maxLines = 300}) {
    final next = [...(logs ?? const <String>[]), line];
    final trimmed = next.length > maxLines ? next.sublist(next.length - maxLines) : next;
    return copyWith(logs: List<String>.unmodifiable(trimmed));
  }

  bool get isBusy =>
      phase == BuyExecutionPhase.signing ||
      phase == BuyExecutionPhase.submitting ||
      phase == BuyExecutionPhase.confirming;
  bool get isDone => phase == BuyExecutionPhase.confirmed;
}
