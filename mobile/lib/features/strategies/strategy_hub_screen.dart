import 'package:flutter/material.dart';

import '../../ui/theme/syntax_theme.dart';
import '../../ui/widgets/glass_card.dart';
import 'strategy_detail_screen.dart';
import 'strategy_mock_data.dart';
import 'strategy_product.dart';
import 'strategy_product_card.dart';

class StrategyHubScreen extends StatelessWidget {
  const StrategyHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);
    final products = StrategyMockData.products();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        const _SectionHeader(
          title: '投资产品',
          subtitle: '像买基金一样选择策略：看收益趋势与关键指标，再决定是否投入。',
        ),
        const SizedBox(height: 12),
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Text(
            '提示：这里展示的是历史表现示例（MVP 使用 mock 数据），不代表未来收益。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.textMuted),
          ),
        ),
        const SizedBox(height: 12),
        for (final StrategyProduct p in products) ...[
          StrategyProductCard(
            product: p,
            onPrimaryAction: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('MVP：尚未接入投入流程')),
              );
            },
            onViewDetails: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StrategyDetailScreen(product: p),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.textMuted),
        ),
      ],
    );
  }
}
