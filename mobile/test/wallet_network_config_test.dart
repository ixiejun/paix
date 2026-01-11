import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/wallet/wallet_network_config.dart';

void main() {
  test('WalletNetworkConfig contains expected Passet Hub endpoints', () {
    expect(WalletNetworkConfig.passetHubRpc, 'https://testnet-passet-hub.polkadot.io');
    expect(WalletNetworkConfig.passetHubEvmRpc, 'https://testnet-passet-hub-eth-rpc.polkadot.io');
    expect(WalletNetworkConfig.passetHubWs, 'wss://passet-hub-paseo.ibp.network');
  });

  test('WalletNetworkConfig contains expected TokenDemo contract address', () {
    expect(
      WalletNetworkConfig.tokenDemoErc20.toLowerCase(),
      '0xdd128d3998ca3dfacebbc4218f7101b10ac8b09f',
    );
  });
}
