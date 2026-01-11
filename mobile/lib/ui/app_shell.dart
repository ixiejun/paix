import 'package:flutter/material.dart';
import 'dart:ui';

import '../features/chat/chat_screen.dart';
import '../features/strategies/strategy_hub_screen.dart';
import 'theme/syntax_theme.dart';
import '../wallet/wallet_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    final tabs = <Widget>[
      const ChatScreen(),
      const StrategyHubScreen(),
      const WalletScreen(),
    ];

    final titles = <String>[
      'AI 助手',
      '策略',
      '钱包',
    ];

    return Scaffold(
      extendBody: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: _GlassBar(
          child: AppBar(
            title: Text(titles[_index]),
            actions: [
              if (_index == 0)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: syntax.surface2,
                        border: Border.all(color: syntax.border),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '设置',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: syntax.keyword,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          const _AuroraBackground(),
          SafeArea(
            top: false,
            child: IndexedStack(
              index: _index,
              children: tabs,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _GlassBar(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: '助手',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view),
              label: '策略',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet),
              label: '钱包',
            ),
          ],
        ),
      ),
    );
  }
}

class _AuroraBackground extends StatelessWidget {
  const _AuroraBackground();

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          color: syntax.background,
          gradient: RadialGradient(
            center: const Alignment(0, -1.1),
            radius: 1.2,
            colors: [
              syntax.primary.withValues(alpha: 0.30),
              syntax.number.withValues(alpha: 0.14),
              Colors.transparent,
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.8, 0.2),
              radius: 0.9,
              colors: [
                syntax.number.withValues(alpha: 0.12),
                Colors.transparent,
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassBar extends StatelessWidget {
  const _GlassBar({
    required this.child,
    this.borderRadius,
    this.padding,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    final radius = borderRadius ?? BorderRadius.zero;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: syntax.surface,
            border: Border.all(color: syntax.border),
            borderRadius: radius,
          ),
          child: child,
        ),
      ),
    );
  }
}
