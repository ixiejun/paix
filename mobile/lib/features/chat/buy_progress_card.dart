import 'package:flutter/material.dart';

import '../../ui/theme/syntax_theme.dart';
import '../../ui/widgets/glass_card.dart';
import 'buy_execution_status.dart';

class BuyProgressCard extends StatefulWidget {
  const BuyProgressCard({
    super.key,
    required this.status,
  });

  final BuyExecutionStatus status;

  @override
  State<BuyProgressCard> createState() => _BuyProgressCardState();
}

class _BuyProgressCardState extends State<BuyProgressCard> with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _dots;
  final ScrollController _logScroll = ScrollController();

  bool _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _dots = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void didUpdateWidget(covariant BuyProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final prev = oldWidget.status.logs?.length ?? 0;
    final next = widget.status.logs?.length ?? 0;

    if (next > prev && _stickToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_logScroll.hasClients) return;
        _logScroll.animateTo(
          _logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _dots.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  Color _stepColor(SyntaxTheme syntax, BuyExecutionStatus s, int idx) {
    if (s.phase == BuyExecutionPhase.failed) return syntax.danger;
    if (s.phase == BuyExecutionPhase.confirmed) return syntax.success;
    final cur = s.stepIndex ?? 0;
    if (idx < cur) return syntax.success;
    if (idx == cur) return syntax.primary;
    return syntax.textMuted;
  }

  Widget _buildStepDot(SyntaxTheme syntax, BuyExecutionStatus s, int idx) {
    final color = _stepColor(syntax, s, idx);
    final cur = s.stepIndex ?? 0;
    final active = s.phase != BuyExecutionPhase.failed && s.phase != BuyExecutionPhase.confirmed && idx == cur && s.isBusy;
    final done = s.phase != BuyExecutionPhase.failed && (idx < cur || (s.phase == BuyExecutionPhase.confirmed && idx == cur));

    if (!active) {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: done ? color : color.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: done ? 0.0 : 0.35)),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = _pulse.value;
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35 + 0.25 * t),
                blurRadius: 10 + 8 * t,
                spreadRadius: 0,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStepper(BuildContext context, BuyExecutionStatus s) {
    final syntax = SyntaxTheme.of(context);
    const steps = <String>['XCM', '到账', 'Swap', '确认'];

    return SizedBox(
      width: 72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildStepDot(syntax, s, i),
                const SizedBox(width: 8),
                Text(
                  steps[i],
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _stepColor(syntax, s, i),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            if (i != steps.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 5),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: 2,
                  height: 20,
                  color: _stepColor(syntax, s, i).withValues(alpha: 0.22),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogTitle(BuildContext context, BuyExecutionStatus s) {
    final syntax = SyntaxTheme.of(context);
    final busy = s.isBusy;

    return Row(
      children: [
        Expanded(
          child: Text(
            '过程日志',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: syntax.text,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        if (busy)
          AnimatedBuilder(
            animation: _dots,
            builder: (context, _) {
              final v = _dots.value;
              final a1 = (v < 0.33) ? 1.0 : 0.25;
              final a2 = (v >= 0.33 && v < 0.66) ? 1.0 : 0.25;
              final a3 = (v >= 0.66) ? 1.0 : 0.25;
              Widget dot(double a) => Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      color: syntax.textMuted.withValues(alpha: a),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
              return Row(children: [dot(a1), dot(a2), dot(a3)]);
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);
    final s = widget.status;
    final logs = s.logs ?? const <String>[];

    return GlassCard(
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(16),
      backgroundColor: syntax.surface2,
      borderColor: syntax.border,
      child: SizedBox(
        height: 248,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepper(context, s),
            const SizedBox(width: 10),
            Expanded(
              child: GlassCard(
                padding: const EdgeInsets.all(10),
                borderRadius: BorderRadius.circular(14),
                backgroundColor: syntax.surface,
                borderColor: syntax.border,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLogTitle(context, s),
                    const SizedBox(height: 8),
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (!_logScroll.hasClients) return false;
                          if (n.metrics.maxScrollExtent <= 0) return false;
                          final distance = n.metrics.maxScrollExtent - n.metrics.pixels;
                          _stickToBottom = distance < 24;
                          return false;
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: ListView.builder(
                            controller: _logScroll,
                            itemCount: logs.isEmpty ? 1 : logs.length,
                            itemBuilder: (context, index) {
                              final text = logs.isEmpty ? '等待开始…' : logs[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  text,
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                        color: syntax.text,
                                        height: 1.25,
                                      ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
