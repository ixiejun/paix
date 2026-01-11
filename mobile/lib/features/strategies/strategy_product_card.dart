import 'package:flutter/material.dart';

import '../../ui/theme/syntax_theme.dart';
import '../../ui/widgets/glass_card.dart';
import 'strategy_formatters.dart';
import 'strategy_product.dart';
import 'widgets/sparkline.dart';

class StrategyProductCard extends StatelessWidget {
  const StrategyProductCard({
    super.key,
    required this.product,
    required this.onPrimaryAction,
    required this.onViewDetails,
  });

  final StrategyProduct product;
  final VoidCallback onPrimaryAction;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.textMuted);

    final annual = product.annualizedReturnPercent;
    final investors = product.investorCount;
    final aum = product.aumUsd;

    final bool hasAnyMetric = annual != null || investors != null || aum != null;

    final Color perfColor = (annual ?? 0) >= 0 ? syntax.success : syntax.danger;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(product.name, style: titleStyle),
          const SizedBox(height: 6),
          Text(product.shortDescription, style: bodyStyle),
          const SizedBox(height: 12),
          if (product.hasPerformanceSeries)
            Sparkline(
              values: product.performance3mPercentSeries,
              color: syntax.function,
            )
          else
            Container(
              height: 34,
              alignment: Alignment.centerLeft,
              child: Text('数据生成中', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.textMuted)),
            ),
          const SizedBox(height: 12),
          if (hasAnyMetric)
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: '年化',
                    value: annual == null ? '—' : formatPercent(annual),
                    valueColor: annual == null ? syntax.text : perfColor,
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: '参与人数',
                    value: investors == null ? '—' : formatCompactInt(investors),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: '管理规模',
                    value: aum == null ? '—' : formatUsd(aum),
                  ),
                ),
              ],
            )
          else
            Text('数据生成中', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.textMuted)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onPrimaryAction,
                  child: const Text('开始投资'),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: onViewDetails,
                child: const Text('查看详情'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.textMuted)),
        const SizedBox(height: 3),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
        ),
      ],
    );
  }
}
