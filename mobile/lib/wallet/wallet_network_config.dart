class WalletNetworkConfig {
  const WalletNetworkConfig._();

  static const String assetHubPaseoName = 'AssetHub Paseo';
  static const String passetHubName = 'Passet Hub';

  static const String assetHubPaseoWs = 'wss://sys.ibp.network/asset-hub-paseo';
  static const List<String> assetHubPaseoFallbackWs = [
    'wss://asset-hub-paseo-rpc.n.dwellir.com',
    'wss://asset-hub-paseo.dotters.network',
    'wss://pas-rpc.stakeworld.io/assethub',
    'wss://sys.turboflakes.io/asset-hub-paseo',
  ];

  static const String passetHubRpc = 'https://testnet-passet-hub.polkadot.io';
  static const String passetHubEvmRpc = 'https://testnet-passet-hub-eth-rpc.polkadot.io';
  static const String passetHubWs = 'wss://passet-hub-paseo.ibp.network';

  static const String passetHubUniswapV2Router = '0x9aeAf6995b64A490fe1c2a8c06Dc2E912a487710';
  static const String passetHubWeth9 = '0x4042196503b0C1E1f4188277bFfA46373FCf3576';

  static const String tokenDemoErc20 = '0xDD128D3998Ca3DfACEbbC4218F7101B10aC8b09F';
}
