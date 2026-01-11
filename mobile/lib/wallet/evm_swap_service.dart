import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

import 'package:convert/convert.dart' as convert;
import 'package:http/http.dart' as http;
import 'package:wallet/wallet.dart';
import 'package:pointycastle/digests/keccak.dart';

import 'package:web3dart/web3dart.dart';

class EvmSwapService {
  EvmSwapService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const int passetHubChainId = 420420422;

  static final ContractAbi _routerAbi = ContractAbi.fromJson(
    '[{"inputs":[{"internalType":"uint256","name":"amountIn","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"}],"name":"getAmountsOut","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountOutMin","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapExactETHForTokens","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountIn","type":"uint256"},{"internalType":"uint256","name":"amountOutMin","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapExactTokensForETH","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"nonpayable","type":"function"}]',
    'UniswapV2Router02',
  );

  static final ContractAbi _erc20Abi = ContractAbi.fromJson(
    '[{"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"spender","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}]',
    'ERC20',
  );

  static final String _erc20TransferTopic0 = _bytesToHex(
    _keccak256(Uint8List.fromList(utf8.encode('Transfer(address,address,uint256)'))),
    include0x: true,
  ).toLowerCase();

  static Uint8List _keccak256(Uint8List input) {
    final d = KeccakDigest(256);
    return d.process(input);
  }

  Future<BigInt> getNativeBalanceWei({
    required String rpcUrl,
    required EthereumAddress owner,
  }) async {
    final w3 = Web3Client(rpcUrl, _client);
    try {
      final bal = await w3.getBalance(owner);
      return bal.getInWei;
    } finally {
      w3.dispose();
    }
  }

  Future<BigInt> getErc20Balance({
    required String rpcUrl,
    required EthereumAddress token,
    required EthereumAddress owner,
  }) async {
    final w3 = Web3Client(rpcUrl, _client);
    try {
      final contract = DeployedContract(_erc20Abi, token);
      final balanceOfFn = contract.function('balanceOf');
      final out = await w3.call(contract: contract, function: balanceOfFn, params: [owner]);
      final v = out.isNotEmpty ? out.first : null;
      if (v is BigInt) return v;
      return BigInt.zero;
    } finally {
      w3.dispose();
    }
  }

  static String _bytesToHex(Uint8List bytes, {required bool include0x}) {
    final h = convert.hex.encode(bytes);
    return include0x ? '0x$h' : h;
  }

  Future<String> swapExactEthForTokens({
    required String rpcUrl,
    required EthPrivateKey credentials,
    required EthereumAddress router,
    required EthereumAddress weth,
    required EthereumAddress tokenOut,
    required EtherAmount amountIn,
    required int slippageBps,
    Duration deadline = const Duration(minutes: 10),
    int? maxGas,
  }) async {
    final w3 = Web3Client(rpcUrl, _client);
    try {
      final to = credentials.address;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final deadlineUnix = BigInt.from(now + deadline.inSeconds);

      final contract = DeployedContract(_routerAbi, router);
      final getAmountsOut = contract.function('getAmountsOut');
      final swap = contract.function('swapExactETHForTokens');

      final path = <EthereumAddress>[weth, tokenOut];
      final amountInWei = amountIn.getInWei;
      final out = await w3.call(
        contract: contract,
        function: getAmountsOut,
        params: [amountInWei, path],
      );

      BigInt amountOutMin = BigInt.zero;
      if (out.isNotEmpty && out.first is List) {
        final amounts = (out.first as List).whereType<BigInt>().toList(growable: false);
        if (amounts.isNotEmpty) {
          final quoted = amounts.last;
          final bps = BigInt.from(10000 - slippageBps);
          amountOutMin = (quoted * bps) ~/ BigInt.from(10000);
        }
      }

      final tx = Transaction.callContract(
        contract: contract,
        function: swap,
        parameters: [amountOutMin, path, to, deadlineUnix],
        value: amountIn,
        maxGas: maxGas,
        gasPrice: await w3.getGasPrice(),
      );
      final hash = await w3.sendTransaction(
        credentials,
        tx,
        chainId: passetHubChainId,
      );

      return hash;
    } finally {
      w3.dispose();
    }
  }

  Future<BigInt> getErc20Allowance({
    required String rpcUrl,
    required EthereumAddress token,
    required EthereumAddress owner,
    required EthereumAddress spender,
  }) async {
    final w3 = Web3Client(rpcUrl, _client);
    try {
      final contract = DeployedContract(_erc20Abi, token);
      final fn = contract.function('allowance');
      final out = await w3.call(contract: contract, function: fn, params: [owner, spender]);
      final v = out.isNotEmpty ? out.first : null;
      if (v is BigInt) return v;
      return BigInt.zero;
    } finally {
      w3.dispose();
    }
  }

