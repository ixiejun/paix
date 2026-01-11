import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import 'chat_models.dart';
import 'chat_state.dart';
import 'buy_execution_confirmation_sheet.dart';
import 'buy_plan_card.dart';
import 'buy_progress_card.dart';
import 'execution_confirmation_sheet.dart';
import 'strategy_recommendation.dart';
import 'strategy_trade_card.dart';
import '../../ui/theme/syntax_theme.dart';
import '../../ui/widgets/glass_card.dart';
import '../../wallet/wallet_state.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _stickToBottom = true;

  Future<void> _executeBuyPlan(String messageId) async {
    final chat = context.read<ChatState>();
    final plan = chat.buyPlanForMessage(messageId);
    if (plan == null) return;

    final wallet = context.read<WalletState>();
    final res = await wallet.authenticateForSigningDetailed();
    if (!res.ok) {
      final reason = [res.code, res.message].whereType<String>().where((e) => e.trim().isNotEmpty).join(': ');
      chat.addSystemMessage(reason.isEmpty ? '签名验证失败，已取消。' : '签名验证失败，已取消。原因：$reason');
      return;
    }

    final mnemonic = await wallet.getMnemonicForSigning();
    if (mnemonic == null || mnemonic.trim().isEmpty) {
      chat.addSystemMessage('未找到助记词，无法签名。');
      return;
    }

    await chat.executeBuyPlan(messageId: messageId, plan: plan, mnemonic: mnemonic);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeScrollToBottom() {
    if (!_stickToBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    context.read<ChatState>().sendMessage(text);
  }

  void _stop() {
    context.read<ChatState>().stopGeneration();
  }

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);
    final chat = context.watch<ChatState>();

    _maybeScrollToBottom();

    return Column(
      children: [
        if (chat.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: syntax.danger.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: syntax.danger.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      chat.error!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.danger),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () => context.read<ChatState>().reset(),
                    child: const Text('重置'),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.maxScrollExtent <= 0) return false;
              final distance = n.metrics.maxScrollExtent - n.metrics.pixels;
              _stickToBottom = distance < 80;
              return false;
            },
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              controller: _scrollController,
              itemCount: chat.messages.length,
              itemBuilder: (context, index) {
                final m = chat.messages[index];
                return _ChatBubble(message: m, onExecuteBuyPlan: _executeBuyPlan);
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            borderRadius: BorderRadius.circular(18),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: '给交易智能体发消息…',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                    minLines: 1,
                    maxLines: 4,
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: (chat.sending || chat.streaming)
                      ? null
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('语音识别演示：未实现')),
                          );
                        },
                  icon: const Icon(Icons.mic_none),
                  tooltip: '语音输入',
                ),
                const SizedBox(width: 2),
                FilledButton(
                  onPressed: chat.streaming
                      ? _stop
                      : chat.sending
                          ? null
                          : _send,
                  child: chat.streaming
                      ? const Text('停止')
                      : chat.sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('发送'),
                ),
              ],
            ),
          ),
        ),
        if (chat.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '请求失败，可重试',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.textMuted),
                  ),
                ),
                TextButton(
                  onPressed: chat.sending ? null : () => context.read<ChatState>().retryLast(),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.onExecuteBuyPlan});

  final ChatMessage message;
  final Future<void> Function(String messageId) onExecuteBuyPlan;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);
    final chat = context.watch<ChatState>();

    final isUser = message.isUser;

    final isStreaming = message.status == ChatMessageStatus.streaming;
    final isError = message.status == ChatMessageStatus.error;

    final bubbleColor = isUser
        ? syntax.primary.withValues(alpha: 0.12)
        : isError
            ? syntax.danger.withValues(alpha: 0.10)
            : isStreaming
                ? syntax.surface2
                : syntax.surface;
    final borderColor = isUser
        ? syntax.primary.withValues(alpha: 0.35)
        : isError
            ? syntax.danger.withValues(alpha: 0.35)
            : syntax.border;

    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: syntax.text,
          height: 1.35,
        );

    final markdownStyle = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: textStyle,
      code: textStyle?.copyWith(
        fontFamily: 'monospace',
        color: syntax.string,
        backgroundColor: syntax.surface2,
      ),
      codeblockDecoration: BoxDecoration(
        color: syntax.surface2,
        border: Border.all(color: syntax.border),
        borderRadius: BorderRadius.circular(14),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      blockquoteDecoration: BoxDecoration(
        color: syntax.surface2,
        border: Border(left: BorderSide(color: syntax.keyword, width: 3)),
      ),
    );

    final rec = !message.isUser ? chat.recommendationForMessage(message.id) : null;
    final buyPlan = !message.isUser ? chat.buyPlanForMessage(message.id) : null;
    final buyStatus = !message.isUser ? chat.buyStatusForMessage(message.id) : null;

    bool hasXcmStep(Map<String, dynamic> raw) {
      final steps = raw['steps'];
      if (steps is! List) return false;
      for (final s in steps) {
        if (s is Map<String, dynamic> && s['kind'] == 'xcm_transfer') return true;
      }
      return false;
    }

    final hideProgressCardForSellNoXcm = buyPlan != null && buyPlan.isSell && !hasXcmStep(buyPlan.raw);
    final showCard =
        rec != null && message.status == ChatMessageStatus.done && rec.isActionable && rec.requiresConfirmation;
    final cardStatus = showCard ? chat.tradeCardStatusForMessage(message.id) : StrategyCardStatus.idle;

    void showBuySheet() {
      final plan = buyPlan;
      if (plan == null) return;

      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) {
          return BuyExecutionConfirmationSheet(
            plan: plan,
            onConfirm: () {
              Navigator.of(ctx).pop();
              onExecuteBuyPlan(message.id);
            },
          );
        },
      );
    }

    void showExecuteSheet() {
      final r = rec;
      if (r == null) return;

      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) {
          return ExecutionConfirmationSheet(
            recommendation: r,
            onConfirm: (amountUsd) {
              Navigator.of(ctx).pop();
              chat.confirmExecuteTradeCard(message.id, amountUsd: amountUsd);
            },
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          constraints: const BoxConstraints(maxWidth: 560),
          child: GlassCard(
            padding: const EdgeInsets.all(12),
            borderRadius: BorderRadius.circular(16),
            backgroundColor: bubbleColor,
            borderColor: borderColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarkdownBody(
                  data: message.content,
                  selectable: true,
                  styleSheet: markdownStyle,
                ),
                if (!isUser && isStreaming) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: syntax.textMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '思考中…',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.textMuted),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        if (showCard) ...[
          const SizedBox(height: 6),
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            constraints: const BoxConstraints(maxWidth: 560),
            child: StrategyTradeCard(
              recommendation: rec,
              status: cardStatus,
              onExecute: showExecuteSheet,
              onObserve: () => chat.observeTradeCard(message.id),
            ),
          ),
        ],
        if (!message.isUser && message.status == ChatMessageStatus.done && buyPlan != null) ...[
          const SizedBox(height: 6),
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            constraints: const BoxConstraints(maxWidth: 560),
            child: BuyPlanCard(
              plan: buyPlan,
              status: buyStatus,
              onExecute: showBuySheet,
            ),
          ),
          if (buyStatus != null &&
              (buyStatus.logs?.isNotEmpty == true || buyStatus.isBusy || buyStatus.txHash != null || buyStatus.error != null)) ...[
            if (!hideProgressCardForSellNoXcm) ...[
              const SizedBox(height: 8),
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                constraints: const BoxConstraints(maxWidth: 560),
                child: BuyProgressCard(
                  key: ValueKey('buy-progress-${message.id}'),
                  status: buyStatus,
                ),
              ),
            ],
          ],
        ],
      ],
    );
  }
}
