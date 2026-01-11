import 'dart:async';
import 'dart:typed_data';

import 'package:polkadart/apis/apis.dart' show ChainDataFetcher, Provider, StateApi;
import 'package:polkadart/extrinsic_builder/extrinsic_builder_base.dart' show ExtrinsicBuilder;
import 'package:polkadart/helpers/call_indices_lookup.dart' show CallIndicesLookup;
import 'package:polkadart/primitives/primitives.dart' show ExtrinsicStatus;
import 'package:polkadart_keyring/polkadart_keyring.dart' as keyring;
import 'package:polkadart_scale_codec/io/io.dart' show ByteOutput;
import 'package:substrate_metadata/chain/chain_info.dart' show ChainInfo;
import 'package:substrate_metadata/metadata/metadata.dart' show RuntimeMetadataPrefixed;
import 'package:substrate_metadata/models/models.dart' show RuntimeCall;

class XcmTransferService {
  const XcmTransferService();

  Future<XcmTransferResult> transferPasToEvmAddress({
    required String originWs,
    required String mnemonic,
    required int destinationParachainId,
    required Uint8List beneficiaryEvmAddress20,
    required BigInt amountInOriginPlanck,
    required void Function(XcmTransferProgress progress) onProgress,
    Duration timeout = const Duration(minutes: 4),
  }) async {
    final provider = Provider.fromUri(Uri.parse(originWs));

    final kr = keyring.Keyring.sr25519;
    final keyPair = await kr.fromMnemonic(mnemonic.trim());

    final completed = Completer<XcmTransferResult>();
    StreamSubscription<ExtrinsicStatus>? sub;

    try {
      final RuntimeMetadataPrefixed runtimeMetadataPrefixed = await StateApi(provider).getMetadata();
      final ChainInfo chainInfo = runtimeMetadataPrefixed.buildChainInfo();

      final callData = _buildXcmCallData(
        chainInfo: chainInfo,
        destinationParachainId: destinationParachainId,
        beneficiaryEvmAddress20: beneficiaryEvmAddress20,
        amountInPlanck: amountInOriginPlanck,
      );

      final chainData = await ChainDataFetcher(provider).fetchStandardData(accountAddress: keyPair.address);

      final builder = ExtrinsicBuilder.fromChainData(
        chainInfo: chainInfo,
        callData: callData,
        chainData: chainData,
      );

      sub = await builder.signBuildAndSubmitWatch(
        provider: provider,
        signerAddress: keyPair.address,
        signingCallback: (payload) => keyPair.sign(payload),
        onStatusChange: (status) {
          if (status.isInBlock) {
            onProgress(XcmTransferProgressInBlock(blockHashHex: status.blockHash));
          } else if (status.isFinalized) {
            onProgress(XcmTransferProgressFinalized(blockHashHex: status.blockHash));
            if (!completed.isCompleted) {
              completed.complete(XcmTransferResult(finalizedBlockHashHex: status.blockHash));
            }
          } else if (status.isInvalid || status.isDropped || status.isError) {
            onProgress(XcmTransferProgressFailed(detail: status.toString()));
            if (!completed.isCompleted) {
              completed.completeError(StateError('xcm extrinsic failed: $status'));
            }
          } else {
            onProgress(XcmTransferProgressStatus(status: status));
          }
        },
      );

      return await completed.future.timeout(timeout);
    } finally {
      try {
        await sub?.cancel();
      } catch (_) {}
      try {
        await provider.disconnect();
      } catch (_) {}
    }
  }

  Uint8List _buildXcmCallData({
    required ChainInfo chainInfo,
    required int destinationParachainId,
    required Uint8List beneficiaryEvmAddress20,
    required BigInt amountInPlanck,
  }) {
    final lookup = CallIndicesLookup(chainInfo);

    final palletName = _firstExistingPallet(chainInfo, const ['PolkadotXcm', 'XcmPallet']);
    if (palletName == null) {
      throw StateError('XCM pallet not found in metadata');
    }

    final callName = _firstExistingCall(
      lookup,
      palletName,
      const [
        'limited_teleport_assets',
        'limitedTeleportAssets',
        'teleport_assets',
        'teleportAssets',
        'limited_reserve_transfer_assets',
        'limitedReserveTransferAssets',
        'reserve_transfer_assets',
        'reserveTransferAssets',
      ],
    );
    if (callName == null) {
      throw StateError('XCM transfer call not found in metadata');
    }

    final indices = lookup.getPalletAndCallIndex(palletName: palletName, callName: callName);

    // Try V4 first, then V3 if encoding fails.
    final v4Args = _buildLimitedReserveTransferAssetsArgsV4(
      destinationParachainId: destinationParachainId,
      beneficiaryEvmAddress20: beneficiaryEvmAddress20,
      amountInPlanck: amountInPlanck,
    );

    try {
      return _encodeRuntimeCall(
        chainInfo: chainInfo,
        palletName: palletName,
        palletIndex: indices.palletIndex,
        callName: callName,
        callIndex: indices.callIndex,
        args: v4Args,
      );
    } catch (_) {
      final v3Args = _buildLimitedReserveTransferAssetsArgsV3(
        destinationParachainId: destinationParachainId,
        beneficiaryEvmAddress20: beneficiaryEvmAddress20,
        amountInPlanck: amountInPlanck,
      );
      return _encodeRuntimeCall(
        chainInfo: chainInfo,
        palletName: palletName,
        palletIndex: indices.palletIndex,
        callName: callName,
        callIndex: indices.callIndex,
        args: v3Args,
      );
    }
  }

