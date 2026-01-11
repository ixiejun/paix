import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/chat/chat_state.dart';
import 'ui/app_shell.dart';
import 'ui/theme/app_theme.dart';
import 'wallet/wallet_state.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatState()),
        ChangeNotifierProvider(create: (_) => WalletState()),
      ],
      child: MaterialApp(
        title: 'AI 现货 DEX',
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const AppShell(),
      ),
    );
  }
}
