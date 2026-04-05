import 'package:actra/chat/models/message_type.dart';

class DraftPayload {
  DraftPayload({
    required this.to,
    required this.subject,
    required this.body,
    this.cc = const [],
  });

  final String to;
  final String subject;
  final String body;
  final List<String> cc;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.type,
    this.text,
    this.providers,
    this.draft,
    this.success,
    required this.timestamp,
    this.isStreaming = false,
    this.reason,
    this.taskContext,
    this.actionId,
    this.connectionPromptPending = false,
  });

  final String id;
  MessageType type;
  String? text;
  List<String>? providers;
  final DraftPayload? draft;
  final bool? success;
  final DateTime timestamp;
  bool isStreaming;
  final String? reason;
  final String? taskContext;
  final String? actionId;

  /// When [type] is [MessageType.connectionsRequired], true until resolved or partially updated.
  bool connectionPromptPending;
}
