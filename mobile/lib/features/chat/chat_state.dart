import 'dart:collection';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:convert/convert.dart' as convert;
import 'package:wallet/wallet.dart';

import 'agent_service.dart';
import 'chat_models.dart';
import 'chat_repository.dart';
import 'buy_execution_plan.dart';
import 'buy_execution_status.dart';
import 'strategy_recommendation.dart';
import '../../wallet/evm_key_service.dart';
import '../../wallet/evm_swap_service.dart';
import '../../wallet/xcm_transfer_service.dart';
import '../../wallet/wallet_network_config.dart';

class ChatState extends ChangeNotifier {
  ChatState({AgentService? agentService, ChatRepository? repository})
      : _agentService = agentService ?? AgentService(),
        _repository = repository ?? SecureChatRepository() {
    _messages.add(
      ChatMessage.assistant(
        '告诉我你想做什么。\n\n示例：\n- 用 200U 买 BTC\n- 推荐适合当下 BTC 的交易策略\n- 创建定投计划：DOT 每周 100U，跌破 5U 停止\n\n```json\n{\n  "intent": "dca.create",\n  "asset": "DOT",\n  "amount_usd": 100,\n  "interval": "weekly",\n  "stop_below": 5\n}\n```',
      ),
    );

    unawaited(_initialize());
  }

  final AgentService _agentService;
  final ChatRepository _repository;

  final List<ChatMessage> _messages = [];
  final Map<String, StrategyRecommendation> _recommendationsByMessageId = {};
  final Map<String, StrategyCardStatus> _cardStatusByMessageId = {};
  final Map<String, BuyExecutionPlan> _buyPlansByMessageId = {};
  final Map<String, BuyExecutionStatus> _buyStatusByMessageId = {};
  bool _sending = false;
  bool _streaming = false;
  String? _error;

  final EvmKeyService _evmKeyService = const EvmKeyService();
  final EvmSwapService _evmSwapService = EvmSwapService();
  final XcmTransferService _xcmTransferService = const XcmTransferService();

  String? _cachedSwapEvmRpc;
  String? _cachedSwapRouter;
  String? _cachedSwapWeth;

  String? _sessionId;
  StreamSubscription<AgentStreamEvent>? _streamSub;
  String? _activeAssistantId;
  String _activeAssistantText = '';
  final ListQueue<int> _pendingAssistantRunes = ListQueue<int>();
  Timer? _typewriterTimer;
  String? _lastUserMessage;
  int _revision = 0;
  Timer? _persistTimer;

  UnmodifiableListView<ChatMessage> get messages => UnmodifiableListView(_messages);
  bool get sending => _sending;
  bool get streaming => _streaming;
  String? get error => _error;
  int get revision => _revision;

  StrategyRecommendation? recommendationForMessage(String messageId) {
    return _recommendationsByMessageId[messageId];
  }

  BuyExecutionPlan? buyPlanForMessage(String messageId) {
    return _buyPlansByMessageId[messageId];
  }

  BuyExecutionStatus? buyStatusForMessage(String messageId) {
    return _buyStatusByMessageId[messageId];
  }

  StrategyCardStatus tradeCardStatusForMessage(String messageId) {
    return _cardStatusByMessageId[messageId] ?? StrategyCardStatus.idle;
  }

  void addSystemMessage(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    _messages.add(ChatMessage.assistant(trimmed));
    _bumpRevision();
    _schedulePersistMessages();
    notifyListeners();
  }

