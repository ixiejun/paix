import 'package:local_auth/local_auth.dart';

class WalletAuthResult {
  const WalletAuthResult({required this.ok, this.code, this.message});

  final bool ok;
  final String? code;
  final String? message;
}

class WalletAuthService {
  WalletAuthService({LocalAuthentication? localAuthentication})
      : _localAuthentication = localAuthentication ?? LocalAuthentication();

  final LocalAuthentication _localAuthentication;

  Future<WalletAuthResult> authenticateForSensitiveOperationDetailed({required String reason}) async {
    try {
      final canCheckBiometrics = await _localAuthentication.canCheckBiometrics;
      final isDeviceSupported = await _localAuthentication.isDeviceSupported();

      if (!canCheckBiometrics && !isDeviceSupported) {
        return const WalletAuthResult(
          ok: false,
          code: 'not_supported',
          message: '设备不支持本地认证/生物识别',
        );
      }

      final ok = await _localAuthentication.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
      if (ok) {
        return const WalletAuthResult(ok: true);
      }

      // local_auth returns false for user cancel / failure without throwing.
      return const WalletAuthResult(
        ok: false,
        code: 'not_authenticated',
        message: '用户取消或验证失败',
      );
    } on LocalAuthException catch (e) {
      final details = e.details?.toString();
      return WalletAuthResult(
        ok: false,
        code: e.code.name,
        message: e.description ?? details,
      );
    } on Exception catch (e) {
      return WalletAuthResult(ok: false, code: 'exception', message: e.toString());
    }
  }

  Future<bool> authenticateForSensitiveOperation({required String reason}) async {
    final res = await authenticateForSensitiveOperationDetailed(reason: reason);
    return res.ok;
  }
}
