import 'dart:convert';

import 'package:flutter/material.dart';

import '../../ui/theme/syntax_theme.dart';
import '../../ui/widgets/glass_card.dart';
import 'strategy_recommendation.dart';

class StrategyTradeCard extends StatelessWidget {
  const StrategyTradeCard({
    super.key,
    required this.recommendation,
    required this.status,
    required this.onExecute,
    required this.onObserve,
  });

  final StrategyRecommendation recommendation;
  final StrategyCardStatus status;
  final VoidCallback onExecute;
  final VoidCallback onObserve;

  bool get _disabled => status != StrategyCardStatus.idle;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: syntax.text,
          fontWeight: FontWeight.w700,
        );
    final metaStyle = Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.textMuted);

    final symbol = recommendation.symbol;

    return GlassCard(
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(16),
      backgroundColor: syntax.surface2,
      borderColor: syntax.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  recommendation.strategyLabel,
                  style: titleStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (recommendation.requiresConfirmation)
                Chip(
                  label: Text(
                    '需确认',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.text),
                  ),
                ),
            ],
          ),
          if (symbol != null) ...[
            const SizedBox(height: 4),
            Text(symbol, style: metaStyle),
          ],
          const SizedBox(height: 10),
          _ParamsBlock(recommendation: recommendation),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _disabled ? null : onExecute,
                  child: Text(status == StrategyCardStatus.executed ? '已执行' : '执行'),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: _disabled ? null : onObserve,
                child: Text(status == StrategyCardStatus.observed ? '已观望' : '观望'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ParamsBlock extends StatelessWidget {
  const _ParamsBlock({required this.recommendation});

  final StrategyRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    final p = <String, Object?>{};
    p.addAll(recommendation.previewParams);
    p.addAll(recommendation.actionParams);

    final rows = <Widget>[];

    void addRow(String label, String value) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 90,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.textMuted),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.text),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final entry = p['entry_price_range'];
    if (entry != null) {
      addRow('入场区间', _stringify(entry));
    }

    final tp = p['take_profit_percent'];
    if (tp != null) {
      addRow('止盈', '${_formatPercent(tp)}%');
    }

    final sl = p['stop_loss_percent'];
    if (sl != null) {
      addRow('止损', '${_formatPercent(sl)}%');
    }

    final gridLevels = p['grid_levels'];
    if (gridLevels != null) {
      addRow('网格档位', _stringify(gridLevels));
    }

    if (rows.isEmpty) {
      addRow('参数', '（无）');
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

String _stringify(Object? v) {
  if (v == null) return '';
  if (v is num || v is bool) return v.toString();
  if (v is String) return v;
  try {
    return jsonEncode(v);
  } catch (_) {
    return v.toString();
  }
}

String _formatPercent(Object? v) {
  final d = _toDouble(v);
  if (d == null) return _stringify(v);
  final percent = (d > 0 && d <= 1) ? d * 100 : d;
  return _trimZeros(percent);
}

String _trimZeros(double d) {
  final s = d.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'\.0+$'), '').replaceFirst(RegExp(r'(\.[0-9]*?)0+$'), r'$1');
}

double? _toDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}
