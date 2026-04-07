import 'dart:async';

import 'package:actra/chat/models/chat_message.dart';
import 'package:actra/chat/models/message_type.dart';
import 'package:actra/chat/models/server_events.dart';
import 'package:actra/chat/services/audio_service.dart';
import 'package:actra/chat/services/websocket_service.dart';
import 'package:actra/core/auth_session_service.dart';
import 'package:actra/core/chat_provider_labels.dart';
import 'package:actra/core/connected_accounts_service.dart';
import 'package:actra/core/linked_accounts_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

class ChatController extends GetxController {
  final messages = <ChatMessage>[].obs;
  final pendingProviders = <String>[].obs;
  final isAgentBusy = false.obs;

  /// Incremented on each `connections_required` so the UI can open the Wolt sheet.
  final openConnectionSheetTick = 0.obs;
  final lastConnectionReason = ''.obs;

  final _uuid = const Uuid();
  WebSocketService? _ws;
  AudioService? _audio;

  StreamSubscription<AgentThinkingEvent>? _subThink;
  StreamSubscription<ConnectionsRequiredEvent>? _subConn;
  StreamSubscription<AgentStreamEvent>? _subStream;
  StreamSubscription<DraftReadyEvent>? _subDraft;
  StreamSubscription<ActionResultEvent>? _subResult;
  StreamSubscription<TtsAudioChunkEvent>? _subTts;
  StreamSubscription<ErrorWsEvent>? _subErr;

  String? _streamingId;
  String? _codeStreamingId;

  void _removeThinkingMessages() {
    messages.removeWhere((m) => m.type == MessageType.agentThinking);
  }

  @override
  void onInit() {
    super.onInit();
    _ws = Get.find<WebSocketService>();
    _audio = Get.find<AudioService>();
    _bind();
    unawaited(_bootstrapConnection());
  }

  Future<void> _bootstrapConnection() async {
    await _ws!.connect();
  }

