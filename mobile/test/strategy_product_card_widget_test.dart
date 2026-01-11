import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/strategies/strategy_product.dart';
import 'package:mobile/features/strategies/strategy_product_card.dart';
import 'package:mobile/ui/theme/app_theme.dart';

void main() {
  testWidgets('StrategyProductCard degrades gracefully when data is missing', (tester) async {
    const product = StrategyProduct(
      id: 'p1',
      name: '示例产品',
      shortDescription: '示例描述',
      riskNote: '示例风险',
      performance3mPercentSeries: [],
      annualizedReturnPercent: null,
      investorCount: null,
      aumUsd: null,
      suitableFor: ['A'],
      notSuitableFor: ['B'],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: StrategyProductCard(
            product: product,
            onPrimaryAction: () {},
            onViewDetails: () {},
          ),
        ),
      ),
    );

    expect(find.text('示例产品'), findsOneWidget);
    expect(find.text('示例描述'), findsOneWidget);

    expect(find.text('数据生成中'), findsWidgets);
    expect(find.text('—'), findsNWidgets(3));

    expect(find.text('开始投资'), findsOneWidget);
    expect(find.text('查看详情'), findsOneWidget);
  });
}
