import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/theme/syntax_theme.dart';
import '../../ui/widgets/glass_card.dart';
import 'strategy_recommendation.dart';

enum Tier {
  low,
  medium,
  high,
}

String? _suggestedAmountUsd(StrategyRecommendation rec) {
  final params = <String, Object?>{};
  params.addAll(rec.previewParams);
  params.addAll(rec.actionParams);

  const keys = <String>[
    'amount_usd',
    'amount',
    'investment_usd',
    'capital_usd',
    'notional_usd',
  ];
  for (final k in keys) {
    final v = params[k];
    if (v is num) return _trimZeros(v.toDouble());
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return null;
}

class _ConfirmationSummary {
  const _ConfirmationSummary({
    required this.riskTier,
    required this.riskExplanation,
    required this.returnTier,
    required this.returnExplanation,
    required this.keyParams,
    required this.visualization,
  });

  final Tier riskTier;
  final String riskExplanation;
  final Tier returnTier;
  final String returnExplanation;
  final List<_KeyParam> keyParams;
  final Widget visualization;
}

class _KeyParam {
  const _KeyParam(this.label, this.value);

  final String label;
  final String value;
}

class ExecutionConfirmationSheet extends StatefulWidget {
  const ExecutionConfirmationSheet({
    super.key,
    required this.recommendation,
    required this.onConfirm,
  });

  final StrategyRecommendation recommendation;
  final ValueChanged<String> onConfirm;

  @override
  State<ExecutionConfirmationSheet> createState() => _ExecutionConfirmationSheetState();
}

class _ExecutionConfirmationSheetState extends State<ExecutionConfirmationSheet> {
  late final TextEditingController _amountController;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: _suggestedAmountUsd(widget.recommendation) ?? '');
    _amountController.addListener(_validateAmount);
    _validateAmount();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _validateAmount() {
    final s = _amountController.text.trim();
    final next = (() {
      if (s.isEmpty) return '请输入投入金额';
      final v = double.tryParse(s);
      if (v == null) return '请输入数字';
      if (v <= 0) return '金额需大于 0';
      return null;
    })();

    if (next != _amountError) {
      setState(() {
        _amountError = next;
      });
    }
  }

  bool get _canConfirm => _amountError == null && _amountController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);
    final summary = _buildSummary(widget.recommendation);

    final symbol = widget.recommendation.symbol;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GlassCard(
          padding: const EdgeInsets.all(12),
          borderRadius: BorderRadius.circular(18),
          backgroundColor: syntax.surface2,
          borderColor: syntax.border,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '执行确认：${widget.recommendation.strategyLabel}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: syntax.text,
                    ),
              ),
              if (symbol != null) ...[
                const SizedBox(height: 4),
                Text(
                  symbol,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.textMuted),
                ),
              ],
              const SizedBox(height: 12),
              _TierCards(summary: summary),
              const SizedBox(height: 12),
              _KeyParamsBlock(params: summary.keyParams),
              const SizedBox(height: 12),
              Text(
                '投入资金',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: syntax.text,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(
                  hintText: '例如 200',
                  suffixText: 'U',
                  errorText: _amountError,
                  filled: true,
                  fillColor: syntax.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: syntax.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: syntax.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: syntax.primary),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              summary.visualization,
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _canConfirm
                          ? () {
                              widget.onConfirm(_amountController.text.trim());
                            }
                          : null,
                      child: const Text('确认执行'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TierCards extends StatelessWidget {
  const _TierCards({required this.summary});

  final _ConfirmationSummary summary;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _TierCard(
              title: '风险',
              tier: summary.riskTier,
              explanation: summary.riskExplanation,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _TierCard(
              title: '潜在收益',
              tier: summary.returnTier,
              explanation: summary.returnExplanation,
            ),
          ),
        ],
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.title,
    required this.tier,
    required this.explanation,
  });

  final String title;
  final Tier tier;
  final String explanation;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);
    final chipColor = _tierColor(syntax, tier);
    final label = _tierLabel(tier);

    return GlassCard(
      padding: const EdgeInsets.all(10),
      borderRadius: BorderRadius.circular(16),
      backgroundColor: syntax.surface,
      borderColor: syntax.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: syntax.text,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: chipColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: chipColor.withValues(alpha: 0.35)),
                ),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            explanation,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: syntax.textMuted, height: 1.35),
          ),
        ],
      ),
    );
  }

  static String _tierLabel(Tier t) {
    switch (t) {
      case Tier.low:
        return '低';
      case Tier.medium:
        return '中';
      case Tier.high:
        return '高';
    }
  }

  static Color _tierColor(SyntaxTheme syntax, Tier t) {
    switch (t) {
      case Tier.low:
        return syntax.success;
      case Tier.medium:
        return syntax.warning;
      case Tier.high:
        return syntax.danger;
    }
  }
}

