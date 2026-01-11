import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/execution_confirmation_sheet.dart';
import 'package:mobile/features/chat/strategy_recommendation.dart';
import 'package:mobile/ui/theme/app_theme.dart';

void main() {
  testWidgets('ExecutionConfirmationSheet shows tiers and key params', (tester) async {
    final rec = StrategyRecommendation.fromDone(
      strategyType: 'start_mean_reversion',
      strategyLabel: '均值回归',
      actions: const [
        {
          'type': 'start_mean_reversion',
          'params': {
            'symbol': 'ETHUSDT',
            'entry_price_range': [2400, 2500],
            'take_profit_percent': 4,
            'stop_loss_percent': 6,
          }
        }
      ],
      executionPreview: const {
        'requires_confirmation': true,
        'params': {'symbol': 'ETHUSDT'}
      },
    )!;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: ExecutionConfirmationSheet(
            recommendation: rec,
            onConfirm: (_) {},
          ),
        ),
      ),
    );

    expect(find.textContaining('执行确认：均值回归'), findsOneWidget);
    expect(find.text('ETHUSDT'), findsOneWidget);

    expect(find.text('风险'), findsOneWidget);
    expect(find.text('潜在收益'), findsOneWidget);

    expect(find.text('关键参数'), findsOneWidget);
    expect(find.text('入场区间'), findsOneWidget);
    expect(find.text('止盈'), findsOneWidget);
    expect(find.text('止损'), findsOneWidget);

    // Range visualization title for non-grid/non-martingale/non-dca
    expect(find.text('区间示意'), findsOneWidget);
  });

  testWidgets('ExecutionConfirmationSheet uses grid visualization for grid strategy', (tester) async {
    final rec = StrategyRecommendation.fromDone(
      strategyType: 'start_grid',
      strategyLabel: '网格',
      actions: const [
        {
          'type': 'start_grid',
          'params': {
            'symbol': 'BTCUSDT',
            'grid_levels': 12,
            'stop_loss_percent': 10,
          }
        }
      ],
      executionPreview: const {
        'requires_confirmation': true,
        'params': {'symbol': 'BTCUSDT'}
      },
    )!;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: ExecutionConfirmationSheet(
            recommendation: rec,
            onConfirm: (_) {},
          ),
        ),
      ),
    );

    expect(find.textContaining('执行确认：网格'), findsOneWidget);
    expect(find.text('网格示意'), findsOneWidget);
    expect(find.textContaining('档位：'), findsOneWidget);
  });
}