  Future<void> executeBuyPlan({
    required String messageId,
    required BuyExecutionPlan plan,
    required String mnemonic,
  }) async {
    final current = _buyStatusByMessageId[messageId];
    if (current?.isBusy == true) return;

    _buyStatusByMessageId[messageId] = (current ?? const BuyExecutionStatus(phase: BuyExecutionPhase.idle)).copyWith(
      phase: BuyExecutionPhase.signing,
      error: null,
    );
    notifyListeners();

    try {
      final raw = plan.raw;
      final steps = raw['steps'];
      Map<String, dynamic>? swapStep;
      Map<String, dynamic>? xcmStep;
      if (steps is List) {
        for (final s in steps) {
          if (s is Map<String, dynamic> && s['kind'] == 'uniswap_v2_swap') {
            swapStep = s;
            continue;
          }
          if (s is Map<String, dynamic> && s['kind'] == 'xcm_transfer') {
            xcmStep = s;
          }
        }
      }

      if (swapStep == null) {
        throw StateError('execution_plan 缺少 swap step');
      }

      final origin = raw['origin'];
      final originWs = (origin is Map<String, dynamic> && origin['substrate_ws'] is String)
          ? (origin['substrate_ws'] as String).trim()
          : '';

      final rpcUrl = (swapStep['evm_rpc'] is String) ? swapStep['evm_rpc'] as String : '';
      final routerRaw = swapStep['router'];
      final wethRaw = swapStep['weth'];
      final tokenOutRaw = swapStep['token_out'];
      final tokenInRaw = swapStep['token_in'];

      final tokenOutAddress = (tokenOutRaw is Map<String, dynamic> && tokenOutRaw['address'] is String)
          ? tokenOutRaw['address'] as String
          : '';
      final tokenInAddress = (tokenInRaw is Map<String, dynamic> && tokenInRaw['address'] is String)
          ? tokenInRaw['address'] as String
          : '';

      if (rpcUrl.trim().isEmpty || routerRaw is! String || wethRaw is! String) {
        throw StateError('swap step 参数不完整（rpc/router/weth）');
      }
      if (plan.isBuy && tokenOutAddress.trim().isEmpty) {
        throw StateError('swap step 参数不完整（token_out.address）');
      }
      if (plan.isSell && tokenInAddress.trim().isEmpty) {
        throw StateError('swap step 参数不完整（token_in.address）');
      }

      final slippageBps = (() {
        final rc = raw['risk_controls'];
        if (rc is Map<String, dynamic> && rc['slippage_bps'] is int) {
          return rc['slippage_bps'] as int;
        }
        return 100;
      })();

      final deadlineSeconds = (() {
        final rc = raw['risk_controls'];
        if (rc is Map<String, dynamic> && rc['deadline_seconds'] is int) {
          return rc['deadline_seconds'] as int;
        }
        return 600;
      })();

      final initialStepIndex = xcmStep != null ? 0 : 2;
      _buyStatusByMessageId[messageId] = BuyExecutionStatus(
        phase: BuyExecutionPhase.submitting,
        stepIndex: initialStepIndex,
        logs: const ['开始执行…'],
      );
      notifyListeners();

      void appendStatusLog(String line, {int? stepIndex, BuyExecutionPhase? phase}) {
        final cur = _buyStatusByMessageId[messageId] ?? const BuyExecutionStatus(phase: BuyExecutionPhase.idle);
        var next = cur;
        if (phase != null) next = next.copyWith(phase: phase);
        if (stepIndex != null) next = next.copyWith(stepIndex: stepIndex);
        next = next.appendLog(line);
        _buyStatusByMessageId[messageId] = next;
        notifyListeners();
      }

      final creds = await _evmKeyService.deriveCredentialsFromMnemonic(mnemonic: mnemonic);

      if (xcmStep != null) {
        if (originWs.isEmpty) {
          throw StateError('execution_plan 缺少 origin.substrate_ws，无法执行 XCM');
        }

        final toPara = (xcmStep['to_parachain_id'] is int) ? xcmStep['to_parachain_id'] as int : 0;
        if (toPara == 0) {
          throw StateError('xcm_transfer step 参数不完整（to_parachain_id）');
        }

        final amountStr = (xcmStep['amount'] is String) ? (xcmStep['amount'] as String).trim() : plan.amount;
        final amountPlanck = _parseDecimalToInt(amountStr, 10);
        if (amountPlanck <= BigInt.zero) {
          throw StateError('xcm_transfer amount 无效');
        }

        final evmToHex = creds.address.toString();
        final beneficiary20 = _hexToFixedBytes(evmToHex, 20);

        appendStatusLog('XCM：提交跨链请求…', stepIndex: 0);

        final beforeWei = await _evmSwapService.getNativeBalanceWei(rpcUrl: rpcUrl.trim(), owner: creds.address);

        await _xcmTransferService.transferPasToEvmAddress(
          originWs: originWs,
          mnemonic: mnemonic,
          destinationParachainId: toPara,
          beneficiaryEvmAddress20: beneficiary20,
          amountInOriginPlanck: amountPlanck,
          onProgress: (p) {
            final msg = switch (p) {
              XcmTransferProgressInBlock(:final blockHashHex) => 'XCM 已入块：${blockHashHex ?? ''}',
              XcmTransferProgressFinalized(:final blockHashHex) => 'XCM 已终局：${blockHashHex ?? ''}',
              XcmTransferProgressFailed(:final detail) => 'XCM 失败：$detail',
              _ => null,
            };
            if (msg != null) {
              appendStatusLog(msg, stepIndex: 0);
            }
          },
        );

        appendStatusLog('XCM：已确认，等待目标链余额到账…', stepIndex: 1);

        await _waitForNativeBalanceIncrease(
          rpcUrl: rpcUrl.trim(),
          owner: creds.address,
          baselineWei: beforeWei,
        );

        appendStatusLog('目标链余额已到账，准备执行 swap…', stepIndex: 2);
      }

      final routerAddr = EthereumAddress.fromHex(routerRaw);
      final wethAddr = EthereumAddress.fromHex(wethRaw);

      appendStatusLog('Swap：发送交易…', stepIndex: 2, phase: BuyExecutionPhase.submitting);

      String txHash;
      BigInt? balanceBefore;
      late final EthereumAddress tokenTrack;
      if (plan.isBuy) {
        final tokenOutAddr = EthereumAddress.fromHex(tokenOutAddress.trim());
        tokenTrack = tokenOutAddr;
        try {
          balanceBefore = await _evmSwapService.getErc20Balance(
            rpcUrl: rpcUrl.trim(),
            token: tokenOutAddr,
            owner: creds.address,
          );
        } catch (_) {
          balanceBefore = null;
        }

        txHash = await _evmSwapService.swapExactEthForTokens(
          rpcUrl: rpcUrl.trim(),
          credentials: creds,
          router: routerAddr,
          weth: wethAddr,
          tokenOut: tokenOutAddr,
          amountIn: EtherAmount.fromBase10String(EtherUnit.ether, plan.amount),
          slippageBps: slippageBps,
          deadline: Duration(seconds: deadlineSeconds),
        );
      } else {
        final tokenInAddr = EthereumAddress.fromHex(tokenInAddress.trim());
        tokenTrack = tokenInAddr;
        final decimals = await _evmSwapService.getErc20Decimals(rpcUrl: rpcUrl.trim(), token: tokenInAddr);
        final amountInRaw = _parseDecimalToInt(plan.amount, decimals);
        if (amountInRaw <= BigInt.zero) {
          throw StateError('sell amount 无效');
        }

        try {
          balanceBefore = await _evmSwapService.getErc20Balance(
            rpcUrl: rpcUrl.trim(),
            token: tokenInAddr,
            owner: creds.address,
          );
        } catch (_) {
          balanceBefore = null;
        }

        final allowance = await _evmSwapService.getErc20Allowance(
          rpcUrl: rpcUrl.trim(),
          token: tokenInAddr,
          owner: creds.address,
          spender: routerAddr,
        );
        if (allowance < amountInRaw) {
          appendStatusLog('Approve：发送授权…', stepIndex: 2);
          final approveHash = await _evmSwapService.approveErc20(
            rpcUrl: rpcUrl.trim(),
            credentials: creds,
            token: tokenInAddr,
            spender: routerAddr,
            amount: amountInRaw,
          );
          appendStatusLog('Approve：已提交 $approveHash', stepIndex: 2);
          appendStatusLog('Approve：等待确认…', stepIndex: 2);
          final approveReceipt = await _evmSwapService.waitForReceipt(
            rpcUrl: rpcUrl.trim(),
            txHash: approveHash,
          );
          if (approveReceipt == null || approveReceipt.status != true) {
            throw StateError('approve 失败或确认超时');
          }
        }

        txHash = await _evmSwapService.swapExactTokensForEth(
          rpcUrl: rpcUrl.trim(),
          credentials: creds,
          router: routerAddr,
          weth: wethAddr,
          tokenIn: tokenInAddr,
          amountIn: amountInRaw,
          slippageBps: slippageBps,
          deadline: Duration(seconds: deadlineSeconds),
        );
      }

      appendStatusLog('Swap：已提交 $txHash', stepIndex: 3);
      _buyStatusByMessageId[messageId] = (_buyStatusByMessageId[messageId] ?? const BuyExecutionStatus(phase: BuyExecutionPhase.submitted))
          .copyWith(phase: BuyExecutionPhase.submitted, txHash: txHash);
      notifyListeners();

      appendStatusLog('Swap：等待确认…', stepIndex: 3, phase: BuyExecutionPhase.confirming);
      _buyStatusByMessageId[messageId] = (_buyStatusByMessageId[messageId] ?? const BuyExecutionStatus(phase: BuyExecutionPhase.confirming))
          .copyWith(phase: BuyExecutionPhase.confirming, txHash: txHash);
      notifyListeners();

      final receipt = await _evmSwapService.waitForReceipt(
        rpcUrl: rpcUrl.trim(),
        txHash: txHash,
      );

      if (receipt == null) {
        appendStatusLog('失败：确认超时（未拿到 receipt）', phase: BuyExecutionPhase.failed, stepIndex: 3);
        _buyStatusByMessageId[messageId] = (_buyStatusByMessageId[messageId] ?? const BuyExecutionStatus(phase: BuyExecutionPhase.failed))
            .copyWith(
              phase: BuyExecutionPhase.failed,
              txHash: txHash,
              error: '执行失败：交易确认超时（未拿到 receipt）',
            );
        notifyListeners();
        return;
      }

      final ok = receipt.status == true;
      if (!ok) {
        appendStatusLog('失败：swap 回滚（status=false）', phase: BuyExecutionPhase.failed, stepIndex: 3);
        _buyStatusByMessageId[messageId] = (_buyStatusByMessageId[messageId] ?? const BuyExecutionStatus(phase: BuyExecutionPhase.failed))
            .copyWith(
              phase: BuyExecutionPhase.failed,
              txHash: txHash,
              error: '执行失败：swap 交易回滚（status=false）',
            );
        notifyListeners();
        return;
      }

      BigInt? receivedRaw;
      late final int tokenDecimals;
      BigInt? balanceAfter;

      if (plan.isBuy) {
        receivedRaw = _evmSwapService.extractErc20ReceivedAmountFromReceipt(
          receipt: receipt,
          token: tokenTrack,
          recipient: creds.address,
        );
      }

      tokenDecimals = await _evmSwapService.getErc20Decimals(
        rpcUrl: rpcUrl.trim(),
        token: tokenTrack,
      );
      try {
        balanceAfter = await _evmSwapService.getErc20Balance(
          rpcUrl: rpcUrl.trim(),
          token: tokenTrack,
          owner: creds.address,
        );
      } catch (_) {
        balanceAfter = null;
      }

      BigInt? deltaRaw;
      if (balanceBefore != null && balanceAfter != null) {
        if (plan.isBuy && balanceAfter >= balanceBefore) {
          deltaRaw = balanceAfter - balanceBefore;
        }
        if (plan.isSell && balanceAfter <= balanceBefore) {
          deltaRaw = balanceBefore - balanceAfter;
        }
      } else if (plan.isBuy && (receivedRaw ?? BigInt.zero) > BigInt.zero) {
        deltaRaw = receivedRaw;
      }

      final receivedText = (deltaRaw != null && deltaRaw > BigInt.zero) ? _formatTokenAmount(deltaRaw, tokenDecimals) : null;
      final balanceText = (balanceAfter != null) ? _formatTokenAmount(balanceAfter, tokenDecimals) : null;

      appendStatusLog(
        receivedText != null ? '确认成功：收到 $receivedText' : '确认成功',
        phase: BuyExecutionPhase.confirmed,
        stepIndex: 3,
      );

      _buyStatusByMessageId[messageId] = (_buyStatusByMessageId[messageId] ?? const BuyExecutionStatus(phase: BuyExecutionPhase.confirmed))
          .copyWith(
            phase: BuyExecutionPhase.confirmed,
            txHash: txHash,
            receivedTokenAmount: receivedText,
            tokenBalance: balanceText,
          );
      notifyListeners();
    } catch (e) {
      final cur = _buyStatusByMessageId[messageId] ?? const BuyExecutionStatus(phase: BuyExecutionPhase.failed);
      _buyStatusByMessageId[messageId] = cur
          .appendLog('失败：${e.toString()}')
          .copyWith(
            phase: BuyExecutionPhase.failed,
            error: '执行失败：${e.toString()}',
          );
      notifyListeners();
    }
  }