class _KeyParamsBlock extends StatelessWidget {
  const _KeyParamsBlock({required this.params});

  final List<_KeyParam> params;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);
    if (params.isEmpty) {
      return Text(
        '关键参数不足',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.textMuted),
      );
    }

    final rows = <Widget>[];
    for (final p in params) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 90,
                child: Text(
                  p.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.textMuted),
                ),
              ),
              Expanded(
                child: Text(
                  p.value,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.text),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '关键参数',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: syntax.text,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        ...rows,
      ],
    );
  }
}

class GridVisualization extends StatelessWidget {
  const GridVisualization({super.key, required this.levels});

  final int levels;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    final lv = levels <= 1 ? 2 : levels;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '网格示意',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: syntax.text,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (ctx, c) {
            final width = c.maxWidth;
            return SizedBox(
              height: 18,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: syntax.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: syntax.border),
                      ),
                    ),
                  ),
                  for (int i = 0; i <= lv; i++)
                    Positioned(
                      left: width * i / lv,
                      top: 2,
                      bottom: 2,
                      child: Container(
                        width: 1,
                        color: syntax.border.withValues(alpha: 0.9),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          '档位：$lv',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: syntax.textMuted),
        ),
      ],
    );
  }
}

class RangeVisualization extends StatelessWidget {
  const RangeVisualization({
    super.key,
    required this.entry,
    required this.stopLoss,
    required this.takeProfit,
    required this.title,
  });

  final String? entry;
  final String? stopLoss;
  final String? takeProfit;
  final String title;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: syntax.text,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 12,
          decoration: BoxDecoration(
            color: syntax.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: syntax.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: syntax.primary.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (entry != null) _badge(context, '入场', entry!, syntax.info),
            if (stopLoss != null) _badge(context, '止损', stopLoss!, syntax.danger),
            if (takeProfit != null) _badge(context, '止盈', takeProfit!, syntax.success),
          ],
        ),
      ],
    );
  }

  Widget _badge(BuildContext context, String k, String v, Color c) {
    final syntax = SyntaxTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$k：$v',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.text),
      ),
    );
  }
}

class DcaVisualization extends StatelessWidget {
  const DcaVisualization({super.key, required this.entry});

  final String? entry;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '分批示意',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: syntax.text,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 12,
          decoration: BoxDecoration(
            color: syntax.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: syntax.border),
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),
              for (int i = 0; i < 5; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: syntax.primary.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (entry != null) ...[
          const SizedBox(height: 6),
          Text(
            '入场区间：$entry',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: syntax.textMuted),
          ),
        ],
      ],
    );
  }
}

class MartingaleVisualization extends StatelessWidget {
  const MartingaleVisualization({super.key});

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '加仓风险示意',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: syntax.text,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (int i = 0; i < 5; i++)
              Expanded(
                child: Container(
                  height: 10,
                  margin: EdgeInsets.only(right: i == 4 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: syntax.danger.withValues(alpha: 0.15 + i * 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: syntax.border),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '层数越深，风险与潜在回撤越大。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: syntax.textMuted),
        ),
      ],
    );
  }
}

