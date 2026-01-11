import 'dart:typed_data';

import 'package:polkadart/polkadart.dart';

import 'wallet_network_config.dart';

const bool _pasBalanceIsRelease = bool.fromEnvironment('dart.vm.product');

class PasBalanceService {
  const PasBalanceService({
    this.endpoint = WalletNetworkConfig.assetHubPaseoWs,
    this.fallbackEndpoints = WalletNetworkConfig.assetHubPaseoFallbackWs,
    this.connectTimeout = const Duration(seconds: 8),
    this.requestTimeout = const Duration(seconds: 20),
    this.symbol = 'PAS',
    this.decimals = 10,
  });

  final String endpoint;
  final List<String> fallbackEndpoints;
  final Duration connectTimeout;
  final Duration requestTimeout;
  final String symbol;
  final int decimals;

  static final Map<String, _WsProviderEntry> _providerPool = <String, _WsProviderEntry>{};
  static final Map<String, dynamic> _registryCache = <String, dynamic>{};
  static final Map<String, Future<dynamic>> _registryLoading = <String, Future<dynamic>>{};

  Future<BigInt> fetchFreeBalance({required Uint8List accountId}) async {
    final endpoints = {endpoint, ...fallbackEndpoints}.toList(growable: false);

    Object? lastError;
    StackTrace? lastStack;

    for (final ep in endpoints) {
      try {
        if (!_pasBalanceIsRelease) {
          // ignore: avoid_print
          print('PAS balance: trying endpoint=$ep');
        }

        final provider = await _getConnectedProvider(ep, connectTimeout);
        final stateApi = StateApi(provider);

        final dynamic registry = await _getRegistry(ep, stateApi, requestTimeout);

        final int? valueTypeId = registry.getStorageType('System', 'Account');
        if (valueTypeId == null) {
          throw StateError('System.Account storage type not found');
        }
        final valueCodec = registry.codecFor(valueTypeId);

        const accountIdCodec = ArrayCodec(U8Codec.codec, 32);
        final storageMap = StorageMap(
          prefix: 'System',
          storage: 'Account',
          hasher: const StorageHasher.blake2b128Concat(accountIdCodec),
          valueCodec: valueCodec,
        );

        final Uint8List keyBytes = storageMap.hashedKeyFor(accountId);

        final StorageData? storageData = await stateApi.getStorage(keyBytes).timeout(requestTimeout);
        if (storageData == null || storageData.isEmpty) return BigInt.zero;

        final decoded = valueCodec.decode(Input.fromBytes(storageData));
        final free = _extractFreeBalance(decoded);

        if (!_pasBalanceIsRelease) {
          // ignore: avoid_print
          print('PAS balance: success endpoint=$ep');
        }

        return free ?? BigInt.zero;
      } catch (e, st) {
        lastError = e;
        lastStack = st;

        if (!_pasBalanceIsRelease) {
          // ignore: avoid_print
          print('PAS balance: failed endpoint=$ep error=$e');
        }

        await _invalidateProvider(ep);
      }
    }

    throw PasBalanceFetchException(
      attemptedEndpoints: endpoints,
      cause: lastError,
      causeStackTrace: lastStack,
    );
  }

  BigInt? _extractFreeBalance(dynamic accountInfo) {
    if (accountInfo is Map) {
      final data = accountInfo['data'];
      if (data is Map) {
        final free = data['free'];
        if (free is BigInt) return free;
        if (free is int) return BigInt.from(free);
        if (free is String) {
          return BigInt.tryParse(free);
        }
      }
    }

    try {
      final dynamic data = (accountInfo as dynamic).data;
      final dynamic free = data.free;
      if (free is BigInt) return free;
      if (free is int) return BigInt.from(free);
      if (free is String) return BigInt.tryParse(free);
    } catch (_) {
      return null;
    }

    return null;
  }
}

class _WsProviderEntry {
  _WsProviderEntry(this.provider);

  final WsProvider provider;
  Future<void>? connecting;
  bool connected = false;
}

Future<WsProvider> _getConnectedProvider(String endpoint, Duration timeout) async {
  final existing = PasBalanceService._providerPool[endpoint];
  final entry = existing ?? _WsProviderEntry(WsProvider(Uri.parse(endpoint)));
  PasBalanceService._providerPool[endpoint] = entry;

  if (entry.provider.isConnected()) {
    entry.connected = true;
    return entry.provider;
  }

  if (entry.connected) return entry.provider;

  final inFlight = entry.connecting;
  if (inFlight != null) {
    await inFlight;
    return entry.provider;
  }

  final future = entry.provider.connect().timeout(timeout);

  entry.connecting = future;
  try {
    await future;
    entry.connected = true;
    return entry.provider;
  } catch (_) {
    await _invalidateProvider(endpoint);
    rethrow;
  } finally {
    entry.connecting = null;
  }
}

Future<void> _invalidateProvider(String endpoint) async {
  final entry = PasBalanceService._providerPool.remove(endpoint);
  PasBalanceService._registryCache.remove(endpoint);
  PasBalanceService._registryLoading.remove(endpoint);
  if (entry == null) return;
  try {
    await entry.provider.disconnect();
  } catch (_) {}
}

Future<dynamic> _getRegistry(String endpoint, StateApi stateApi, Duration timeout) async {
  final cached = PasBalanceService._registryCache[endpoint];
  if (cached != null) return cached;

  final inFlight = PasBalanceService._registryLoading[endpoint];
  if (inFlight != null) {
    return inFlight;
  }

  final future = () async {
    final runtimeMetadata = await stateApi.getMetadata().timeout(timeout);
    final chainInfo = runtimeMetadata.buildChainInfo();
    return chainInfo.registry;
  }();

  PasBalanceService._registryLoading[endpoint] = future;
  try {
    final reg = await future;
    PasBalanceService._registryCache[endpoint] = reg;
    return reg;
  } finally {
    PasBalanceService._registryLoading.remove(endpoint);
  }
}

class PasBalanceFetchException implements Exception {
  PasBalanceFetchException({
    required this.attemptedEndpoints,
    required this.cause,
    required this.causeStackTrace,
  });

  final List<String> attemptedEndpoints;
  final Object? cause;
  final StackTrace? causeStackTrace;

  @override
  String toString() {
    return 'PasBalanceFetchException(attempted=${attemptedEndpoints.join(', ')}, cause=$cause)';
  }
}
