import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wallet/wallet.dart';

import 'wallet_account.dart';
import 'wallet_auth_service.dart';
import 'pas_balance_service.dart';
import 'token_demo_balance_service.dart';
import 'wallet_repository.dart';
import 'wallet_service.dart';

class WalletState extends ChangeNotifier {
  WalletState({
    WalletRepository? repository,
    WalletService? walletService,
    WalletAuthService? authService,
    PasBalanceService? pasBalanceService,
    TokenDemoBalanceService? tokenDemoBalanceService,
  })  : _repository = repository ?? WalletRepository(),
        _walletService = walletService ?? WalletService(),
        _authService = authService ?? WalletAuthService(),
        _pasBalanceService = pasBalanceService ?? const PasBalanceService(),
        _tokenDemoBalanceService = tokenDemoBalanceService ?? TokenDemoBalanceService() {
    _initialize();
  }

  final WalletRepository _repository;
  final WalletService _walletService;
  final WalletAuthService _authService;
  final PasBalanceService _pasBalanceService;
  final TokenDemoBalanceService _tokenDemoBalanceService;

  bool _loading = true;
  WalletAccount? _activeAccount;
  String? _pendingMnemonic;
  String? _error;

  BigInt? _pasBalance;
  bool _pasBalanceLoading = false;
  String? _pasBalanceError;

  BigInt? _tokenDemoBalance;
  int? _tokenDemoDecimals;
  bool _tokenDemoBalanceLoading = false;
  String? _tokenDemoBalanceError;

  bool get loading => _loading;
  WalletAccount? get activeAccount => _activeAccount;
  String? get pendingMnemonic => _pendingMnemonic;
  String? get error => _error;

  BigInt? get pasBalance => _pasBalance;
  bool get pasBalanceLoading => _pasBalanceLoading;
  String? get pasBalanceError => _pasBalanceError;

  BigInt? get tokenDemoBalance => _tokenDemoBalance;
  bool get tokenDemoBalanceLoading => _tokenDemoBalanceLoading;
  String? get tokenDemoBalanceError => _tokenDemoBalanceError;

  String? get pasBalanceFormatted {
    final value = _pasBalance;
    if (value == null) return null;
    return _formatUnits(value, _pasBalanceService.decimals);
  }

  String? get tokenDemoBalanceFormatted {
    final value = _tokenDemoBalance;
    final decimals = _tokenDemoDecimals;
    if (value == null || decimals == null) return null;
    return _formatUnits(value, decimals);
  }