  void _bind() {
    final ws = _ws!;
    final audio = _audio!;

    _subThink = ws.onThinking.listen((e) {
      messages.add(
        ChatMessage(
          id: _uuid.v4(),
          type: MessageType.agentThinking,
          text: e.message,
          timestamp: DateTime.now(),
        ),
      );
    });

    _subConn = ws.onConnectionsRequired.listen((e) {
      pendingProviders.assignAll(e.providers);
      lastConnectionReason.value = e.reason;
      messages.add(
        ChatMessage(
          id: _uuid.v4(),
          type: MessageType.connectionsRequired,
          text: e.reason,
          providers: List<String>.from(e.providers),
          reason: e.reason,
          taskContext: e.taskContext,
          timestamp: DateTime.now(),
          connectionPromptPending: true,
        ),
      );
      openConnectionSheetTick.value++;
    });

    _subStream = ws.onAgentStream.listen((e) {
      final seg = e.segment;
      if (seg == 'code') {
        isAgentBusy.value = true;
        if (_codeStreamingId == null) {
          _removeThinkingMessages();
          _codeStreamingId = _uuid.v4();
          messages.add(
            ChatMessage(
              id: _codeStreamingId!,
              type: MessageType.agentStream,
              text: '',
              timestamp: DateTime.now(),
              isStreaming: true,
              isCodeStream: true,
            ),
          );
        }
        final cid = _codeStreamingId!;
        final cidx = messages.indexWhere((m) => m.id == cid);
        if (cidx >= 0) {
          final m = messages[cidx];
          m.text = (m.text ?? '') + e.chunk;
          messages[cidx] = m;
          messages.refresh();
        }
        if (e.done) {
          final idx2 = messages.indexWhere((m) => m.id == cid);
          if (idx2 >= 0) {
            messages[idx2].isStreaming = false;
            messages[idx2].type = MessageType.agentFinal;
            messages.refresh();
          }
          _codeStreamingId = null;
          isAgentBusy.value = false;
        }
        return;
      }

      if (_streamingId == null) {
        _removeThinkingMessages();
        _streamingId = _uuid.v4();
        messages.add(
          ChatMessage(
            id: _streamingId!,
            type: MessageType.agentStream,
            text: '',
            timestamp: DateTime.now(),
            isStreaming: true,
          ),
        );
      }
      final id = _streamingId!;
      final idx = messages.indexWhere((m) => m.id == id);
      if (idx >= 0) {
        final m = messages[idx];
        m.text = (m.text ?? '') + e.chunk;
        messages[idx] = m;
        messages.refresh();
      }
      if (e.done) {
        final idx2 = messages.indexWhere((m) => m.id == id);
        if (idx2 >= 0) {
          messages[idx2].isStreaming = false;
          messages[idx2].type = MessageType.agentFinal;
          messages.refresh();
        }
        _streamingId = null;
        isAgentBusy.value = false;
      }
    });

    _subDraft = ws.onDraftReady.listen((e) {
      _removeThinkingMessages();
      final p = e.payload;
      if (e.type == 'github_pr') {
        messages.add(
          ChatMessage(
            id: _uuid.v4(),
            type: MessageType.draftReady,
            githubPrDraft: GithubPrDraftPayload.fromJson(p),
            actionId: e.actionId,
            timestamp: DateTime.now(),
          ),
        );
      } else {
        messages.add(
          ChatMessage(
            id: _uuid.v4(),
            type: MessageType.draftReady,
            draft: DraftPayload(
              to: p['to'] as String? ?? '',
              subject: p['subject'] as String? ?? '',
              body: p['body'] as String? ?? '',
              cc: (p['cc'] as List<dynamic>? ?? []).cast<String>(),
            ),
            actionId: e.actionId,
            timestamp: DateTime.now(),
          ),
        );
      }
    });

    _subResult = ws.onActionResult.listen((e) {
      messages.add(
        ChatMessage(
          id: _uuid.v4(),
          type: MessageType.actionResult,
          text: e.message,
          success: e.success,
          timestamp: DateTime.now(),
        ),
      );
    });

    _subTts = ws.onTtsAudioChunk.listen((e) async {
      await audio.onTtsChunk(
        audioBase64: e.audioBase64,
        done: e.done,
        sampleRate: e.sampleRate,
      );
    });

    _subErr = ws.onError.listen((e) {
      _removeThinkingMessages();
      messages.add(
        ChatMessage(
          id: _uuid.v4(),
          type: MessageType.agentFinal,
          text: 'Error (${e.code}): ${e.message}',
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  void sendUserTranscript(String text) {
    if (text.trim().isEmpty) return;
    if (Get.isRegistered<AuthSessionService>()) {
      final uid = Get.find<AuthSessionService>().userId.value;
      if (uid == null || uid.isEmpty) {
        Get.snackbar(
          'Sign in required',
          'Complete Auth0 sign-in from the splash screen first.',
        );
        return;
      }
    }
    messages.add(
      ChatMessage(
        id: _uuid.v4(),
        type: MessageType.userTranscript,
        text: text,
        timestamp: DateTime.now(),
      ),
    );
    isAgentBusy.value = true;
    _streamingId = null;
    _codeStreamingId = null;
    _ws?.sendTranscript(text);
  }

  void confirmDraft(String actionId, DraftPayload draft) {
    _ws?.sendActionEdited(actionId, {
      'to': draft.to,
      'subject': draft.subject,
      'body': draft.body,
    });
  }

  void confirmGithubPrDraft(String actionId, GithubPrDraftPayload draft) {
    _ws?.sendActionEdited(actionId, draft.toJson());
  }

  /// Links Google or Slack via Auth0 Connected Accounts (Token Vault), then notifies the backend.
  /// Returns whether OAuth + complete succeeded. When [suppressSuccessSnack] is true, the service
  /// does not show its default snackbar (used from the Wolt sheet).
  Future<bool> connectProvider(
    String provider, {
    bool suppressSuccessSnack = false,
  }) async {
    debugPrint('[Chat] connectProvider tapped provider=$provider');
    if (!Get.isRegistered<ConnectedAccountsService>()) {
      debugPrint('[Chat] connectProvider abort: ConnectedAccountsService not registered');
      Get.snackbar('Error', 'Account linking is not available.');
      return false;
    }
    final accounts = Get.find<ConnectedAccountsService>();
    final bool ok;
    if (provider == 'slack') {
      ok = await accounts.connectSlackConnection(
        showSuccessSnack: !suppressSuccessSnack,
      );
    } else if (provider == 'github') {
      ok = await accounts.connectGitHubConnection(
        showSuccessSnack: !suppressSuccessSnack,
      );
    } else {
      ok = await accounts.connectGoogleConnection(
        provider,
        showSuccessSnack: !suppressSuccessSnack,
      );
    }
    if (!ok) {
      debugPrint('[Chat] connectProvider finished ok=false (see ConnectedAccounts logs)');
      return false;
    }
    debugPrint('[Chat] connectProvider success, sending account_connected');
    _ws?.sendAccountConnected(provider);
    pendingProviders.remove(provider);
    if (Get.isRegistered<LinkedAccountsController>()) {
      unawaited(Get.find<LinkedAccountsController>().reloadFromBackend());
    }
    return true;
  }

  /// Replaces the latest pending connection prompt for [provider], or appends a success line.
  void resolveConnectionPromptForProvider(String provider) {
    final successText = successfullyConnectedCaption(provider);
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.type != MessageType.connectionsRequired || !m.connectionPromptPending) {
        continue;
      }
      final provs = m.providers;
      if (provs == null || !provs.contains(provider)) {
        continue;
      }
      final remaining = List<String>.from(provs)..remove(provider);
      if (remaining.isEmpty) {
        m.type = MessageType.systemConnectionStatus;
        m.text = successText;
        m.connectionPromptPending = false;
      } else {
        m.providers = remaining;
      }
      messages.refresh();
      return;
    }
    messages.add(
      ChatMessage(
        id: _uuid.v4(),
        type: MessageType.systemConnectionStatus,
        text: successText,
        timestamp: DateTime.now(),
      ),
    );
    messages.refresh();
  }

  @override
  void onClose() {
    _subThink?.cancel();
    _subConn?.cancel();
    _subStream?.cancel();
    _subDraft?.cancel();
    _subResult?.cancel();
    _subTts?.cancel();
    _subErr?.cancel();
    super.onClose();
  }
}
