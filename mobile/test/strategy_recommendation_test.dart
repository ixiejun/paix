import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/strategy_recommendation.dart';

void main() {
  test('StrategyRecommendation.fromDone returns null when missing required fields', () {
    expect(
      StrategyRecommendation.fromDone(
        strategyType: null,
        strategyLabel: '网格',
        actions: const [],
        executionPreview: const {'requires_confirmation': true},
      ),
      isNull,
    );

    expect(
      StrategyRecommendation.fromDone(
        strategyType: 'start_grid',
        strategyLabel: null,
        actions: const [{}],
        executionPreview: const {'requires_confirmation': true},
      ),
      isNull,
    );

    expect(
      StrategyRecommendation.fromDone(
        strategyType: 'start_grid',
        strategyLabel: '网格',
        actions: const [],
        executionPreview: const {'requires_confirmation': true},
      ),
      isNull,
    );
  });

  test('StrategyRecommendation.fromDone only accepts actionable strategy types', () {
    expect(
      StrategyRecommendation.fromDone(
        strategyType: 'none',
        strategyLabel: '暂时观望',
        actions: const [{}],
        executionPreview: const {'requires_confirmation': true},
      ),
      isNull,
    );

    final rec = StrategyRecommendation.fromDone(
      strategyType: 'start_dca',
      strategyLabel: '智能DCA',
      actions: const [
        {
          'type': 'start_dca',
          'params': {'symbol': 'BTCUSDT'}
        }
      ],
      executionPreview: const {'requires_confirmation': true, 'params': {'symbol': 'BTCUSDT'}},
    );

    expect(rec, isNotNull);
    expect(rec!.strategyType, 'start_dca');
    expect(rec.strategyLabel, '智能DCA');
    expect(rec.isActionable, isTrue);
    expect(rec.requiresConfirmation, isTrue);
    expect(rec.symbol, 'BTCUSDT');
  });
}
