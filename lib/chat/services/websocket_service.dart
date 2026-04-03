import 'dart:async';
import 'dart:convert';

import 'package:actra/chat/models/server_events.dart';
import 'package:actra/core/auth_session_service.dart';
import 'package:actra/core/env.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum WsConnectionStatus { connected, reconnecting, disconnected }

/// WebSocket client with typed streams and exponential backoff reconnect.
class WebSocketService extends GetxService {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  final _uuid = const Uuid();

  final status = WsConnectionStatus.disconnected.obs;
  int _attempt = 0;
  Timer? _reconnectTimer;

  final _thinking = StreamController<AgentThinkingEvent>.broadcast();
  final _connectionsRequired =
      StreamController<ConnectionsRequiredEvent>.broadcast();
  final _agentStream = StreamController<AgentStreamEvent>.broadcast();
  final _draftReady = StreamController<DraftReadyEvent>.broadcast();
  final _actionResult = StreamController<ActionResultEvent>.broadcast();
  final _ttsChunk = StreamController<TtsAudioChunkEvent>.broadcast();
  final _errors = StreamController<ErrorWsEvent>.broadcast();

  Stream<AgentThinkingEvent> get onThinking => _thinking.stream;
  Stream<ConnectionsRequiredEvent> get onConnectionsRequired =>
      _connectionsRequired.stream;
  Stream<AgentStreamEvent> get onAgentStream => _agentStream.stream;
  Stream<DraftReadyEvent> get onDraftReady => _draftReady.stream;
  Stream<ActionResultEvent> get onActionResult => _actionResult.stream;
  Stream<TtsAudioChunkEvent> get onTtsAudioChunk => _ttsChunk.stream;
  Stream<ErrorWsEvent> get onError => _errors.stream;

  String sessionId = '';

  @override
  void onInit() {
    super.onInit();
    sessionId = _uuid.v4();
  }

  Future<void> connect() async {
    await disconnect();
    status.value = WsConnectionStatus.reconnecting;
    try {
      final uri = Uri.parse(Env.wsUrl);
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: false,
      );
      status.value = WsConnectionStatus.connected;
      _attempt = 0;
      if (Get.isRegistered<AuthSessionService>()) {
        unawaited(Get.find<AuthSessionService>().pushSessionAuthIfAvailable(this));
      }
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic message) {
    if (message is! String) return;
    Map<String, dynamic> j;
    try {
      j = jsonDecode(message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final ev = ServerWsEvent.fromJson(j);
    if (ev is AgentThinkingEvent) {
      _thinking.add(ev);
    } else if (ev is ConnectionsRequiredEvent) {
      _connectionsRequired.add(ev);
    } else if (ev is AgentStreamEvent) {
      _agentStream.add(ev);
    } else if (ev is DraftReadyEvent) {
      _draftReady.add(ev);
    } else if (ev is ActionResultEvent) {
      _actionResult.add(ev);
    } else if (ev is TtsAudioChunkEvent) {
      _ttsChunk.add(ev);
    } else if (ev is ErrorWsEvent) {
      _errors.add(ev);
    }
  }

  void _scheduleReconnect() {
    status.value = WsConnectionStatus.disconnected;
    _reconnectTimer?.cancel();
    final delay = Duration(
      milliseconds: (1000 * (1 << _attempt.clamp(0, 5))).clamp(1000, 30000),
    );
    _attempt++;
    _reconnectTimer = Timer(delay, () {
      unawaited(connect());
    });
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
    status.value = WsConnectionStatus.disconnected;
  }

  void sendJson(Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null) return;
    ch.sink.add(jsonEncode(payload));
  }

  /// Backend stores this in Redis so token exchange can reach Google APIs.
  void sendSessionAuth({
    required String userId,
    required String refreshToken,
  }) {
    sendJson({
      'event': 'session_auth',
      'session_id': sessionId,
      'user_id': userId,
      'refresh_token': refreshToken,
    });
  }

  void sendTranscript(String text) {
    sendJson({
      'event': 'transcript_received',
      'session_id': sessionId,
      'user_id': Env.devUserId,
      'text': text,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void sendAccountConnected(String provider) {
    sendJson({
      'event': 'account_connected',
      'session_id': sessionId,
      'user_id': Env.devUserId,
      'provider': provider,
    });
  }

  void sendActionConfirmed(String actionId, {required bool confirmed}) {
    sendJson({
      'event': 'action_confirmed',
      'session_id': sessionId,
      'user_id': Env.devUserId,
      'action_id': actionId,
      'confirmed': confirmed,
    });
  }

  void sendActionEdited(String actionId, Map<String, dynamic> editedPayload) {
    sendJson({
      'event': 'action_edited',
      'session_id': sessionId,
      'user_id': Env.devUserId,
      'action_id': actionId,
      'edited_payload': editedPayload,
    });
  }

  @override
  void onClose() {
    unawaited(disconnect());
    _thinking.close();
    _connectionsRequired.close();
    _agentStream.close();
    _draftReady.close();
    _actionResult.close();
    _ttsChunk.close();
    _errors.close();
    super.onClose();
  }
}
