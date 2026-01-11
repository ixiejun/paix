import 'dart:typed_data';

import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:convert/convert.dart' as convert;
import 'package:pointycastle/api.dart' as pc;
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:web3dart/web3dart.dart';

class EvmKeyService {
  const EvmKeyService();

  static final BigInt _secp256k1N = BigInt.parse(
    'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141',
    radix: 16,
  );

  static const int _hardenedOffset = 0x80000000;

  Uint8List _hmacSha512({required Uint8List key, required Uint8List data}) {
    final hmac = HMac(SHA512Digest(), 128)..init(pc.KeyParameter(key));
    hmac.update(data, 0, data.length);
    final out = Uint8List(64);
    hmac.doFinal(out, 0);
    return out;
  }

  BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  Uint8List _bigIntTo32(BigInt v) {
    final out = Uint8List(32);
    var tmp = v;
    for (var i = 31; i >= 0; i--) {
      out[i] = (tmp & BigInt.from(0xff)).toInt();
      tmp = tmp >> 8;
    }
    return out;
  }

  Uint8List _ser32(int i) {
    final out = Uint8List(4);
    out[0] = (i >> 24) & 0xff;
    out[1] = (i >> 16) & 0xff;
    out[2] = (i >> 8) & 0xff;
    out[3] = i & 0xff;
    return out;
  }

  Uint8List _concat(List<Uint8List> parts) {
    final total = parts.fold<int>(0, (p, e) => p + e.length);
    final out = Uint8List(total);
    var offset = 0;
    for (final p in parts) {
      out.setRange(offset, offset + p.length, p);
      offset += p.length;
    }
    return out;
  }

  ({BigInt key, Uint8List chainCode}) _ckdPriv({
    required BigInt parentKey,
    required Uint8List parentChainCode,
    required int index,
  }) {
    final curve = ECCurve_secp256k1();
    final G = curve.G;

    final bool hardened = index >= _hardenedOffset;
    Uint8List data;

    if (hardened) {
      data = _concat([
        Uint8List.fromList([0x00]),
        _bigIntTo32(parentKey),
        _ser32(index),
      ]);
    } else {
      final ECPoint? pub = G * parentKey;
      if (pub == null) {
        throw StateError('Invalid public key derived from private key');
      }
      final pubCompressed = pub.getEncoded(true);
      data = _concat([pubCompressed, _ser32(index)]);
    }

    final I = _hmacSha512(key: parentChainCode, data: data);
    final ilBytes = Uint8List.sublistView(I, 0, 32);
    final irBytes = Uint8List.sublistView(I, 32, 64);
    final ilInt = _bytesToBigInt(ilBytes);

    if (ilInt >= _secp256k1N) {
      throw StateError('Invalid child key (IL >= n)');
    }

    final childKey = (ilInt + parentKey) % _secp256k1N;
    if (childKey == BigInt.zero) {
      throw StateError('Invalid child key (derived key == 0)');
    }

    return (key: childKey, chainCode: Uint8List.fromList(irBytes));
  }

  Future<EthPrivateKey> deriveCredentialsFromMnemonic({required String mnemonic, String passphrase = ''}) async {
    final m = Mnemonic.fromSentence(mnemonic.trim(), Language.english, passphrase: passphrase);
    final seed = Uint8List.fromList(m.seed);

    // Master key: I = HMAC-SHA512(key="Bitcoin seed", data=seed)
    final I = _hmacSha512(
      key: Uint8List.fromList('Bitcoin seed'.codeUnits),
      data: seed,
    );

    final ilBytes = Uint8List.sublistView(I, 0, 32);
    final irBytes = Uint8List.sublistView(I, 32, 64);
    var key = _bytesToBigInt(ilBytes);
    if (key == BigInt.zero || key >= _secp256k1N) {
      throw StateError('Invalid master key derived from seed');
    }
    var chainCode = Uint8List.fromList(irBytes);

    // m/44'/60'/0'/0/0
    final path = <int>[
      44 | _hardenedOffset,
      60 | _hardenedOffset,
      0 | _hardenedOffset,
      0,
      0,
    ];

    for (final p in path) {
      final child = _ckdPriv(parentKey: key, parentChainCode: chainCode, index: p);
      key = child.key;
      chainCode = child.chainCode;
    }

    final pkBytes = _bigIntTo32(key);
    final hexPk = convert.hex.encode(pkBytes);
    return EthPrivateKey.fromHex('0x$hexPk');
  }
}