  Uint8List _encodeRuntimeCall({
    required ChainInfo chainInfo,
    required String palletName,
    required int palletIndex,
    required String callName,
    required int callIndex,
    required Map<String, dynamic> args,
  }) {
    final call = RuntimeCall(
      palletName: palletName,
      palletIndex: palletIndex,
      callName: callName,
      callIndex: callIndex,
      args: args,
    );

    final out = ByteOutput();
    chainInfo.callsCodec.encodeTo(call, out);
    return out.toBytes();
  }

  String? _firstExistingPallet(ChainInfo chainInfo, List<String> candidates) {
    final names = chainInfo.pallets.map((p) => p.name).toSet();
    for (final c in candidates) {
      if (names.contains(c)) return c;
    }
    return null;
  }

  String? _firstExistingCall(CallIndicesLookup lookup, String palletName, List<String> candidates) {
    for (final c in candidates) {
      try {
        lookup.getCallIndex(palletName, c);
        return c;
      } catch (_) {}
    }
    return null;
  }

  Map<String, dynamic> _buildLimitedReserveTransferAssetsArgsV4({
    required int destinationParachainId,
    required Uint8List beneficiaryEvmAddress20,
    required BigInt amountInPlanck,
  }) {
    final beneficiaryAccountId32 = _evmToAccountId32(beneficiaryEvmAddress20);

    final dest = MapEntry(
      'V4',
      {
        'parents': 1,
        'interior': MapEntry(
          'X1',
          MapEntry('Parachain', destinationParachainId),
        ),
      },
    );

    final beneficiary = MapEntry(
      'V4',
      {
        'parents': 0,
        'interior': MapEntry(
          'X1',
          MapEntry('AccountId32', {'network': null, 'id': beneficiaryAccountId32}),
        ),
      },
    );

    final assetIdHere = {
      'parents': 1,
      'interior': const MapEntry('Here', null),
    };

    final assets = MapEntry(
      'V4',
      [
        {
          'id': MapEntry('Concrete', assetIdHere),
          'fun': MapEntry('Fungible', amountInPlanck),
        },
      ],
    );

    return {
      'dest': dest,
      'beneficiary': beneficiary,
      'assets': assets,
      'fee_asset_item': 0,
      'weight_limit': const MapEntry('Unlimited', null),

      // Common alternative field names across runtimes
      'feeAssetItem': 0,
      'weightLimit': const MapEntry('Unlimited', null),
    };
  }

  Map<String, dynamic> _buildLimitedReserveTransferAssetsArgsV3({
    required int destinationParachainId,
    required Uint8List beneficiaryEvmAddress20,
    required BigInt amountInPlanck,
  }) {
    final beneficiaryAccountId32 = _evmToAccountId32(beneficiaryEvmAddress20);

    final dest = MapEntry(
      'V3',
      {
        'parents': 1,
        'interior': MapEntry(
          'X1',
          MapEntry('Parachain', destinationParachainId),
        ),
      },
    );

    final beneficiary = MapEntry(
      'V3',
      {
        'parents': 0,
        'interior': MapEntry(
          'X1',
          MapEntry('AccountId32', {'network': null, 'id': beneficiaryAccountId32}),
        ),
      },
    );

    final assetIdHere = {
      'parents': 1,
      'interior': const MapEntry('Here', null),
    };

    final assets = MapEntry(
      'V3',
      [
        {
          'id': MapEntry('Concrete', assetIdHere),
          'fun': MapEntry('Fungible', amountInPlanck),
        },
      ],
    );

    return {
      'dest': dest,
      'beneficiary': beneficiary,
      'assets': assets,
      'fee_asset_item': 0,
      'weight_limit': const MapEntry('Unlimited', null),

      // Common alternative field names across runtimes
      'feeAssetItem': 0,
      'weightLimit': const MapEntry('Unlimited', null),
    };
  }

  Uint8List _evmToAccountId32(Uint8List h160) {
    if (h160.length != 20) {
      throw StateError('beneficiaryEvmAddress20 must be 20 bytes');
    }
    final out = Uint8List(32);
    out.setRange(0, 20, h160);
    for (var i = 20; i < 32; i++) {
      out[i] = 0xEE;
    }
    return out;
  }
}

class XcmTransferResult {
  const XcmTransferResult({required this.finalizedBlockHashHex});

  final String? finalizedBlockHashHex;
}

sealed class XcmTransferProgress {
  const XcmTransferProgress();
}

class XcmTransferProgressStatus extends XcmTransferProgress {
  const XcmTransferProgressStatus({required this.status});

  final ExtrinsicStatus status;
}

class XcmTransferProgressInBlock extends XcmTransferProgress {
  const XcmTransferProgressInBlock({required this.blockHashHex});

  final String? blockHashHex;
}

class XcmTransferProgressFinalized extends XcmTransferProgress {
  const XcmTransferProgressFinalized({required this.blockHashHex});

  final String? blockHashHex;
}

class XcmTransferProgressFailed extends XcmTransferProgress {
  const XcmTransferProgressFailed({required this.detail});

  final String detail;
}