  Uint8List _hexToFixedBytes(String hex, int length) {
    var s = hex.trim();
    if (s.startsWith('0x')) s = s.substring(2);
    if (s.length != length * 2) {
      throw StateError('invalid hex length for $hex');
    }
    return Uint8List.fromList(convert.hex.decode(s));
  }

  BigInt _parseDecimalToInt(String amount, int decimals) {
    final s = amount.trim();
    if (s.isEmpty) return BigInt.zero;
    final parts = s.split('.');
    final whole = parts[0].isEmpty ? '0' : parts[0];
    final frac = parts.length > 1 ? parts[1] : '';
    final fracPadded = (frac.length >= decimals) ? frac.substring(0, decimals) : frac.padRight(decimals, '0');
    final combined = whole + fracPadded;
    final normalized = combined.replaceFirst(RegExp(r'^0+'), '');
    if (normalized.isEmpty) return BigInt.zero;
    return BigInt.parse(normalized);
  }

  Future<void> _waitForNativeBalanceIncrease({
    required String rpcUrl,
    required EthereumAddress owner,
    required BigInt baselineWei,
    Duration timeout = const Duration(minutes: 4),
    Duration pollInterval = const Duration(seconds: 6),
  }) async {
    final started = DateTime.now();
    while (DateTime.now().difference(started) < timeout) {
      final nowWei = await _evmSwapService.getNativeBalanceWei(rpcUrl: rpcUrl, owner: owner);
      if (nowWei > baselineWei) return;
      await Future.delayed(pollInterval);
    }
    throw StateError('等待目标链余额到账超时');
  }

