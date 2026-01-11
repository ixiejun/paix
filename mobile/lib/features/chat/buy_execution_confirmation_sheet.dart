import 'package:flutter/material.dart';

import '../../ui/theme/syntax_theme.dart';
import '../../ui/widgets/glass_card.dart';
import 'buy_execution_plan.dart';

class BuyExecutionConfirmationSheet extends StatelessWidget {
  const BuyExecutionConfirmationSheet({
    super.key,
    required this.plan,
    required this.onConfirm,
  });

  final BuyExecutionPlan plan;
  final VoidCallback onConfirm;

  bool _hasXcmStep(Map<String, dynamic> raw) {
    final steps = raw['steps'];
    if (steps is! List) return false;
    for (final s in steps) {
      if (s is Map<String, dynamic> && s['kind'] == 'xcm_transfer') return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    final hasXcm = _hasXcmStep(plan.raw);
    final title = plan.isBuy ? '执行确认：买入 ${plan.tokenOutSymbol}' : '执行确认：卖出 ${plan.tokenInSymbol}';

    final swapLine = plan.isBuy
        ? '在 Passet Hub EVM 上 swap ${plan.tokenInSymbol} -> ${plan.tokenOutSymbol}（需要本地签名）'
        : '在 Passet Hub EVM 上 swap ${plan.tokenInSymbol} -> ${plan.tokenOutSymbol}（需要本地签名）';

    final stepsText = hasXcm
        ? '你将执行两步交易：\n1) XCM 跨链 AssetHub(1000) -> PassetHub(1111)（需要本地签名）\n2) $swapLine'
        : '你将执行一步交易：\n1) $swapLine';

    final amountText = plan.isBuy
        ? '数量：${plan.amount} ${plan.tokenInSymbol}'
        : '数量：${plan.amount} ${plan.tokenInSymbol}';

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
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: syntax.text,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                stepsText,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.text, height: 1.35),
              ),
              const SizedBox(height: 10),
              Text(
                amountText,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: syntax.text),
              ),
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
                      onPressed: onConfirm,
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
