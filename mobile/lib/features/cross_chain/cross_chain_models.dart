class CrossChainConnectorType {
  const CrossChainConnectorType._(this.value);

  final String value;

  static const xcm = CrossChainConnectorType._('xcm');
  static const hyperbridgeIsmp = CrossChainConnectorType._('hyperbridge_ismp');

  static const values = <CrossChainConnectorType>[xcm, hyperbridgeIsmp];

  static CrossChainConnectorType fromJson(Object? raw) {
    final s = raw is String ? raw : '';
    for (final v in values) {
      if (v.value == s) return v;
    }
    return CrossChainConnectorType._(s.isEmpty ? 'unknown' : s);
  }

  @override
  String toString() => value;
}

class CrossChainGoalType {
  const CrossChainGoalType._(this.value);

  final String value;

  static const deposit = CrossChainGoalType._('deposit');
  static const withdraw = CrossChainGoalType._('withdraw');
  static const pathCRoundtrip = CrossChainGoalType._('path_c_roundtrip');

  static const values = <CrossChainGoalType>[deposit, withdraw, pathCRoundtrip];

  static CrossChainGoalType fromJson(Object? raw) {
    final s = raw is String ? raw : '';
    for (final v in values) {
      if (v.value == s) return v;
    }
    return CrossChainGoalType._(s.isEmpty ? 'unknown' : s);
  }

  @override
  String toString() => value;
}

class CrossChainAssetKind {
  const CrossChainAssetKind._(this.value);

  final String value;

  static const native = CrossChainAssetKind._('native');
  static const erc20 = CrossChainAssetKind._('erc20');

  static const values = <CrossChainAssetKind>[native, erc20];

  static CrossChainAssetKind fromJson(Object? raw) {
    final s = raw is String ? raw : '';
    for (final v in values) {
      if (v.value == s) return v;
    }
    return CrossChainAssetKind._(s.isEmpty ? 'unknown' : s);
  }

  @override
  String toString() => value;
}

class CrossChainLifecycleState {
  const CrossChainLifecycleState._(this.value);

  final String value;

  static const created = CrossChainLifecycleState._('created');
  static const pending = CrossChainLifecycleState._('pending');
  static const settled = CrossChainLifecycleState._('settled');
  static const failed = CrossChainLifecycleState._('failed');
  static const cancelled = CrossChainLifecycleState._('cancelled');
  static const refunded = CrossChainLifecycleState._('refunded');

  static const values = <CrossChainLifecycleState>[created, pending, settled, failed, cancelled, refunded];

  static CrossChainLifecycleState fromJson(Object? raw) {
    final s = raw is String ? raw : '';
    for (final v in values) {
      if (v.value == s) return v;
    }
    return CrossChainLifecycleState._(s.isEmpty ? 'unknown' : s);
  }

  @override
  String toString() => value;
}

class CrossChainTarget {
  const CrossChainTarget({required this.connector, required this.destination});

  final CrossChainConnectorType connector;
  final String destination;

  factory CrossChainTarget.fromJson(Map<String, dynamic> json) {
    return CrossChainTarget(
      connector: CrossChainConnectorType.fromJson(json['connector']),
      destination: (json['destination'] is String) ? json['destination'] as String : '',
    );
  }

  Map<String, dynamic> toJson() => {
        'connector': connector.value,
        'destination': destination,
      };
}

class CrossChainAsset {
  const CrossChainAsset({required this.kind, required this.amount, this.tokenAddress});

  final CrossChainAssetKind kind;
  final String amount;
  final String? tokenAddress;

  factory CrossChainAsset.fromJson(Map<String, dynamic> json) {
    return CrossChainAsset(
      kind: CrossChainAssetKind.fromJson(json['kind']),
      amount: (json['amount'] is String) ? json['amount'] as String : '',
      tokenAddress: (json['token_address'] is String) ? json['token_address'] as String : null,
    );
  }

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      'kind': kind.value,
      'amount': amount,
    };
    if (tokenAddress != null && tokenAddress!.trim().isNotEmpty) {
      out['token_address'] = tokenAddress;
    }
    return out;
  }
}

