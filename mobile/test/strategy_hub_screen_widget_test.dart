import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/strategies/strategy_detail_screen.dart';
import 'package:mobile/features/strategies/strategy_hub_screen.dart';
import 'package:mobile/ui/theme/app_theme.dart';

void main() {
  testWidgets('StrategyHubScreen renders product list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: StrategyHubScreen()),
      ),
    );

    expect(find.text('投资产品'), findsOneWidget);
    expect(find.textContaining('像买基金一样选择策略'), findsOneWidget);

    expect(find.text('区间收益增强'), findsOneWidget);
    expect(find.text('稳健定投计划'), findsOneWidget);
    expect(find.text('回调机会捕捉'), findsOneWidget);

    expect(find.text('开始投资'), findsNWidgets(3));
    expect(find.text('查看详情'), findsNWidgets(3));
  });

  testWidgets('StrategyHubScreen navigates to detail page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: StrategyHubScreen()),
      ),
    );

    await tester.tap(find.text('查看详情').first);
    await tester.pumpAndSettle();

    expect(find.byType(StrategyDetailScreen), findsOneWidget);
    expect(find.text('近 3 个月收益走势'), findsOneWidget);
    expect(find.text('风险提示'), findsOneWidget);
  });
}
