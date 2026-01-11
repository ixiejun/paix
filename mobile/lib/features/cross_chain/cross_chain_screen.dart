import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ui/theme/syntax_theme.dart';
import '../../ui/widgets/glass_card.dart';
import 'cross_chain_models.dart';
import 'cross_chain_state.dart';

class CrossChainScreen extends StatefulWidget {
  const CrossChainScreen({super.key});

  @override
  State<CrossChainScreen> createState() => _CrossChainScreenState();
}

class _CrossChainScreenState extends State<CrossChainScreen> {
  final _intentIdController = TextEditingController();
  final _clientRequestIdController = TextEditingController();
  final _destinationController = TextEditingController(text: 'para-2000');
  final _amountController = TextEditingController(text: '1');
  final _tokenController = TextEditingController();

  CrossChainConnectorType _connector = CrossChainConnectorType.xcm;
  CrossChainGoalType _goal = CrossChainGoalType.deposit;
  CrossChainAssetKind _assetKind = CrossChainAssetKind.native;

  @override
  void dispose() {
    _intentIdController.dispose();
    _clientRequestIdController.dispose();
    _destinationController.dispose();
    _amountController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    return ChangeNotifierProvider(
      create: (_) => CrossChainState(),
      child: Builder(
        builder: (context) {
          final state = context.watch<CrossChainState>();
          final intent = state.intent;

          return Scaffold(
            appBar: AppBar(
              title: const Text('跨链状态'),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                if (state.error != null) ...[
                  Container(
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
                            state.error!,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.danger),
                          ),
                        ),
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: state.clearError,
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '创建 Intent',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _clientRequestIdController,
                        decoration: const InputDecoration(labelText: 'client_request_id（可选，用于幂等）'),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<CrossChainGoalType>(
                        initialValue: _goal,
                        items: CrossChainGoalType.values
                            .map((e) => DropdownMenuItem(value: e, child: Text(e.value)))
                            .toList(growable: false),
                        onChanged: state.loading ? null : (v) => setState(() => _goal = v ?? _goal),
                        decoration: const InputDecoration(labelText: 'goal'),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<CrossChainConnectorType>(
                        initialValue: _connector,
                        items: CrossChainConnectorType.values
                            .map((e) => DropdownMenuItem(value: e, child: Text(e.value)))
                            .toList(growable: false),
                        onChanged: state.loading ? null : (v) => setState(() => _connector = v ?? _connector),
                        decoration: const InputDecoration(labelText: 'connector'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _destinationController,
                        decoration: const InputDecoration(labelText: 'destination（例：para-2000 / evm:11155111）'),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<CrossChainAssetKind>(
                        initialValue: _assetKind,
                        items: CrossChainAssetKind.values
                            .map((e) => DropdownMenuItem(value: e, child: Text(e.value)))
                            .toList(growable: false),
                        onChanged: state.loading ? null : (v) => setState(() => _assetKind = v ?? _assetKind),
                        decoration: const InputDecoration(labelText: 'asset.kind'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _amountController,
                        decoration: const InputDecoration(labelText: 'asset.amount（字符串）'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 10),
                      if (_assetKind == CrossChainAssetKind.erc20)
                        TextField(
                          controller: _tokenController,
                          decoration: const InputDecoration(labelText: 'token_address（ERC-20 合约地址）'),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: state.loading
                                  ? null
                                  : () {
                                      final req = CrossChainIntentCreateRequest(
                                        clientRequestId: _clientRequestIdController.text.trim().isEmpty
                                            ? null
                                            : _clientRequestIdController.text.trim(),
                                        goal: _goal,
                                        target: CrossChainTarget(
                                          connector: _connector,
                                          destination: _destinationController.text.trim(),
                                        ),
                                        asset: CrossChainAsset(
                                          kind: _assetKind,
                                          amount: _amountController.text.trim(),
                                          tokenAddress: _assetKind == CrossChainAssetKind.erc20
                                              ? _tokenController.text.trim()
                                              : null,
                                        ),
                                        timeoutSeconds: 60,
                                      );
                                      state.createIntent(req);
                                    },
                              child: state.loading
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('创建并派发'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '查询 / 刷新',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _intentIdController,
                        decoration: const InputDecoration(labelText: 'intent_id'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: state.loading
                                  ? null
                                  : () {
                                      final id = _intentIdController.text.trim();
                                      if (id.isEmpty) return;
                                      state.loadIntent(id);
                                    },
                              child: const Text('查询'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextButton(
                              onPressed: state.loading || intent == null
                                  ? null
                                  : () {
                                      state.loadIntent(intent.intentId);
                                    },
                              child: const Text('刷新当前'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (intent != null)
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前 Intent',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        SelectableText('intent_id: ${intent.intentId}'),
                        const SizedBox(height: 6),
                        Text('state: ${intent.state.value}', style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 6),
                        Text('connector: ${intent.target.connector.value}', style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 6),
                        Text('destination: ${intent.target.destination}', style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 6),
                        Text('goal: ${intent.goal.value}', style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 6),
                        Text('asset: ${intent.asset.kind.value} ${intent.asset.amount}', style: Theme.of(context).textTheme.bodyMedium),
                        if (intent.asset.tokenAddress != null) ...[
                          const SizedBox(height: 6),
                          SelectableText('token: ${intent.asset.tokenAddress}'),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: state.loading ? null : state.cancel,
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: state.loading ? null : state.refund,
                                child: const Text('Refund'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '事件',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        if (intent.events.isEmpty)
                          Text('暂无事件', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.textMuted))
                        else
                          Column(
                            children: intent.events
                                .map(
                                  (e) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: syntax.surface2,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: syntax.border),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            e.state.value,
                                            style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            't=${e.timestampUnixS.toStringAsFixed(0)}',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: syntax.textMuted),
                                          ),
                                          if (e.messageId != null) ...[
                                            const SizedBox(height: 4),
                                            SelectableText(
                                              'message_id: ${e.messageId}',
                                              style: Theme.of(context).textTheme.bodySmall,
                                            ),
                                          ],
                                          if (e.detail != null && e.detail!.trim().isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              e.detail!,
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: syntax.textMuted),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
