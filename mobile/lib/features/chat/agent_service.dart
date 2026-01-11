import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'agent_backend_config.dart';
import 'chat_models.dart';
import 'sse_parser.dart';

sealed class AgentStreamEvent {
  const AgentStreamEvent();
}

class AgentStreamChunk extends AgentStreamEvent {
  const AgentStreamChunk({required this.deltaText, required this.sequence});

  final String deltaText;
  final int sequence;
}

class AgentStreamDone extends AgentStreamEvent {
  const AgentStreamDone({
    required this.assistantText,
    required this.sessionId,
    required this.actions,
    required this.executionPreview,
    required this.executionPlan,
    required this.strategyType,
    required this.strategyLabel,
  });

  final String assistantText;
  final String sessionId;
  final List<dynamic> actions;
  final Map<String, dynamic>? executionPreview;
  final Map<String, dynamic>? executionPlan;
  final String? strategyType;
  final String? strategyLabel;
}

class AgentStreamError extends AgentStreamEvent {
  const AgentStreamError({required this.code, required this.message});

  final String code;
  final String message;
}

class AgentService {
  AgentService({
    AgentBackendConfig? config,
    http.Client? client,
  })  : _config = config ?? AgentBackendConfig.localhost,
        _client = client ?? http.Client();

  final AgentBackendConfig _config;
  final http.Client _client;

  Future<String> respond({required List<ChatMessage> history, required String userMessage, required String sessionId}) async {
    final uri = Uri.parse('${_config.baseUrl}/chat');
    http.Response resp;
    try {
      resp = await _client.post(
        uri,
        headers: const {
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode({'user_input': userMessage, 'session_id': sessionId}),
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
      final text = decoded['assistant_text'];
      if (text is String) return text;
    }
    throw Exception('backend_invalid_response');
  }

  Stream<AgentStreamEvent> streamRespond({required String userMessage, required String sessionId}) async* {
    final streamClient = http.Client();
    final uri = Uri.parse('${_config.baseUrl}/chat/stream');
    final req = http.Request('POST', uri);
    req.headers['content-type'] = 'application/json';
    req.headers['accept'] = 'text/event-stream';
    req.body = jsonEncode({'user_input': userMessage, 'session_id': sessionId});

    try {
      http.StreamedResponse streamed;
      try {
        streamed = await streamClient.send(req);
      } catch (e) {
        yield AgentStreamError(code: 'network_error', message: 'connect ${_config.baseUrl}: ${e.toString()}');
        return;
      }

      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        String? body;
        try {
          body = await streamed.stream.bytesToString();
        } catch (_) {
          body = null;
        }
        final trimmed = (body ?? '').trim();
        yield AgentStreamError(
          code: 'http_error',
          message: 'HTTP ${streamed.statusCode}${trimmed.isEmpty ? '' : ' - $trimmed'}',
        );
        return;
      }

      final lines = utf8LinesFromByteStream(streamed.stream);

      await for (final evt in parseSseLines(lines)) {
        if (evt.event == 'chunk') {
          final obj = jsonDecode(evt.data);
          if (obj is Map<String, dynamic>) {
            final delta = obj['delta_text'];
            final seq = obj['sequence'];
            if (delta is String && seq is int) {
              yield AgentStreamChunk(deltaText: delta, sequence: seq);
              continue;
            }
          }
          continue;
        }

        if (evt.event == 'done') {
          final obj = jsonDecode(evt.data);
          if (obj is Map<String, dynamic>) {
            final text = obj['assistant_text'];
            final sid = obj['session_id'];
            final actions = obj['actions'];
            final preview = obj['execution_preview'];
            final plan = obj['execution_plan'];
            final strategyType = obj['strategy_type'];
            final strategyLabel = obj['strategy_label'];
            if (text is String && sid is String) {
              yield AgentStreamDone(
                assistantText: text,
                sessionId: sid,
                actions: actions is List ? actions : const [],
                executionPreview: preview is Map<String, dynamic> ? preview : null,
                executionPlan: plan is Map<String, dynamic> ? plan : null,
                strategyType: strategyType is String ? strategyType : null,
                strategyLabel: strategyLabel is String ? strategyLabel : null,
              );
              return;
            }
          }
          yield const AgentStreamError(code: 'invalid_done', message: 'Invalid done payload');
          return;
        }

        if (evt.event == 'error') {
          final obj = jsonDecode(evt.data);
          if (obj is Map<String, dynamic>) {
            final code = obj['code'];
            final message = obj['message'];
            if (code is String && message is String) {
              yield AgentStreamError(code: code, message: message);
              return;
            }
          }
          yield const AgentStreamError(code: 'stream_error', message: 'Unknown stream error');
          return;
        }
      }

      yield const AgentStreamError(code: 'stream_closed', message: 'Stream closed');
    } finally {
      streamClient.close();
    }
  }
}
