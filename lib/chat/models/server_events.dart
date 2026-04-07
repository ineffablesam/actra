/// Typed server → client WebSocket payloads.
sealed class ServerWsEvent {
  const ServerWsEvent({required this.sessionId});

  final String sessionId;

  factory ServerWsEvent.fromJson(Map<String, dynamic> j) {
    final event = j['event'] as String?;
    final sid = j['session_id'] as String? ?? '';
    switch (event) {
      case 'agent_thinking':
        return AgentThinkingEvent(
          sessionId: sid,
          message: j['message'] as String? ?? '',
        );
      case 'connections_required':
        return ConnectionsRequiredEvent(
          sessionId: sid,
          providers: (j['providers'] as List<dynamic>? ?? []).cast<String>(),
          reason: j['reason'] as String? ?? '',
          taskContext: j['task_context'] as String? ?? '',
        );
      case 'agent_stream':
        return AgentStreamEvent(
          sessionId: sid,
          chunk: j['chunk'] as String? ?? '',
          done: j['done'] as bool? ?? false,
          segment: j['segment'] as String? ?? 'text',
        );
      case 'draft_ready':
        return DraftReadyEvent(
          sessionId: sid,
          actionId: j['action_id'] as String? ?? '',
          type: j['type'] as String? ?? 'email',
          payload: j['payload'] as Map<String, dynamic>? ?? {},
        );
      case 'action_result':
        return ActionResultEvent(
          sessionId: sid,
          actionId: j['action_id'] as String? ?? '',
          success: j['success'] as bool? ?? false,
          message: j['message'] as String? ?? '',
        );
      case 'tts_audio_chunk':
        return TtsAudioChunkEvent(
          sessionId: sid,
          audioBase64: j['audio_base64'] as String? ?? '',
          sampleRate: (j['sample_rate'] as num?)?.toInt() ?? 44100,
          done: j['done'] as bool? ?? false,
        );
      case 'error':
        return ErrorWsEvent(
          sessionId: sid,
          code: j['code'] as String? ?? 'ERROR',
          message: j['message'] as String? ?? '',
          recoverable: j['recoverable'] as bool? ?? true,
        );
      default:
        return UnknownServerEvent(sessionId: sid, raw: j);
    }
  }
}

class AgentThinkingEvent extends ServerWsEvent {
  const AgentThinkingEvent({required super.sessionId, required this.message});
  final String message;
}

class ConnectionsRequiredEvent extends ServerWsEvent {
  const ConnectionsRequiredEvent({
    required super.sessionId,
    required this.providers,
    required this.reason,
    required this.taskContext,
  });
  final List<String> providers;
  final String reason;
  final String taskContext;
}

class AgentStreamEvent extends ServerWsEvent {
  const AgentStreamEvent({
    required super.sessionId,
    required this.chunk,
    required this.done,
    this.segment = 'text',
  });
  final String chunk;
  final bool done;
  /// Backend sends `code` for streamed code previews (e.g. GitHub fix).
  final String segment;
}

class DraftReadyEvent extends ServerWsEvent {
  const DraftReadyEvent({
    required super.sessionId,
    required this.actionId,
    required this.type,
    required this.payload,
  });
  final String actionId;
  final String type;
  final Map<String, dynamic> payload;
}

class ActionResultEvent extends ServerWsEvent {
  const ActionResultEvent({
    required super.sessionId,
    required this.actionId,
    required this.success,
    required this.message,
  });
  final String actionId;
  final bool success;
  final String message;
}

class TtsAudioChunkEvent extends ServerWsEvent {
  const TtsAudioChunkEvent({
    required super.sessionId,
    required this.audioBase64,
    required this.sampleRate,
    required this.done,
  });
  final String audioBase64;
  final int sampleRate;
  final bool done;
}

class ErrorWsEvent extends ServerWsEvent {
  const ErrorWsEvent({
    required super.sessionId,
    required this.code,
    required this.message,
    required this.recoverable,
  });
  final String code;
  final String message;
  final bool recoverable;
}

class UnknownServerEvent extends ServerWsEvent {
  const UnknownServerEvent({required super.sessionId, required this.raw});
  final Map<String, dynamic> raw;
}
