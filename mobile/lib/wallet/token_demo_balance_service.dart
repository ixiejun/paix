import 'dart:async';

import 'package:wallet/wallet.dart';

import 'evm_swap_service.dart';
import 'wallet_network_config.dart';

class TokenDemoBalanceService {
  TokenDemoBalanceService({EvmSwapService? evmSwapService}) : _evmSwapService = evmSwapService ?? EvmSwapService();

  final EvmSwapService _evmSwapService;

  Future<TokenDemoBalanceResult> fetch({
    required EthereumAddress owner,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final token = EthereumAddress.fromHex(WalletNetworkConfig.tokenDemoErc20);

    final decimals = await _evmSwapService
        .getErc20Decimals(
          rpcUrl: WalletNetworkConfig.passetHubEvmRpc,
          token: token,
        )
        .timeout(timeout);

    final balance = await _evmSwapService
        .getErc20Balance(
          rpcUrl: WalletNetworkConfig.passetHubEvmRpc,
          token: token,
          owner: owner,
        )
        .timeout(timeout);

    return TokenDemoBalanceResult(balance: balance, decimals: decimals);
  }
}

class TokenDemoBalanceResult {
  const TokenDemoBalanceResult({required this.balance, required this.decimals});

  final BigInt balance;
  final int decimals;
}