  Future<String> approveErc20({
    required String rpcUrl,
    required EthPrivateKey credentials,
    required EthereumAddress token,
    required EthereumAddress spender,
    required BigInt amount,
    int? maxGas,
  }) async {
    final w3 = Web3Client(rpcUrl, _client);
    try {
      final contract = DeployedContract(_erc20Abi, token);
      final approve = contract.function('approve');
      final tx = Transaction.callContract(
        contract: contract,
        function: approve,
        parameters: [spender, amount],
        maxGas: maxGas,
        gasPrice: await w3.getGasPrice(),
      );
      return await w3.sendTransaction(
        credentials,
        tx,
        chainId: passetHubChainId,
      );
    } finally {
      w3.dispose();
    }
  }

  Future<String> swapExactTokensForEth({
    required String rpcUrl,
    required EthPrivateKey credentials,
    required EthereumAddress router,
    required EthereumAddress weth,
    required EthereumAddress tokenIn,
    required BigInt amountIn,
    required int slippageBps,
    Duration deadline = const Duration(minutes: 10),
    int? maxGas,
  }) async {
    final w3 = Web3Client(rpcUrl, _client);
    try {
      final to = credentials.address;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final deadlineUnix = BigInt.from(now + deadline.inSeconds);

      final contract = DeployedContract(_routerAbi, router);
      final getAmountsOut = contract.function('getAmountsOut');
      final swap = contract.function('swapExactTokensForETH');

      final path = <EthereumAddress>[tokenIn, weth];
      final out = await w3.call(
        contract: contract,
        function: getAmountsOut,
        params: [amountIn, path],
      );

      BigInt amountOutMin = BigInt.zero;
      if (out.isNotEmpty && out.first is List) {
        final amounts = (out.first as List).whereType<BigInt>().toList(growable: false);
        if (amounts.isNotEmpty) {
          final quoted = amounts.last;
          final bps = BigInt.from(10000 - slippageBps);
          amountOutMin = (quoted * bps) ~/ BigInt.from(10000);
        }
      }

      final tx = Transaction.callContract(
        contract: contract,
        function: swap,
        parameters: [amountIn, amountOutMin, path, to, deadlineUnix],
        maxGas: maxGas,
        gasPrice: await w3.getGasPrice(),
      );
      return await w3.sendTransaction(
        credentials,
        tx,
        chainId: passetHubChainId,
      );
    } finally {
      w3.dispose();
    }
  }

  Future<TransactionReceipt?> waitForReceipt({
    required String rpcUrl,
    required String txHash,
    Duration timeout = const Duration(minutes: 2),
    Duration pollInterval = const Duration(seconds: 3),
  }) async {
    final w3 = Web3Client(rpcUrl, _client);
    try {
      final started = DateTime.now();
      while (DateTime.now().difference(started) < timeout) {
        final receipt = await w3.getTransactionReceipt(txHash);
        if (receipt != null) return receipt;
        await Future.delayed(pollInterval);
      }
      return null;
    } finally {
      w3.dispose();
    }
  }

  Future<int> getErc20Decimals({
    required String rpcUrl,
    required EthereumAddress token,
  }) async {
    final w3 = Web3Client(rpcUrl, _client);
    try {
      final contract = DeployedContract(_erc20Abi, token);
      final decimalsFn = contract.function('decimals');
      final out = await w3.call(contract: contract, function: decimalsFn, params: const []);
      final v = out.isNotEmpty ? out.first : null;
      if (v is BigInt) return v.toInt();
      if (v is int) return v;
      return 18;
    } catch (_) {
      return 18;
    } finally {
      w3.dispose();
    }
  }

  BigInt extractErc20ReceivedAmountFromReceipt({
    required TransactionReceipt receipt,
    required EthereumAddress token,
    required EthereumAddress recipient,
  }) {
    BigInt total = BigInt.zero;
    final recipientHex = recipient.toString().toLowerCase();
    final logs = receipt.logs;

    for (final l in logs) {
      final addr = l.address;
      if (addr == null) continue;
      if (addr.toString().toLowerCase() != token.toString().toLowerCase()) continue;

      final topics = l.topics;
      if (topics == null || topics.length < 3) continue;

      final topic0Raw = topics.first;
      if (topic0Raw == null) continue;

      final topic0 = _normalizeHex(topic0Raw).toLowerCase();
      if (topic0 != _erc20TransferTopic0) continue;

      final toTopicRaw = topics[2];
      if (toTopicRaw == null) continue;
      final toTopicHex = _normalizeHex(toTopicRaw);
      final toHex = _topicToAddressHex(toTopicHex).toLowerCase();
      if (toHex != recipientHex) continue;

      final dataHex = _normalizeHex(l.data);
      if (dataHex.length < 3) continue;

      final amount = BigInt.parse(dataHex.substring(2), radix: 16);
      total += amount;
    }

    return total;
  }

  String _topicToAddressHex(String topic) {
    final t = topic.toLowerCase();
    final normalized = t.startsWith('0x') ? t.substring(2) : t;
    if (normalized.length < 40) return '0x0';
    return '0x${normalized.substring(normalized.length - 40)}';
  }

  String _normalizeHex(Object? data) {
    if (data == null) return '0x';
    if (data is String) return data.startsWith('0x') ? data : '0x$data';
    if (data is Uint8List) return _bytesToHex(data, include0x: true);
    return data.toString();
  }
}
