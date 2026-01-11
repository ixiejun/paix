import 'dart:typed_data';

class WalletAccount {
  WalletAccount({
    required this.id,
    required this.name,
    required this.ss58Address,
    required this.accountId,
    required this.evmAddress,
  });

  final String id;
  final String name;
  final String ss58Address;
  final Uint8List accountId;
  final String evmAddress;
}
