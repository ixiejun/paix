import 'package:flutter/foundation.dart';

@immutable
class StrategyRecommendation {
  const StrategyRecommendation({
    required this.strategyType,
    required this.strategyLabel,
    required this.actions,
    required this.executionPreview,
  });

  static const Set<String> actionableTypes = <String>{
    'start_dca',
    'start_grid',
    'start_mean_reversion',
    'start_martingale',
  };

  static StrategyRecommendation? fromDone({
    required String? strategyType,
    required String? strategyLabel,
    required List<dynamic> actions,
    required Map<String, dynamic>? executionPreview,
  }) {
    final t = (strategyType ?? '').trim();
    if (t.isEmpty) return null;

    final label = (strategyLabel ?? '').trim();
    if (label.isEmpty) return null;

    if (actions.isEmpty) return null;

    if (!actionableTypes.contains(t)) return null;

    return StrategyRecommendation(
      strategyType: t,
      strategyLabel: label,
      actions: actions,
      executionPreview: executionPreview,
    );
  }

  final String strategyType;
  final String strategyLabel;
  final List<dynamic> actions;
  final Map<String, dynamic>? executionPreview;

  bool get isActionable => actionableTypes.contains(strategyType);

  bool get requiresConfirmation {
    final preview = executionPreview;
    if (preview == null) return false;
    final v = preview['requires_confirmation'];
    return v is bool ? v : false;
  }

  Map<String, dynamic> get actionParams {
    if (actions.isEmpty) return const {};
    final first = actions.first;
    if (first is Map<String, dynamic>) {
      final p = first['params'];
      if (p is Map<String, dynamic>) return p;
    }
    return const {};
  }

  Map<String, dynamic> get previewParams {
    final preview = executionPreview;
    if (preview == null) return const {};
    final p = preview['params'];
    if (p is Map<String, dynamic>) return p;
    return const {};
  }

  String? get symbol {
    final p1 = actionParams['symbol'];
    if (p1 is String && p1.trim().isNotEmpty) return p1;
    final p2 = previewParams['symbol'];
    if (p2 is String && p2.trim().isNotEmpty) return p2;
    return null;
  }
}

enum StrategyCardStatus {
  idle,
  observed,
  executed,
}
