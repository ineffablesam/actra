import 'package:actra/chat/controllers/chat_controller.dart';
import 'package:actra/chat/models/message_type.dart';
import 'package:actra/chat/widgets/agent_bubble.dart';
import 'package:actra/chat/widgets/draft_card.dart';
import 'package:actra/chat/widgets/thinking_bubble.dart';
import 'package:actra/chat/widgets/user_bubble.dart';
import 'package:actra/core/chat_provider_labels.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

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
              return _ConnectionPromptLine(
                providers: m.providers ?? const [],
                pending: m.connectionPromptPending,
              );
            case MessageType.systemConnectionStatus:
              return _SystemConnectionLine(text: m.text ?? '');
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

class _ConnectionPromptLine extends StatelessWidget {
  const _ConnectionPromptLine({
    required this.providers,
    required this.pending,
  });

  final List<String> providers;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final caption = connectionRequiredCaption(providers);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (pending) ...[
              SizedBox(
                width: 12.w,
                height: 12.w,
                child: Transform.scale(
                  scale: 0.55,
                  alignment: Alignment.center,
                  child: const CupertinoActivityIndicator(
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ),
              SizedBox(width: 8.w),
            ],
            Flexible(
              child: Text(
                caption,
                textAlign: TextAlign.center,
                style: GoogleFonts.instrumentSans(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemConnectionLine extends StatelessWidget {
  const _SystemConnectionLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.instrumentSans(
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
            letterSpacing: 0.15,
          ),
        ),
      ),
    );
  }
}