  Future<void> _initialize() async {
    try {
      _loading = true;
      _error = null;
      notifyListeners();

      final mnemonic = await _repository.getMnemonic();
      if (mnemonic == null || mnemonic.trim().isEmpty) {
        _activeAccount = null;
        return;
      }

      _activeAccount = await _walletService.deriveAccountFromMnemonic(mnemonic: mnemonic);

      await refreshPasBalance();
      await refreshTokenDemoBalance();
    } catch (e) {
      _error = '加载钱包失败';
      _activeAccount = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void startCreateWallet() {
    _error = null;
    _pendingMnemonic = _walletService.generateMnemonic();
    notifyListeners();
  }

  void cancelCreateWallet() {
    _error = null;
    _pendingMnemonic = null;
    notifyListeners();
  }

  Future<void> confirmCreateWallet() async {
    if (_pendingMnemonic == null) return;

    try {
      _loading = true;
      _error = null;
      notifyListeners();

      final mnemonic = _pendingMnemonic!;
      await _repository.setMnemonic(mnemonic);
      _activeAccount = await _walletService.deriveAccountFromMnemonic(mnemonic: mnemonic);
      _pendingMnemonic = null;

      await refreshPasBalance();
      await refreshTokenDemoBalance();
    } catch (e) {
      _error = '创建钱包失败';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> importWallet(String mnemonic) async {
    final trimmed = mnemonic.trim();
    if (!_walletService.validateMnemonic(trimmed)) {
      _error = '助记词无效';
      notifyListeners();
      return;
    }

    try {
      _loading = true;
      _error = null;
      notifyListeners();

      await _repository.setMnemonic(trimmed);
      _activeAccount = await _walletService.deriveAccountFromMnemonic(mnemonic: trimmed);

      await refreshPasBalance();
      await refreshTokenDemoBalance();
    } catch (e) {
      _error = '导入钱包失败';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> authenticateForSigning() async {
    return _authService.authenticateForSensitiveOperation(reason: '验证以进行签名');
  }

  Future<WalletAuthResult> authenticateForSigningDetailed() async {
    return _authService.authenticateForSensitiveOperationDetailed(reason: '验证以进行签名');
  }

  Future<String?> getMnemonicForSigning() async {
    return _repository.getMnemonic();
  }

  Future<void> resetWallet() async {
    try {
      _loading = true;
      _error = null;
      notifyListeners();

      await _repository.clear();
      _activeAccount = null;
      _pendingMnemonic = null;
      _pasBalance = null;
      _pasBalanceError = null;
      _tokenDemoBalance = null;
      _tokenDemoDecimals = null;
      _tokenDemoBalanceLoading = false;
      _tokenDemoBalanceError = null;
    } catch (e) {
      _error = '重置钱包失败';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshPasBalance() async {
    final account = _activeAccount;
    if (account == null) {
      _pasBalance = null;
      _pasBalanceError = null;
      _pasBalanceLoading = false;
      notifyListeners();
      return;
    }

    if (_pasBalanceLoading) return;

    _pasBalanceLoading = true;
    _pasBalanceError = null;
    notifyListeners();

    try {
      _pasBalance = await _pasBalanceService.fetchFreeBalance(accountId: account.accountId);
    } catch (e, st) {
      if (e is PasBalanceFetchException) {
        final cause = e.cause;
        if (cause is TimeoutException) {
          _pasBalanceError = '获取 PAS 余额失败：请求超时，请稍后重试';
        } else if (cause is StateError) {
          _pasBalanceError = '获取 PAS 余额失败：链数据解析失败';
        } else {
          _pasBalanceError = '获取 PAS 余额失败：网络节点不可用，请稍后重试';
        }

        if (kDebugMode) {
          _pasBalanceError = '${_pasBalanceError!}\n(${cause.runtimeType}: $cause)';
        }
        if (kDebugMode) {
          debugPrint('PAS balance fetch failed. attempted=${e.attemptedEndpoints} cause=${e.cause}');
          if (e.causeStackTrace != null) {
            debugPrint(e.causeStackTrace.toString());
          }
        }
      } else {
        _pasBalanceError = '获取 PAS 余额失败：${e.toString()}';
        if (kDebugMode) {
          debugPrint('PAS balance fetch failed: $e');
          debugPrint(st.toString());
        }
      }
    } finally {
      _pasBalanceLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshTokenDemoBalance() async {
    final account = _activeAccount;
    if (account == null) {
      _tokenDemoBalance = null;
      _tokenDemoDecimals = null;
      _tokenDemoBalanceError = null;
      _tokenDemoBalanceLoading = false;
      notifyListeners();
      return;
    }

    if (_tokenDemoBalanceLoading) return;

    _tokenDemoBalanceLoading = true;
    _tokenDemoBalanceError = null;
    notifyListeners();

    try {
      final owner = EthereumAddress.fromHex(account.evmAddress);
      final res = await _tokenDemoBalanceService.fetch(owner: owner);
      _tokenDemoBalance = res.balance;
      _tokenDemoDecimals = res.decimals;
    } catch (e, st) {
      if (e is TimeoutException) {
        _tokenDemoBalanceError = '获取 TokenDemo 余额失败：请求超时，请稍后重试';
      } else {
        _tokenDemoBalanceError = '获取 TokenDemo 余额失败：${e.toString()}';
      }

      if (kDebugMode) {
        debugPrint('TokenDemo balance fetch failed: $e');
        debugPrint(st.toString());
      }
    } finally {
      _tokenDemoBalanceLoading = false;
      notifyListeners();
    }
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
}
