import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mobile/wallet/token_demo_balance_service.dart';
import 'package:mobile/wallet/wallet_network_config.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:convert/convert.dart' as convert;
import 'package:ss58/ss58.dart' as ss58;
import 'package:wallet/wallet.dart';

const String _erc20TransferTopic0 =
    '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef';

Future<void> main(List<String> args) async {
  final chainIdHex = await _rpcCall(WalletNetworkConfig.passetHubEvmRpc, 'eth_chainId', const []) as String;
  final chainId = _parseHexInt(chainIdHex);

  final svc = TokenDemoBalanceService();
  final token = EthereumAddress.fromHex(WalletNetworkConfig.tokenDemoErc20);

  stdout.writeln('rpc=${WalletNetworkConfig.passetHubEvmRpc}');
  stdout.writeln('chainId=$chainId ($chainIdHex)');
  stdout.writeln('token=${WalletNetworkConfig.tokenDemoErc20}');

  final decimals = (await svc.fetch(owner: EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'))).decimals;
  stdout.writeln('decimals=$decimals');

  if (args.isNotEmpty && args.first.trim().isNotEmpty) {
    final input = args.first.trim();
    final owner = _parseOwnerAddress(input);
    final res = await svc.fetch(owner: owner);
    stdout.writeln('owner=${owner.with0x}');
    stdout.writeln('balanceRaw=${res.balance}');
    stdout.writeln('balanceFormatted=${_formatUnits(res.balance, res.decimals)}');
  }

  await _scanRecentRecipientsAndPrintBalances(
    token: token,
    decimals: decimals,
    limit: 8,
    lookbackBlocks: 5000,
  );
}

EthereumAddress _parseOwnerAddress(String input) {
  final s = input.trim();
  if (s.startsWith('0x') || s.startsWith('0X')) {
    return EthereumAddress.fromHex(s);
  }

  final decoded = ss58.Address.decode(s);
  final accountId = Uint8List.fromList(decoded.pubkey);
  final evmHex = _mapSubstrateAccountIdToEvmAddress(accountId);

  stdout.writeln('ss58=$s prefix=${decoded.prefix}');
  stdout.writeln('accountId=0x${convert.hex.encode(accountId)}');
  stdout.writeln('derivedEvm=$evmHex');

  return EthereumAddress.fromHex(evmHex);
}

String _mapSubstrateAccountIdToEvmAddress(Uint8List accountId) {
  if (accountId.length != 32) {
    throw StateError('accountId must be 32 bytes, got ${accountId.length}');
  }

  final isEthDerived = (() {
    for (var i = 20; i < 32; i++) {
      if (accountId[i] != 0xEE) return false;
    }
    return true;
  })();

  Uint8List h160;
  if (isEthDerived) {
    h160 = Uint8List.sublistView(accountId, 0, 20);
  } else {
    final digest = KeccakDigest(256);
    final hash = Uint8List.fromList(digest.process(accountId));
    h160 = Uint8List.sublistView(hash, 12, 32);
  }

  return '0x${convert.hex.encode(h160)}'.toLowerCase();
}

Future<void> _scanRecentRecipientsAndPrintBalances({
  required EthereumAddress token,
  required int decimals,
  required int limit,
  required int lookbackBlocks,
}) async {
  final latestHex = await _rpcCall(WalletNetworkConfig.passetHubEvmRpc, 'eth_blockNumber', const []) as String;
  final latest = _parseHexInt(latestHex);
  final from = latest - lookbackBlocks;
  final fromHex = '0x${from.clamp(0, latest).toRadixString(16)}';

  final logs = await _rpcCall(
    WalletNetworkConfig.passetHubEvmRpc,
    'eth_getLogs',
    [
      {
        'fromBlock': fromHex,
        'toBlock': 'latest',
        'address': token.with0x,
        'topics': [_erc20TransferTopic0],
      }
    ],
  );

  final decoded = (logs as List).cast<dynamic>();
  final recipients = <String>[];
  final seen = <String>{};

  for (final raw in decoded.reversed) {
    if (raw is! Map) continue;
    final topics = raw['topics'];
    if (topics is! List || topics.length < 3) continue;
    final toTopic = topics[2];
    if (toTopic is! String) continue;
    final to = _topicToAddress(toTopic);
    final key = to.toLowerCase();
    if (seen.contains(key)) continue;
    seen.add(key);
    recipients.add(to);
    if (recipients.length >= limit) break;
  }

  stdout.writeln('recentRecipients=${recipients.length} (lookbackBlocks=$lookbackBlocks latest=$latest)');
  if (recipients.isEmpty) return;

  final svc = TokenDemoBalanceService();
  for (final addr in recipients) {
    try {
      final owner = EthereumAddress.fromHex(addr);
      final res = await svc.fetch(owner: owner);
      final formatted = _formatUnits(res.balance, decimals);
      stdout.writeln('recipient=${owner.with0x} balanceRaw=${res.balance} balanceFormatted=$formatted');
    } catch (e) {
      stdout.writeln('recipient=$addr error=$e');
    }
  }
}

Future<dynamic> _rpcCall(String url, String method, List<dynamic> params) async {
  final resp = await http.post(
    Uri.parse(url),
    headers: {'content-type': 'application/json'},
    body: json.encode({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params}),
  );

  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw StateError('RPC $method failed. status=${resp.statusCode} body=${resp.body}');
  }

  final decoded = json.decode(resp.body) as Map<String, dynamic>;
  if (decoded['error'] != null) {
    throw StateError('RPC $method error: ${decoded['error']}');
  }

  return decoded['result'];
}

int _parseHexInt(String hex) {
  final normalized = hex;
  final s = normalized.startsWith('0x') ? normalized.substring(2) : normalized;
  if (s.isEmpty) return 0;
  return int.parse(s, radix: 16);
}

String _topicToAddress(String topic) {
  final t = topic.toLowerCase();
  final normalized = t.startsWith('0x') ? t.substring(2) : t;
  if (normalized.length < 40) return '0x0';
  return '0x${normalized.substring(normalized.length - 40)}';
}

String _formatUnits(BigInt value, int decimals) {
  if (decimals <= 0) return value.toString();

  final negative = value.isNegative;
  final abs = value.abs();
  final s = abs.toString().padLeft(decimals + 1, '0');
  final intPart = s.substring(0, s.length - decimals);
  var fracPart = s.substring(s.length - decimals);
  while (fracPart.isNotEmpty && fracPart.endsWith('0')) {
    fracPart = fracPart.substring(0, fracPart.length - 1);
  }

  final result = fracPart.isEmpty ? intPart : '$intPart.$fracPart';
  return negative ? '-$result' : result;
}
