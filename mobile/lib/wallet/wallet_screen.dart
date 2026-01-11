import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/cross_chain/cross_chain_screen.dart';
import '../ui/theme/syntax_theme.dart';
import '../ui/widgets/glass_card.dart';
import 'wallet_state.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _importController = TextEditingController();

  @override
  void dispose() {
    _importController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WalletState>();
    final syntax = SyntaxTheme.of(context);

    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '跨链状态',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '查看 bridge/回拨的 lifecycle，支持 cancel/refund。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const CrossChainScreen()),
                  );
                },
                child: const Text('打开'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (state.error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: syntax.danger.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: syntax.danger.withValues(alpha: 0.35)),
            ),
            child: Text(
              state.error!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.danger),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (state.activeAccount == null) ...[
          Text(
            '隐形钱包',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '在本设备创建非托管钱包。签名可通过 FaceID/指纹等方式保护。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.textMuted),
          ),
          const SizedBox(height: 14),
          GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '导入或创建',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _importController,
                  decoration: const InputDecoration(
                    labelText: '导入助记词',
                  ),
                  minLines: 2,
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => context.read<WalletState>().importWallet(_importController.text),
                        child: const Text('导入'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => context.read<WalletState>().startCreateWallet(),
                        child: const Text('创建'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ] else ...[
          GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.activeAccount!.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text('SS58 地址', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.textMuted)),
                const SizedBox(height: 6),
                SelectableText(state.activeAccount!.ss58Address),
                const SizedBox(height: 12),
                Text('EVM 映射地址', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: syntax.textMuted)),
                const SizedBox(height: 6),
                SelectableText(state.activeAccount!.evmAddress),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final res = await context.read<WalletState>().authenticateForSigningDetailed();
                          if (!context.mounted) return;
                          final reason = [res.code, res.message].whereType<String>().where((e) => e.trim().isNotEmpty).join(': ');
                          final msg = res.ok ? '已验证' : (reason.isEmpty ? '验证失败' : '验证失败：$reason');
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                        },
                        child: const Text('测试生物识别'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => context.read<WalletState>().resetWallet(),
                        child: const Text('重置'),
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'PAS 余额',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: state.pasBalanceLoading ? null : () => context.read<WalletState>().refreshPasBalance(),
                      child: const Text('刷新'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (state.pasBalanceLoading)
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '正在获取余额…',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.textMuted),
                      ),
                    ],
                  )
                else
                  Text(
                    '${state.pasBalanceFormatted ?? '—'} PAS',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                if (state.pasBalanceError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    state.pasBalanceError!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.danger),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  '网络：AssetHub Paseo',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.textMuted),
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'TokenDemo 余额',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: state.tokenDemoBalanceLoading ? null : () => context.read<WalletState>().refreshTokenDemoBalance(),
                      child: const Text('刷新'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (state.tokenDemoBalanceLoading)
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '正在获取余额…',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.textMuted),
                      ),
                    ],
                  )
                else
                  Text(
                    state.tokenDemoBalanceFormatted ?? '—',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                if (state.tokenDemoBalanceError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    state.tokenDemoBalanceError!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.danger),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  '网络：Passet Hub',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.textMuted),
                ),
              ],
            ),
          ),
        ],
        if (state.pendingMnemonic != null) ...[
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '备份助记词',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '请勿与任何人分享。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.textMuted),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  padding: const EdgeInsets.all(12),
                  borderRadius: BorderRadius.circular(14),
                  backgroundColor: syntax.surface2,
                  child: SelectableText(
                    state.pendingMnemonic!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => context.read<WalletState>().confirmCreateWallet(),
                        child: const Text('我已备份'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextButton(
                        onPressed: () => context.read<WalletState>().cancelCreateWallet(),
                        child: const Text('取消'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
