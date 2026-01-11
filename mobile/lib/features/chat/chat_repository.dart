import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'chat_models.dart';

abstract class ChatRepository {
  Future<String?> getSessionId();

  Future<void> setSessionId(String sessionId);

  Future<List<ChatMessage>?> getMessages();

  Future<void> setMessages(List<ChatMessage> messages);

  Future<void> clear();
}

class SecureChatRepository implements ChatRepository {
  SecureChatRepository({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  static const _sessionIdKey = 'chat.session_id';
  static const _messagesKey = 'chat.messages';

  @override
  Future<String?> getSessionId() {
    return _secureStorage.read(key: _sessionIdKey);
  }

  @override
  Future<void> setSessionId(String sessionId) {
    return _secureStorage.write(key: _sessionIdKey, value: sessionId);
  }

  @override
  Future<List<ChatMessage>?> getMessages() async {
    final raw = await _secureStorage.read(key: _messagesKey);
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! List) return null;
      final out = <ChatMessage>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final m = _chatMessageFromJsonMap(item);
        if (m != null) out.add(m);
      }
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setMessages(List<ChatMessage> messages) {
    final payload = messages.map(_chatMessageToJsonMap).toList(growable: false);
    return _secureStorage.write(key: _messagesKey, value: jsonEncode(payload));
  }

  @override
  Future<void> clear() async {
    await _secureStorage.delete(key: _sessionIdKey);
    await _secureStorage.delete(key: _messagesKey);
  }
}

class InMemoryChatRepository implements ChatRepository {
  String? _sessionId;
  List<ChatMessage>? _messages;

  @override
  Future<String?> getSessionId() async {
    return _sessionId;
  }

  @override
  Future<void> setSessionId(String sessionId) async {
    _sessionId = sessionId;
  }

  @override
  Future<List<ChatMessage>?> getMessages() async {
    return _messages;
  }

  @override
  Future<void> setMessages(List<ChatMessage> messages) async {
    _messages = List<ChatMessage>.from(messages);
  }

  @override
  Future<void> clear() async {
    _sessionId = null;
    _messages = null;
  }
}

Map<String, Object?> _chatMessageToJsonMap(ChatMessage m) {
  return <String, Object?>{
    'id': m.id,
    'role': m.role.name,
    'content': m.content,
    'status': m.status.name,
    'created_at': m.createdAt.toIso8601String(),
  };
}

ChatMessage? _chatMessageFromJsonMap(Map<dynamic, dynamic> raw) {
  final id = raw['id'];
  final roleRaw = raw['role'];
  final content = raw['content'];
  final statusRaw = raw['status'];
  final createdAtRaw = raw['created_at'];

  if (id is! String || id.trim().isEmpty) return null;
  if (content is! String) return null;

  ChatRole? role;
  for (final r in ChatRole.values) {
    if (r.name == roleRaw) {
      role = r;
      break;
    }
  }
  ChatMessageStatus? status;
  for (final s in ChatMessageStatus.values) {
    if (s.name == statusRaw) {
      status = s;
      break;
    }
  }
  if (role == null || status == null) return null;

  DateTime createdAt;
  if (createdAtRaw is String) {
    createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();
  } else {
    createdAt = DateTime.now();
  }

  return ChatMessage(
    id: id,
    role: role,
    content: content,
    status: status,
    createdAt: createdAt,
  );
}