  String _formatTokenAmount(BigInt raw, int decimals) {
    if (decimals <= 0) return raw.toString();
    final s = raw.toString();
    if (s == '0') return '0';

    final pad = decimals + 1;
    final padded = s.padLeft(pad, '0');
    final intPart = padded.substring(0, padded.length - decimals);
    var frac = padded.substring(padded.length - decimals);
    frac = frac.replaceFirst(RegExp(r'0+$'), '');
    if (frac.isEmpty) return intPart;
    final limited = frac.length > 6 ? frac.substring(0, 6) : frac;
    return '$intPart.$limited';
  }

  void observeTradeCard(String messageId) {
    if (!_recommendationsByMessageId.containsKey(messageId)) return;
    final current = _cardStatusByMessageId[messageId] ?? StrategyCardStatus.idle;
    if (current != StrategyCardStatus.idle) return;
    _cardStatusByMessageId[messageId] = StrategyCardStatus.observed;
    _bumpRevision();
    notifyListeners();
  }

  void confirmExecuteTradeCard(String messageId, {String? amountUsd}) {
    if (!_recommendationsByMessageId.containsKey(messageId)) return;
    final current = _cardStatusByMessageId[messageId] ?? StrategyCardStatus.idle;
    if (current != StrategyCardStatus.idle) return;

    _cardStatusByMessageId[messageId] = StrategyCardStatus.executed;
    final amountPart = (amountUsd != null && amountUsd.trim().isNotEmpty) ? '投入：${amountUsd.trim()}U\n' : '';
    _messages.add(ChatMessage.assistant('$amountPart已确认执行（演示，不会真实交易）。'));
    _bumpRevision();
    _schedulePersistMessages();
    notifyListeners();
  }

  @override
  void dispose() {
    final sub = _streamSub;
    _streamSub = null;
    if (sub != null) {
      sub.cancel();
    }

    final timer = _typewriterTimer;
    _typewriterTimer = null;
    timer?.cancel();

    final persist = _persistTimer;
    _persistTimer = null;
    persist?.cancel();

    super.dispose();
  }

  void _schedulePersistMessages() {
    final t = _persistTimer;
    if (t != null) return;

    _persistTimer = Timer(const Duration(milliseconds: 500), () async {
      _persistTimer = null;
      try {
        final snapshot = List<ChatMessage>.from(_messages);
        final capped = snapshot.length > 50 ? snapshot.sublist(snapshot.length - 50) : snapshot;
        await _repository.setMessages(capped);
      } catch (_) {}
    });
  }