class CrossChainIntentEvent {
  const CrossChainIntentEvent({required this.timestampUnixS, required this.state, this.detail, this.messageId});

  final double timestampUnixS;
  final CrossChainLifecycleState state;
  final String? detail;
  final String? messageId;

  factory CrossChainIntentEvent.fromJson(Map<String, dynamic> json) {
    final ts = json['timestamp_unix_s'];
    return CrossChainIntentEvent(
      timestampUnixS: ts is num ? ts.toDouble() : 0,
      state: CrossChainLifecycleState.fromJson(json['state']),
      detail: (json['detail'] is String) ? json['detail'] as String : null,
      messageId: (json['message_id'] is String) ? json['message_id'] as String : null,
    );
  }
}

class CrossChainIntent {
  const CrossChainIntent({
    required this.intentId,
    required this.goal,
    required this.target,
    required this.asset,
    required this.state,
    required this.createdUnixS,
    this.clientRequestId,
    this.sessionId,
    this.dispatchId,
    this.expiresUnixS,
    this.events = const [],
  });

  final String intentId;
  final String? clientRequestId;
  final String? sessionId;
  final CrossChainGoalType goal;
  final CrossChainTarget target;
  final CrossChainAsset asset;
  final CrossChainLifecycleState state;
  final String? dispatchId;
  final double createdUnixS;
  final double? expiresUnixS;
  final List<CrossChainIntentEvent> events;

  factory CrossChainIntent.fromJson(Map<String, dynamic> json) {
    final eventsRaw = json['events'];
    final events = <CrossChainIntentEvent>[];
    if (eventsRaw is List) {
      for (final item in eventsRaw) {
        if (item is Map<String, dynamic>) {
          events.add(CrossChainIntentEvent.fromJson(item));
        }
      }
    }

    final created = json['created_unix_s'];
    final expires = json['expires_unix_s'];

    return CrossChainIntent(
      intentId: (json['intent_id'] is String) ? json['intent_id'] as String : '',
      clientRequestId: (json['client_request_id'] is String) ? json['client_request_id'] as String : null,
      sessionId: (json['session_id'] is String) ? json['session_id'] as String : null,
      goal: CrossChainGoalType.fromJson(json['goal']),
      target: CrossChainTarget.fromJson((json['target'] is Map<String, dynamic>) ? json['target'] as Map<String, dynamic> : const {}),
      asset: CrossChainAsset.fromJson((json['asset'] is Map<String, dynamic>) ? json['asset'] as Map<String, dynamic> : const {}),
      state: CrossChainLifecycleState.fromJson(json['state']),
      dispatchId: (json['dispatch_id'] is String) ? json['dispatch_id'] as String : null,
      createdUnixS: created is num ? created.toDouble() : 0,
      expiresUnixS: expires is num ? expires.toDouble() : null,
      events: events,
    );
  }
}

class CrossChainIntentCreateRequest {
  const CrossChainIntentCreateRequest({
    required this.goal,
    required this.target,
    required this.asset,
    this.clientRequestId,
    this.sessionId,
    this.timeoutSeconds,
  });

  final String? clientRequestId;
  final String? sessionId;
  final CrossChainGoalType goal;
  final CrossChainTarget target;
  final CrossChainAsset asset;
  final int? timeoutSeconds;

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      'goal': goal.value,
      'target': target.toJson(),
      'asset': asset.toJson(),
    };
    if (clientRequestId != null && clientRequestId!.trim().isNotEmpty) {
      out['client_request_id'] = clientRequestId;
    }
    if (sessionId != null && sessionId!.trim().isNotEmpty) {
      out['session_id'] = sessionId;
    }
    if (timeoutSeconds != null) {
      out['timeout_seconds'] = timeoutSeconds;
    }
    return out;
  }
}
