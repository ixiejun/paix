import 'package:flutter/foundation.dart';

enum ChatRole { user, assistant }

enum ChatMessageStatus { sending, streaming, done, error }

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final ChatRole role;
  final String content;
  final ChatMessageStatus status;
  final DateTime createdAt;

  bool get isUser => role == ChatRole.user;

  ChatMessage copyWith({String? content, ChatMessageStatus? status}) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  static ChatMessage user(String content) {
    final now = DateTime.now();
    return ChatMessage(
      id: now.microsecondsSinceEpoch.toString(),
      role: ChatRole.user,
      content: content,
      status: ChatMessageStatus.done,
      createdAt: now,
    );
  }

  static ChatMessage assistant(String content, {ChatMessageStatus status = ChatMessageStatus.done}) {
    final now = DateTime.now();
    return ChatMessage(
      id: now.microsecondsSinceEpoch.toString(),
      role: ChatRole.assistant,
      content: content,
      status: status,
      createdAt: now,
    );
  }

  static ChatMessage assistantWithId(String id, String content, {ChatMessageStatus status = ChatMessageStatus.done}) {
    return ChatMessage(
      id: id,
      role: ChatRole.assistant,
      content: content,
      status: status,
      createdAt: DateTime.now(),
    );
  }
}
