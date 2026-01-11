import 'package:flutter/material.dart';

import '../../ui/theme/syntax_theme.dart';
import '../../ui/widgets/glass_card.dart';
import 'strategy_formatters.dart';
import 'strategy_product.dart';
import 'widgets/sparkline.dart';

class StrategyDetailScreen extends StatelessWidget {
  const StrategyDetailScreen({super.key, required this.product});

  final StrategyProduct product;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(product.name),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          _AuroraBackground(color: syntax.background, primary: syntax.primary, accent: syntax.number),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                Text(
                  product.shortDescription,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.textMuted),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '近 3 个月收益走势',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      if (product.hasPerformanceSeries)
                        Sparkline(
                          values: product.performance3mPercentSeries,
                          color: syntax.function,
                          height: 140,
                          strokeWidth: 2.5,
                        )
                      else
                        Container(
                          height: 140,
                          alignment: Alignment.center,
                          child:
                              Text('数据生成中', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.textMuted)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _KpiGrid(product: product),
                const SizedBox(height: 12),
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '适合谁',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      ...product.suitableFor.map(
                        (t) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('• $t', style: Theme.of(context).textTheme.bodyMedium),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '不适合谁',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      ...product.notSuitableFor.map(
                        (t) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('• $t', style: Theme.of(context).textTheme.bodyMedium),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '风险提示',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(product.riskNote, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.textMuted)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('MVP：尚未接入投入流程')),
                          );
                        },
                        child: const Text('开始投资'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('MVP：可在聊天里咨询 AI')),
                          );
                        },
                        child: const Text('咨询 AI'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.product});

  final StrategyProduct product;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    final annual = product.annualizedReturnPercent;
    final ret3m = product.return3mPercent;
    final investors = product.investorCount;
    final aum = product.aumUsd;

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 420;
        final itemWidth = twoColumns ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;

        final items = <Widget>[
          _KpiCard(
            width: itemWidth,
            title: '年化收益',
            value: annual == null ? '—' : formatPercent(annual),
            valueColor: annual == null ? null : (annual >= 0 ? syntax.success : syntax.danger),
          ),
          _KpiCard(
            width: itemWidth,
            title: '近 3 个月',
            value: ret3m == null ? '—' : formatPercent(ret3m),
            valueColor: ret3m == null ? null : (ret3m >= 0 ? syntax.success : syntax.danger),
          ),
          _KpiCard(
            width: itemWidth,
            title: '参与人数',
            value: investors == null ? '—' : formatCompactInt(investors),
          ),
          _KpiCard(
            width: itemWidth,
            title: '管理规模',
            value: aum == null ? '—' : formatUsd(aum),
          ),
        ];

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items,
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.width,
    required this.title,
    required this.value,
    this.valueColor,
  });

  final double width;
  final String title;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    return SizedBox(
      width: width,
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.textMuted)),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: valueColor,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuroraBackground extends StatelessWidget {
  const _AuroraBackground({
    required this.color,
    required this.primary,
    required this.accent,
  });

  final Color color;
  final Color primary;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          color: color,
          gradient: RadialGradient(
            center: const Alignment(0, -1.1),
            radius: 1.2,
            colors: [
              primary.withValues(alpha: 0.30),
              accent.withValues(alpha: 0.14),
              Colors.transparent,
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.8, 0.2),
              radius: 0.9,
              colors: [
                accent.withValues(alpha: 0.12),
                Colors.transparent,
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
