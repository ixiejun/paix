import 'package:flutter/foundation.dart';

import 'cross_chain_models.dart';
import 'cross_chain_service.dart';

class CrossChainState extends ChangeNotifier {
  CrossChainState({CrossChainService? service}) : _service = service ?? CrossChainService();

  final CrossChainService _service;

  bool _loading = false;
  String? _error;
  CrossChainIntent? _intent;

  bool get loading => _loading;
  String? get error => _error;
  CrossChainIntent? get intent => _intent;

  Future<void> createIntent(CrossChainIntentCreateRequest req) async {
    if (_loading) return;

    try {
      _loading = true;
      _error = null;
      notifyListeners();

      final created = await _service.createIntent(req);
      _intent = created;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadIntent(String intentId) async {
    final trimmed = intentId.trim();
    if (trimmed.isEmpty) return;
    if (_loading) return;

    try {
      _loading = true;
      _error = null;
      notifyListeners();

      final loaded = await _service.getIntent(trimmed);
      _intent = loaded;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> cancel() async {
    final current = _intent;
    if (current == null) return;
    if (_loading) return;

    try {
      _loading = true;
      _error = null;
      notifyListeners();

      _intent = await _service.cancelIntent(current.intentId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refund() async {
    final current = _intent;
    if (current == null) return;
    if (_loading) return;

    try {
      _loading = true;
      _error = null;
      notifyListeners();

      _intent = await _service.refundIntent(current.intentId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
