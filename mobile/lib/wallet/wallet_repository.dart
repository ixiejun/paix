import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class WalletRepository {
  WalletRepository({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  static const _mnemonicKey = 'wallet.mnemonic';

  Future<String?> getMnemonic() async {
    return _secureStorage.read(key: _mnemonicKey);
  }

  Future<void> setMnemonic(String mnemonic) async {
    await _secureStorage.write(key: _mnemonicKey, value: mnemonic);
  }

  Future<void> clear() async {
    await _secureStorage.delete(key: _mnemonicKey);
  }
}
