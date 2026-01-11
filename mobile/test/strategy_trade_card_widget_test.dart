import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/strategy_recommendation.dart';
import 'package:mobile/features/chat/strategy_trade_card.dart';
import 'package:mobile/ui/theme/app_theme.dart';

void main() {
  testWidgets('StrategyTradeCard disables buttons after observed', (tester) async {
    final rec = StrategyRecommendation.fromDone(
      strategyType: 'start_grid',
      strategyLabel: '网格',
      actions: const [
        {
          'type': 'start_grid',
          'params': {'symbol': 'BTCUSDT'}
        }
      ],
      executionPreview: const {'requires_confirmation': true, 'params': {'symbol': 'BTCUSDT'}},
    )!;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: StrategyTradeCard(
            recommendation: rec,
            status: StrategyCardStatus.observed,
            onExecute: () {},
            onObserve: () {},
          ),
        ),
      ),
    );

    expect(find.text('网格'), findsOneWidget);
    expect(find.text('BTCUSDT'), findsOneWidget);

    final execute = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(execute.onPressed, isNull);

    final observe = tester.widget<TextButton>(find.byType(TextButton));
    expect(observe.onPressed, isNull);
  });
}
