import 'dart:convert';

import 'package:http/http.dart' as http;

import '../chat/agent_backend_config.dart';
import 'cross_chain_models.dart';

class CrossChainService {
  CrossChainService({AgentBackendConfig? config, http.Client? client})
      : _config = config ?? AgentBackendConfig.localhost,
        _client = client ?? http.Client();

  final AgentBackendConfig _config;
  final http.Client _client;

  Future<CrossChainIntent> createIntent(CrossChainIntentCreateRequest req) async {
    final uri = Uri.parse('${_config.baseUrl}/cross-chain/intents');
    http.Response resp;
    try {
      resp = await _client.post(
        uri,
        headers: const {
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode(req.toJson()),
      );
    } catch (e) {
      throw Exception('backend_network_error:${_config.baseUrl}:${e.toString()}');
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final body = resp.body.trim();
      throw Exception('backend_http_${resp.statusCode}:${body.isEmpty ? '<empty>' : body}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) {
      return CrossChainIntent.fromJson(decoded);
    }
    throw Exception('backend_invalid_response');
  }

  Future<CrossChainIntent> getIntent(String intentId) async {
    final uri = Uri.parse('${_config.baseUrl}/cross-chain/intents/$intentId');
    http.Response resp;
    try {
      resp = await _client.get(
        uri,
        headers: const {
          'accept': 'application/json',
        },
      );
    } catch (e) {
      throw Exception('backend_network_error:${_config.baseUrl}:${e.toString()}');
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final body = resp.body.trim();
      throw Exception('backend_http_${resp.statusCode}:${body.isEmpty ? '<empty>' : body}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) {
      return CrossChainIntent.fromJson(decoded);
    }
    throw Exception('backend_invalid_response');
  }

  Future<CrossChainIntent> cancelIntent(String intentId) async {
    final uri = Uri.parse('${_config.baseUrl}/cross-chain/intents/$intentId/cancel');
    http.Response resp;
    try {
      resp = await _client.post(
        uri,
        headers: const {
          'accept': 'application/json',
        },
      );
    } catch (e) {
      throw Exception('backend_network_error:${_config.baseUrl}:${e.toString()}');
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final body = resp.body.trim();
      throw Exception('backend_http_${resp.statusCode}:${body.isEmpty ? '<empty>' : body}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) {
      return CrossChainIntent.fromJson(decoded);
    }
    throw Exception('backend_invalid_response');
  }

  Future<CrossChainIntent> refundIntent(String intentId) async {
    final uri = Uri.parse('${_config.baseUrl}/cross-chain/intents/$intentId/refund');
    http.Response resp;
    try {
      resp = await _client.post(
        uri,
        headers: const {
          'accept': 'application/json',
        },
      );
    } catch (e) {
      throw Exception('backend_network_error:${_config.baseUrl}:${e.toString()}');
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final body = resp.body.trim();
      throw Exception('backend_http_${resp.statusCode}:${body.isEmpty ? '<empty>' : body}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) {
      return CrossChainIntent.fromJson(decoded);
    }
    throw Exception('backend_invalid_response');
  }
}
