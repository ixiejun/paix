import 'package:flutter/material.dart';

import '../../ui/theme/syntax_theme.dart';
import '../../ui/widgets/glass_card.dart';
import 'buy_execution_plan.dart';
import 'buy_execution_status.dart';

class BuyPlanCard extends StatelessWidget {
  const BuyPlanCard({
    super.key,
    required this.plan,
    required this.onExecute,
    this.status,
  });

  final BuyExecutionPlan plan;
  final VoidCallback onExecute;
  final BuyExecutionStatus? status;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    final s = status;
    final bool disabled = s?.isBusy == true || s?.txHash != null;
    final infoStyle = Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.textMuted);
    final buttonText = () {
      if (s == null) return '确认执行';
      switch (s.phase) {
        case BuyExecutionPhase.signing:
        case BuyExecutionPhase.submitting:
          return '执行中…';
        case BuyExecutionPhase.confirming:
          return '确认中…';
        case BuyExecutionPhase.confirmed:
          return '已确认';
        case BuyExecutionPhase.submitted:
          return '已提交';
        case BuyExecutionPhase.failed:
        case BuyExecutionPhase.idle:
          return '确认执行';
      }
    }();

    final summary = plan.isBuy
        ? '用 ${plan.amount} ${plan.tokenInSymbol} 购买 ${plan.tokenOutSymbol}'
        : '卖出 ${plan.amount} ${plan.tokenInSymbol} 换成 ${plan.tokenOutSymbol}';

    final infoWidgets = <Widget>[];
    if (s?.txHash != null) {
      infoWidgets.add(
        Text(
          'tx: ${s?.txHash ?? '—'}',
          style: infoStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    if (s?.receivedTokenAmount != null) {
      if (infoWidgets.isNotEmpty) infoWidgets.add(const SizedBox(height: 8));
      infoWidgets.add(
        Text(
          '收到：${s?.receivedTokenAmount ?? '—'}',
          style: infoStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    if (s?.tokenBalance != null) {
      if (infoWidgets.isNotEmpty) infoWidgets.add(const SizedBox(height: 8));
      infoWidgets.add(
        Text(
          '持仓：${s?.tokenBalance ?? '—'}',
          style: infoStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    if (s?.error != null) {
      if (infoWidgets.isNotEmpty) infoWidgets.add(const SizedBox(height: 8));
      infoWidgets.add(
        Text(
          s?.error ?? '—',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.danger),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return GlassCard(
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(16),
      backgroundColor: syntax.surface2,
      borderColor: syntax.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '交易计划',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: syntax.text,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            summary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.text),
          ),
          if (infoWidgets.isNotEmpty) ...[
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: infoWidgets,
            ),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: disabled ? null : onExecute,
                  child: Text(buttonText),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