_ConfirmationSummary _buildSummary(StrategyRecommendation rec) {
  final params = <String, Object?>{};
  params.addAll(rec.previewParams);
  params.addAll(rec.actionParams);

  final stopLoss = _toPercentDouble(params['stop_loss_percent']);
  final takeProfit = _toPercentDouble(params['take_profit_percent']);

  final risk = _inferRiskTier(rec.strategyType, stopLoss);
  final ret = _inferReturnTier(rec.strategyType, takeProfit);

  final riskExplanation = _riskExplanation(rec.strategyType, stopLoss);
  final returnExplanation = _returnExplanation(rec.strategyType, takeProfit);

  final keyParams = <_KeyParam>[];

  final entry = params['entry_price_range'];
  if (entry != null) {
    keyParams.add(_KeyParam('入场区间', _stringify(entry)));
  }

  if (takeProfit != null) {
    keyParams.add(_KeyParam('止盈', '${_trimZeros(takeProfit)}%'));
  }

  if (stopLoss != null) {
    keyParams.add(_KeyParam('止损', '${_trimZeros(stopLoss)}%'));
  }

  final gridLevels = _toInt(params['grid_levels']);
  if (gridLevels != null) {
    keyParams.add(_KeyParam('网格档位', '$gridLevels'));
  }

  final entryStr = entry == null ? null : _stringify(entry);
  final slStr = stopLoss == null ? null : '${_trimZeros(stopLoss)}%';
  final tpStr = takeProfit == null ? null : '${_trimZeros(takeProfit)}%';

  final viz = _visualizationFor(rec.strategyType, gridLevels, entryStr, slStr, tpStr);

  return _ConfirmationSummary(
    riskTier: risk,
    riskExplanation: riskExplanation,
    returnTier: ret,
    returnExplanation: returnExplanation,
    keyParams: keyParams,
    visualization: viz,
  );
}

Widget _visualizationFor(String strategyType, int? gridLevels, String? entry, String? sl, String? tp) {
  if (strategyType == 'start_grid') {
    return GridVisualization(levels: gridLevels ?? 10);
  }
  if (strategyType == 'start_martingale') {
    return const MartingaleVisualization();
  }
  if (strategyType == 'start_dca') {
    return DcaVisualization(entry: entry);
  }
  return RangeVisualization(
    entry: entry,
    stopLoss: sl,
    takeProfit: tp,
    title: '区间示意',
  );
}

Tier _inferRiskTier(String strategyType, double? stopLossPercent) {
  if (strategyType == 'start_martingale') return Tier.high;
  if (stopLossPercent == null) return Tier.high;
  if (stopLossPercent <= 3) return Tier.low;
  if (stopLossPercent <= 8) return Tier.medium;
  return Tier.high;
}

Tier _inferReturnTier(String strategyType, double? takeProfitPercent) {
  if (takeProfitPercent == null) return Tier.medium;
  if (takeProfitPercent <= 2) return Tier.low;
  if (takeProfitPercent <= 5) return Tier.medium;
  return Tier.high;
}

String _riskExplanation(String strategyType, double? stopLossPercent) {
  if (strategyType == 'start_martingale') {
    return '马丁策略具有加仓递增特性，风险较高。建议小仓位并严格控制最大层数。';
  }
  if (stopLossPercent == null) {
    return '未提供明确止损参数，回撤不可控风险更高。建议补充止损或降低仓位。';
  }
  if (stopLossPercent <= 3) {
    return '止损相对紧，单笔回撤控制更强，但更容易被短期波动触发。';
  }
  if (stopLossPercent <= 8) {
    return '止损适中，容错与回撤控制相对平衡。';
  }
  return '止损较宽，允许更大波动，潜在回撤更高。建议降低仓位。';
}

String _returnExplanation(String strategyType, double? takeProfitPercent) {
  if (takeProfitPercent == null) {
    if (strategyType == 'start_grid') {
      return '网格收益依赖震荡幅度与执行纪律，通常较稳健但不保证收益。';
    }
    return '未提供明确止盈目标，潜在收益评估偏保守。';
  }
  if (takeProfitPercent <= 2) {
    return '目标止盈较小，更偏向保守快进快出。';
  }
  if (takeProfitPercent <= 5) {
    return '目标止盈适中，兼顾胜率与收益空间。';
  }
  return '目标止盈较高，收益空间更大但达成概率可能降低。';
}

String _stringify(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is num) return _trimZeros(v.toDouble());
  if (v is List) {
    return v.map(_stringify).where((e) => e.isNotEmpty).join(' ~ ');
  }
  if (v is Map) {
    return v.toString();
  }
  return v.toString();
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

double? _toPercentDouble(Object? v) {
  final d = _toDouble(v);
  if (d == null) return null;
  if (d > 0 && d <= 1) return d * 100;
  return d;
}

int? _toInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}
