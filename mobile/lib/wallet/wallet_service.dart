import 'dart:typed_data';

import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:convert/convert.dart' as convert;
import 'package:pointycastle/digests/keccak.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart';

import 'evm_key_service.dart';
import 'wallet_account.dart';

class WalletService {
  WalletService({Keyring? keyring, EvmKeyService? evmKeyService})
      : _keyring = keyring ?? Keyring(),
        _evmKeyService = evmKeyService ?? const EvmKeyService();

  final Keyring _keyring;
  final EvmKeyService _evmKeyService;

  String generateMnemonic() {
    final mnemonic = Mnemonic.generate(
      Language.english,
      length: MnemonicLength.words12,
    );
    return mnemonic.sentence;
  }

  bool validateMnemonic(String mnemonic) {
    try {
      Mnemonic.fromSentence(mnemonic.trim(), Language.english);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<WalletAccount> deriveAccountFromMnemonic({
    required String mnemonic,
    String name = '账户 1',
  }) async {
    final keyPair = await _keyring.fromMnemonic(mnemonic.trim());

    final evmCreds = await _evmKeyService.deriveCredentialsFromMnemonic(mnemonic: mnemonic.trim());

    final accountId = Uint8List.fromList(keyPair.publicKey.bytes);
    final evmAddress = evmCreds.address.with0x.toLowerCase();

    final id = convert.hex.encode(accountId);

    return WalletAccount(
      id: id,
      name: name,
      ss58Address: keyPair.address,
      accountId: accountId,
      evmAddress: evmAddress,
    );
  }

  String mapSubstrateAccountIdToEvmAddress(Uint8List accountId) {
    return _mapSubstrateAccountIdToEvmAddress(accountId);
  }

  String _mapSubstrateAccountIdToEvmAddress(Uint8List accountId) {
    if (accountId.length != 32) {
      throw StateError('accountId must be 32 bytes');
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
}