  void _enqueueAssistantDelta(String delta) {
    if (delta.isEmpty) return;
    _pendingAssistantRunes.addAll(delta.runes);
    _ensureTypewriterRunning();
  }

  void _ensureTypewriterRunning() {
    if (_typewriterTimer != null) return;
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 35), (_) {
      if (_pendingAssistantRunes.isEmpty) {
        final t = _typewriterTimer;
        _typewriterTimer = null;
        t?.cancel();
        return;
      }

      final id = _activeAssistantId;
      if (id == null) {
        _pendingAssistantRunes.clear();
        final t = _typewriterTimer;
        _typewriterTimer = null;
        t?.cancel();
        return;
      }

      var take = 2;
      if (_pendingAssistantRunes.length > 120) {
        take = 6;
      } else if (_pendingAssistantRunes.length > 40) {
        take = 4;
      }

      final out = <int>[];
      for (var i = 0; i < take && _pendingAssistantRunes.isNotEmpty; i++) {
        out.add(_pendingAssistantRunes.removeFirst());
      }
      _activeAssistantText += String.fromCharCodes(out);
      _updateAssistantMessage(id: id, content: _activeAssistantText, status: ChatMessageStatus.streaming);
    });
  }

  void _stopTypewriter({bool flush = false, ChatMessageStatus? finalStatus}) {
    final t = _typewriterTimer;
    _typewriterTimer = null;
    t?.cancel();

    if (flush && _pendingAssistantRunes.isNotEmpty) {
      final remaining = String.fromCharCodes(_pendingAssistantRunes);
      _pendingAssistantRunes.clear();
      _activeAssistantText += remaining;
    } else {
      _pendingAssistantRunes.clear();
    }

    final id = _activeAssistantId;
    if (flush && id != null) {
      _updateAssistantMessage(
        id: id,
        content: _activeAssistantText,
        status: finalStatus ?? ChatMessageStatus.streaming,
      );
    }
  }

  Future<void> _initialize() async {
    try {
      _sessionId = await _repository.getSessionId();
    } catch (_) {
      _sessionId = null;
    }

    try {
      final saved = await _repository.getMessages();
      if (saved != null && saved.isNotEmpty) {
        _messages
          ..clear()
          ..addAll(saved);
        _bumpRevision();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<String> _ensureSessionId() async {
    final current = _sessionId;
    if (current != null && current.trim().isNotEmpty) return current;

    final generated = DateTime.now().microsecondsSinceEpoch.toString();
    _sessionId = generated;
    try {
      await _repository.setSessionId(generated);
    } catch (_) {}
    return generated;
  }

  String _normalizeUserMessageForAgent(String input) {
    final original = input.trim();
    if (original.isEmpty) return original;

    var s = original
        .replaceAll(',', ' ')
        .replaceAll(';', ' ')
        .replaceAll(':', ' ')
        .replaceAll('?', ' ')
        .replaceAll('!', ' ')
        .replaceAll('，', ' ')
        .replaceAll('。', ' ')
        .replaceAll('？', ' ')
        .replaceAll('！', ' ')
        .replaceAll('：', ' ')
        .replaceAll('（', ' ')
        .replaceAll('）', ' ')
        .replaceAll('、', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Canonicalize common token spellings (e.g. "Token Demo" -> "TokenDemo").
    s = s.replaceAll(RegExp(r'token\s*demo', caseSensitive: false), 'TokenDemo');

    bool hasAny(RegExp r) => r.hasMatch(s);
    final buyWords = RegExp(r'(再买|继续买|加仓|追加|买入|买)');
    final sellWords = RegExp(r'(再卖|继续卖|减仓|清仓|卖出|卖)');
    final isBuy = hasAny(buyWords) && !hasAny(sellWords);
    final isSell = hasAny(sellWords);

    String? normToken(String raw) {
      var t = raw.trim();
      t = t.replaceAll(RegExp(r'[\s\u3000]'), '');
      t = t.replaceAll(RegExp(r'^(的)+'), '');
      t = t.replaceAll(RegExp(r'(个|枚|颗|只|份|点)$'), '');
      if (t.isEmpty) return null;
      final lower = t.toLowerCase();
      if (lower == 'pas') return 'PAS';
      if (lower == 'usdt') return 'USDT';
      if (lower == 'usd' || lower == 'u') return 'U';
      final m = RegExp(r'([A-Za-z][A-Za-z0-9_]{1,31})').firstMatch(t);
      return m?.group(1);
    }

    // Buy pattern: 再买10 PAS的TokenDemo / 再买 10 PAS TokenDemo
    if (isBuy) {
      final m = RegExp(r'(?:再买|继续买|加仓|追加|买入|买)\s*([0-9]+(?:\.[0-9]+)?)\s*(PAS|pas|USDT|usdt|U|u)?\s*(?:的)?\s*([A-Za-z][A-Za-z0-9_]{1,31})')
          .firstMatch(s);
      if (m != null) {
        final amount = m.group(1);
        final inRaw = m.group(2);
        final outRaw = m.group(3);
        final tokenIn = (inRaw == null || inRaw.trim().isEmpty) ? 'PAS' : (normToken(inRaw) ?? 'PAS');
        final tokenOut = outRaw == null ? null : normToken(outRaw);
        if (amount != null && tokenOut != null) {
          final normalized = 'buy $amount $tokenIn $tokenOut';
          if (kDebugMode && normalized != input) {
            debugPrint('[agent-normalize] "$input" -> "$normalized"');
          }
          return normalized;
        }
      }

      // If the user explicitly mentioned TokenDemo but the structured regex didn't match,
      // fall back to a best-effort canonical command (never produce an incomplete "of").
      if (s.toLowerCase().contains('tokendemo')) {
        final amount = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(s)?.group(1);
        if (amount != null) {
          final tokenIn = hasAny(RegExp(r'\busdt\b', caseSensitive: false))
              ? 'USDT'
              : (hasAny(RegExp(r'\bu\b', caseSensitive: false)) ? 'U' : 'PAS');
          final normalized = 'buy $amount $tokenIn TokenDemo';
          if (kDebugMode && normalized != input) {
            debugPrint('[agent-normalize] "$input" -> "$normalized"');
          }
          return normalized;
        }
      }
    }

    // Sell pattern: 再卖300 TokenDemo / 卖出300个TokenDemo / 卖出 300 TokenDemo
    if (isSell) {
      final m = RegExp(
        r'(?:再卖|继续卖|减仓|清仓|卖出|卖)\s*([0-9]+(?:\.[0-9]+)?)\s*(?:个|枚|颗|只|份|点)?\s*(?:的)?\s*([A-Za-z][A-Za-z0-9_]{1,31})',
      ).firstMatch(s);
      if (m != null) {
        final amount = m.group(1);
        final tokenRaw = m.group(2);
        final token = tokenRaw == null ? null : normToken(tokenRaw);
        if (amount != null && token != null) {
          final normalized = 'sell $amount $token PAS';
          if (kDebugMode && normalized != input) {
            debugPrint('[agent-normalize] "$input" -> "$normalized"');
          }
          return normalized;
        }
      }
    }

    // Fallback for TokenDemo: try to extract amount and infer direction.
    if (s.toLowerCase().contains('tokendemo')) {
      final num = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(s)?.group(1);
      if (num != null && hasAny(buyWords)) {
        final normalized = 'buy $num PAS TokenDemo';
        if (kDebugMode && normalized != input) {
          debugPrint('[agent-normalize] "$input" -> "$normalized"');
        }
        return normalized;
      }
      if (num != null && hasAny(sellWords)) {
        final normalized = 'sell $num TokenDemo PAS';
        if (kDebugMode && normalized != input) {
          debugPrint('[agent-normalize] "$input" -> "$normalized"');
        }
        return normalized;
      }
    }

    return input;
  }

  BuyExecutionPlan? _tryBuildLocalExecutionPlan(String normalized) {
    final s = normalized.trim();
    if (s.isEmpty) return null;

    final sell = RegExp(r'^sell\s+([0-9]+(?:\.[0-9]+)?)\s+([A-Za-z][A-Za-z0-9_]{1,31})', caseSensitive: false)
        .firstMatch(s);
    if (sell != null) {
      final amount = sell.group(1);
      final tokenIn = sell.group(2);
      if (amount == null || tokenIn == null) return null;

      if (tokenIn.toLowerCase() != 'tokendemo') return null;

      final rpc = (_cachedSwapEvmRpc ?? WalletNetworkConfig.passetHubEvmRpc).trim();
      final router = (_cachedSwapRouter ?? WalletNetworkConfig.passetHubUniswapV2Router).trim();
      final weth = (_cachedSwapWeth ?? WalletNetworkConfig.passetHubWeth9).trim();
      if (rpc.isEmpty || router.isEmpty || weth.isEmpty) return null;

      // Local fallback: treat sell TokenDemo as a direct swap to PAS.
      final json = <String, dynamic>{
        'type': 'sell_token',
        'amount_in_token': amount,
        'token_in': tokenIn,
        'token_out': 'PAS',
        'steps': [
          {
            'kind': 'uniswap_v2_swap',
            'evm_rpc': rpc,
            'router': router,
            'weth': weth,
            'token_in': {
              'symbol': tokenIn,
              'address': WalletNetworkConfig.tokenDemoErc20,
            },
            'token_out': {
              'symbol': 'PAS',
            },
          },
        ],
      };
      return BuyExecutionPlan.fromJson(json);
    }

    return null;
  }

  void _captureSwapConfigFromPlanRaw(Map<String, dynamic> raw) {
    final steps = raw['steps'];
    if (steps is! List) return;
    for (final s in steps) {
      if (s is! Map<String, dynamic>) continue;
      if (s['kind'] != 'uniswap_v2_swap') continue;
      final rpc = s['evm_rpc'];
      final router = s['router'];
      final weth = s['weth'];
      if (rpc is String && router is String && weth is String) {
        _cachedSwapEvmRpc = rpc;
        _cachedSwapRouter = router;
        _cachedSwapWeth = weth;
        return;
      }
    }
  }

  void _bumpRevision() {
    _revision += 1;
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    if (_sending) return;

    await stopGeneration();

    _error = null;
    _sending = true;
    final user = ChatMessage.user(trimmed);
    _messages.add(user);
    _lastUserMessage = trimmed;
    _bumpRevision();
    _schedulePersistMessages();
    notifyListeners();

    final sessionId = await _ensureSessionId();
    final assistantId = 'assistant_${DateTime.now().microsecondsSinceEpoch}';
    _activeAssistantId = assistantId;
    _activeAssistantText = '';
    _pendingAssistantRunes.clear();
    _streaming = true;
    _messages.add(ChatMessage.assistantWithId(assistantId, '', status: ChatMessageStatus.streaming));
    _bumpRevision();
    _schedulePersistMessages();
    notifyListeners();

    final normalized = _normalizeUserMessageForAgent(trimmed);

    final localPlan = _tryBuildLocalExecutionPlan(normalized);
    if (localPlan != null) {
      _activeAssistantText = '我已为你生成交易计划。';
      _updateAssistantMessage(id: assistantId, content: _activeAssistantText, status: ChatMessageStatus.done);
      _buyPlansByMessageId[assistantId] = localPlan;
      _streaming = false;
      _sending = false;
      _activeAssistantId = null;
      _schedulePersistMessages();
      notifyListeners();
      return;
    }

    _streamSub = _agentService.streamRespond(userMessage: normalized, sessionId: sessionId).listen(
      (evt) async {
        if (evt is AgentStreamChunk) {
          _enqueueAssistantDelta(evt.deltaText);
          return;
        }

        if (evt is AgentStreamDone) {
          _stopTypewriter(flush: true, finalStatus: ChatMessageStatus.done);
          if (evt.sessionId != sessionId) {
            _sessionId = evt.sessionId;
            try {
              await _repository.setSessionId(evt.sessionId);
            } catch (_) {}
          }
          final rec = StrategyRecommendation.fromDone(
            strategyType: evt.strategyType,
            strategyLabel: evt.strategyLabel,
            actions: evt.actions,
            executionPreview: evt.executionPreview,
          );

          _activeAssistantText = evt.assistantText;
          if (rec != null) {
            _activeAssistantText = '${evt.assistantText}\n\n策略：${rec.strategyLabel}';
          }
          _updateAssistantMessage(id: assistantId, content: _activeAssistantText, status: ChatMessageStatus.done);

          if (rec != null && rec.requiresConfirmation) {
            _recommendationsByMessageId[assistantId] = rec;
            _cardStatusByMessageId[assistantId] = StrategyCardStatus.idle;
          }

          final rawPlan = evt.executionPlan;
          if (rawPlan != null) {
            _captureSwapConfigFromPlanRaw(rawPlan);
          }

          final plan = BuyExecutionPlan.fromJson(evt.executionPlan);
          if (plan != null) {
            _buyPlansByMessageId[assistantId] = plan;
          }

          _streaming = false;
          _sending = false;
          _activeAssistantId = null;
          _schedulePersistMessages();
          notifyListeners();
          return;
        }

        if (evt is AgentStreamError) {
          _stopTypewriter(flush: true, finalStatus: ChatMessageStatus.error);
          _error = '请求失败（${evt.code}）：${evt.message}';
          _updateAssistantMessage(
            id: assistantId,
            content: _activeAssistantText.isEmpty ? '请求失败（${evt.code}）' : _activeAssistantText,
            status: ChatMessageStatus.error,
          );
          _streaming = false;
          _sending = false;
          _activeAssistantId = null;
          _schedulePersistMessages();
          notifyListeners();
          return;
        }
      },
      onError: (_) {
        _stopTypewriter(flush: true, finalStatus: ChatMessageStatus.error);
        _error = '请求失败';
        if (_activeAssistantId != null) {
          _updateAssistantMessage(
            id: _activeAssistantId!,
            content: _activeAssistantText.isEmpty ? '请求失败' : _activeAssistantText,
            status: ChatMessageStatus.error,
          );
        }
        _streaming = false;
        _sending = false;
        _activeAssistantId = null;
        _schedulePersistMessages();
        notifyListeners();
      },
      onDone: () {
        if (_sending) {
          _stopTypewriter(flush: true, finalStatus: ChatMessageStatus.done);
          _sending = false;
          _streaming = false;
          _activeAssistantId = null;
          _schedulePersistMessages();
          notifyListeners();
        }
      },
      cancelOnError: true,
    );
  }

  void _updateAssistantMessage({required String id, required String content, required ChatMessageStatus status}) {
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx == -1) return;
    _messages[idx] = _messages[idx].copyWith(content: content, status: status);
    _bumpRevision();
    _schedulePersistMessages();
    notifyListeners();
  }

  Future<void> stopGeneration() async {
    final sub = _streamSub;
    _streamSub = null;
    if (sub != null) {
      await sub.cancel();
    }
    _stopTypewriter(flush: true, finalStatus: ChatMessageStatus.done);
    _streaming = false;
    _sending = false;
    if (_activeAssistantId != null) {
      final idx = _messages.indexWhere((m) => m.id == _activeAssistantId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(status: ChatMessageStatus.done);
        _bumpRevision();
      }
    }
    _activeAssistantId = null;
    _schedulePersistMessages();
    notifyListeners();
  }

  Future<void> retryLast() async {
    final lastText = _lastUserMessage;
    if (lastText == null) return;
    if (_sending) return;

    _error = null;

    final lastAssistantIdx = _messages.lastIndexWhere((m) => !m.isUser);
    if (lastAssistantIdx != -1 && _messages[lastAssistantIdx].status == ChatMessageStatus.error) {
      final removed = _messages.removeAt(lastAssistantIdx);
      _recommendationsByMessageId.remove(removed.id);
      _cardStatusByMessageId.remove(removed.id);
      _bumpRevision();
      _schedulePersistMessages();
      notifyListeners();
    }

    await _sendWithoutAddingUserMessage(lastText);
  }

  Future<void> _sendWithoutAddingUserMessage(String text) async {
    await stopGeneration();
    _sending = true;
    _streaming = true;
    notifyListeners();

    final sessionId = await _ensureSessionId();
    final assistantId = 'assistant_${DateTime.now().microsecondsSinceEpoch}';
    _activeAssistantId = assistantId;
    _activeAssistantText = '';
    _pendingAssistantRunes.clear();
    _messages.add(ChatMessage.assistantWithId(assistantId, '', status: ChatMessageStatus.streaming));
    _bumpRevision();
    notifyListeners();

    final normalized = _normalizeUserMessageForAgent(text);

    final localPlan = _tryBuildLocalExecutionPlan(normalized);
    if (localPlan != null) {
      _activeAssistantText = '我已为你生成交易计划。';
      _updateAssistantMessage(id: assistantId, content: _activeAssistantText, status: ChatMessageStatus.done);
      _buyPlansByMessageId[assistantId] = localPlan;
      _streaming = false;
      _sending = false;
      _activeAssistantId = null;
      _schedulePersistMessages();
      notifyListeners();
      return;
    }

    _streamSub = _agentService.streamRespond(userMessage: normalized, sessionId: sessionId).listen(
      (evt) async {
        if (evt is AgentStreamChunk) {
          _enqueueAssistantDelta(evt.deltaText);
          return;
        }
        if (evt is AgentStreamDone) {
          _stopTypewriter(flush: true, finalStatus: ChatMessageStatus.done);
          if (evt.sessionId != sessionId) {
            _sessionId = evt.sessionId;
            try {
              await _repository.setSessionId(evt.sessionId);
            } catch (_) {}
          }
          final rec = StrategyRecommendation.fromDone(
            strategyType: evt.strategyType,
            strategyLabel: evt.strategyLabel,
            actions: evt.actions,
            executionPreview: evt.executionPreview,
          );

          _activeAssistantText = evt.assistantText;
          if (rec != null) {
            _activeAssistantText = '${evt.assistantText}\n\n策略：${rec.strategyLabel}';
          }
          _updateAssistantMessage(id: assistantId, content: _activeAssistantText, status: ChatMessageStatus.done);

          if (rec != null && rec.requiresConfirmation) {
            _recommendationsByMessageId[assistantId] = rec;
            _cardStatusByMessageId[assistantId] = StrategyCardStatus.idle;
          }

          final rawPlan = evt.executionPlan;
          if (rawPlan != null) {
            _captureSwapConfigFromPlanRaw(rawPlan);
          }

          final plan = BuyExecutionPlan.fromJson(evt.executionPlan);
          if (plan != null) {
            _buyPlansByMessageId[assistantId] = plan;
          }

          _streaming = false;
          _sending = false;
          _activeAssistantId = null;
          notifyListeners();
          return;
        }
        if (evt is AgentStreamError) {
          _stopTypewriter(flush: true, finalStatus: ChatMessageStatus.error);
          _error = '请求失败（${evt.code}）：${evt.message}';
          _updateAssistantMessage(
            id: assistantId,
            content: _activeAssistantText.isEmpty ? '请求失败（${evt.code}）' : _activeAssistantText,
            status: ChatMessageStatus.error,
          );
          _streaming = false;
          _sending = false;
          _activeAssistantId = null;
          _schedulePersistMessages();
          notifyListeners();
        }
      },
      onError: (_) {
        _stopTypewriter(flush: true, finalStatus: ChatMessageStatus.error);
        _error = '请求失败';
        if (_activeAssistantId != null) {
          _updateAssistantMessage(
            id: _activeAssistantId!,
            content: _activeAssistantText.isEmpty ? '请求失败' : _activeAssistantText,
            status: ChatMessageStatus.error,
          );
        }
        _streaming = false;
        _sending = false;
        _activeAssistantId = null;
        notifyListeners();
      },
      onDone: () {
        if (_sending) {
          _stopTypewriter(flush: true, finalStatus: ChatMessageStatus.done);
          _sending = false;
          _streaming = false;
          _activeAssistantId = null;
          notifyListeners();
        }
      },
      cancelOnError: true,
    );
  }

  void reset() {
    unawaited(stopGeneration());
    _recommendationsByMessageId.clear();
    _cardStatusByMessageId.clear();
    _messages
      ..clear()
      ..add(
        ChatMessage.assistant(
          '告诉我你想做什么。\n\n示例：\n- 用 200U 买 BTC\n- 创建定投计划：DOT 每周 100U，跌破 5U 停止',
        ),
      );
    _sending = false;
    _streaming = false;
    _error = null;
    _activeAssistantId = null;
    _activeAssistantText = '';
    _pendingAssistantRunes.clear();
    _stopTypewriter(flush: false);
    _lastUserMessage = null;
    _sessionId = null;
    unawaited(_repository.clear());
    _bumpRevision();
    _schedulePersistMessages();
    notifyListeners();
  }
}
