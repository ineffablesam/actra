import 'package:actra/chat/controllers/chat_controller.dart';
import 'package:actra/chat/models/message_type.dart';
import 'package:actra/chat/widgets/agent_bubble.dart';
import 'package:actra/chat/widgets/connection_panel.dart';
import 'package:actra/chat/widgets/draft_card.dart';
import 'package:actra/chat/widgets/thinking_bubble.dart';
import 'package:actra/chat/widgets/user_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

class ChatMessageList extends StatelessWidget {
  const ChatMessageList({super.key});

  @override
  Widget build(BuildContext context) {
    final chat = Get.find<ChatController>();
    return Obx(() {
      final items = chat.messages;
      return ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final m = items[i];
          switch (m.type) {
            case MessageType.userTranscript:
              return UserBubble(text: m.text ?? '');
            case MessageType.agentThinking:
              return const ThinkingBubble();
            case MessageType.agentStream:
            case MessageType.agentFinal:
              return AgentBubble(
                text: m.text ?? '',
                isStreaming: m.isStreaming,
              );
            case MessageType.connectionsRequired:
              return ConnectionPanel(
                providers: m.providers ?? const [],
                reason: m.reason ?? '',
              );
            case MessageType.draftReady:
              return DraftCard(message: m);
            case MessageType.actionResult:
              return AgentBubble(
                text: m.success == true
                    ? '✓ ${m.text}'
                    : '✗ ${m.text}',
                isStreaming: false,
              );
          }
        },
      );
    });
  }
}
