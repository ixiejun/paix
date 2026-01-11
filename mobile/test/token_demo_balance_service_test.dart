import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/wallet/evm_swap_service.dart';
import 'package:mobile/wallet/token_demo_balance_service.dart';
import 'package:wallet/wallet.dart';

void main() {
  test('TokenDemoBalanceService fetches decimals() and balanceOf()', () async {
    final mock = MockClient((req) async {
      final body = json.decode(req.body) as Map<String, dynamic>;
      final id = body['id'];
      final method = body['method'] as String?;

      String ok(Object? result) {
        return json.encode({'jsonrpc': '2.0', 'id': id, 'result': result});
      }

      if (method == 'eth_call') {
        final params = (body['params'] as List).cast<dynamic>();
        final call = (params[0] as Map).cast<String, dynamic>();
        final data = (call['data'] as String).toLowerCase();

        if (data.startsWith('0x313ce567')) {
          return http.Response(ok('0x0000000000000000000000000000000000000000000000000000000000000012'), 200);
        }

        if (data.startsWith('0x70a08231')) {
          return http.Response(ok('0x0000000000000000000000000000000000000000000000000de0b6b3a7640000'), 200);
        }

        return http.Response(ok('0x0'), 200);
      }

      if (method == 'eth_chainId') {
        return http.Response(ok('0x1'), 200);
      }

      if (method == 'eth_blockNumber') {
        return http.Response(ok('0x1'), 200);
      }

      return http.Response(ok(null), 200);
    });

    final evm = EvmSwapService(client: mock);
    final svc = TokenDemoBalanceService(evmSwapService: evm);

    final res = await svc.fetch(owner: EthereumAddress.fromHex('0x0000000000000000000000000000000000000001'));

    expect(res.decimals, 18);
    expect(res.balance, BigInt.parse('1000000000000000000'));
  });
}
