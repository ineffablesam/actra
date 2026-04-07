import 'package:actra/chat/controllers/chat_controller.dart';
import 'package:actra/chat/models/chat_message.dart';
import 'package:actra/chat/models/message_type.dart';
import 'package:actra/chat/widgets/agent_bubble.dart';
import 'package:actra/chat/widgets/draft_card.dart';
import 'package:actra/chat/widgets/github_pr_draft_card.dart';
import 'package:actra/chat/widgets/thinking_bubble.dart';
import 'package:actra/chat/widgets/user_bubble.dart';
import 'package:actra/core/chat_provider_labels.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gradient_borders/box_borders/gradient_box_border.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:text_gradiate/text_gradiate.dart';

/// Matches [connected_accounts_view] sheet cards and icon wells.
BoxDecoration _emptyStateCardDecoration({double radius = 12}) {
  return BoxDecoration(
    color: Colors.white.withOpacity(0.08),
    image: DecorationImage(
      fit: BoxFit.cover,
      opacity: 0.3,
      image: AssetImage("assets/images/chat_bubble_bg.png"),
    ),
    borderRadius: BorderRadius.circular(12.r),
    border: const GradientBoxBorder(
      gradient: LinearGradient(
        begin: AlignmentGeometry.topLeft,
        end: AlignmentGeometry.bottomRight,
        colors: [Color(0xFFEDD9FF), Colors.white10, Color(0xFFC887FF)],
      ),
      width: 0.7,
    ),
  );
}

const Color _kEmptyStateLabelSecondary = Color(0x9EFFFFFF);

/// Sliver list of chat messages (use under a [SliverAppBar] or in a [CustomScrollView]).
class ChatMessagesSliver extends StatelessWidget {
  const ChatMessagesSliver({super.key});

  @override
  Widget build(BuildContext context) {
    final chat = Get.find<ChatController>();
    return Obx(() {
      final items = chat.messages;
      if (items.isEmpty) {
        // [SliverFillRemaining] queries child intrinsics; [GridView] shrink-wrap uses a
        // viewport that cannot report intrinsics. Use [SliverToBoxAdapter] + a plain grid.
        return SliverToBoxAdapter(
          child: _ChatEmptyState(
            onPromptTap: Get.find<ChatController>().sendUserTranscript,
          ),
        );
      }
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => _messageWidgetFor(items[i]),
          childCount: items.length,
        ),
      );
    });
  }
}

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState({required this.onPromptTap});

  final void Function(String text) onPromptTap;

  static const _quickPrompts = <String>[
    'Get me the latest message from slack',
    'Summarize my unread emails from today',
    'What meetings do I have tomorrow?',
    'List open issues in the ineffablesam/codi',
  ];

  static const _gridItems = <({IconData icon, String label, String hint})>[
    (icon: Iconsax.sms, label: 'Mail', hint: 'Draft & triage'),
    (icon: Iconsax.calendar_1, label: 'Calendar', hint: 'Schedule & prep'),
    (icon: Iconsax.messages_3, label: 'Slack', hint: 'Channels & DMs'),
    (icon: Iconsax.code, label: 'GitHub', hint: 'Issues & PRs'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(2.w, 0, 2.w, 4.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextGradiate(
            text: Text(
              'From Question to\nAction — Instantly.',
              textAlign: TextAlign.left,
              style: GoogleFonts.instrumentSans(
                fontSize: 28.sp,
                fontWeight: FontWeight.w900,
                height: 1.08,
                letterSpacing: -0.45,
              ),
            ),
            colors: const [Color(0xFFEBD2FF), Color(0xFFFFFFFF)],
            gradientType: GradientType.linear,
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            tileMode: TileMode.clamp,
          ),
          SizedBox(height: 4.h),
          Text(
            'Connect tools, then ask Actra anything—in plain language.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.instrumentSans(
              fontSize: 11.sp,
              fontWeight: FontWeight.w400,
              color: _kEmptyStateLabelSecondary,
              height: 1.25,
            ),
          ),
          SizedBox(height: 10.h),
          _CapabilityGrid(items: _gridItems),
          SizedBox(height: 10.h),
          Text(
            'QUICK PROMPTS',
            style: GoogleFonts.instrumentSans(
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: _kEmptyStateLabelSecondary,
            ),
          ),
          SizedBox(height: 6.h),
          ..._quickPrompts.map(
            (p) => Padding(
              padding: EdgeInsets.only(bottom: 5.h),
              child: _QuickPromptTile(text: p, onTap: () => onPromptTap(p)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 2×2 grid without [GridView] — shrink-wrapped grids use a viewport that breaks
/// intrinsics (e.g. under [SliverFillRemaining]).
class _CapabilityGrid extends StatelessWidget {
  const _CapabilityGrid({required this.items});

  final List<({IconData icon, String label, String hint})> items;

  @override
  Widget build(BuildContext context) {
    final gap = 6.w;
    final rowGap = 6.h;
    var aspectRatio = 1.60;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: _EmptyCapabilityTile(
                  icon: items[0].icon,
                  label: items[0].label,
                  hint: items[0].hint,
                ),
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: _EmptyCapabilityTile(
                  icon: items[1].icon,
                  label: items[1].label,
                  hint: items[1].hint,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: rowGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: _EmptyCapabilityTile(
                  icon: items[2].icon,
                  label: items[2].label,
                  hint: items[2].hint,
                ),
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: _EmptyCapabilityTile(
                  icon: items[3].icon,
                  label: items[3].label,
                  hint: items[3].hint,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyCapabilityTile extends StatelessWidget {
  const _EmptyCapabilityTile({
    required this.icon,
    required this.label,
    required this.hint,
  });

  final IconData icon;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: _emptyStateCardDecoration(radius: 10),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Color(0xFFEBD2FF), size: 28.sp),
              SizedBox(height: 4.h),
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.instrumentSans(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.instrumentSans(
                      fontSize: 9.sp,
                      fontWeight: FontWeight.w500,
                      color: _kEmptyStateLabelSecondary.withValues(alpha: 0.75),
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickPromptTile extends StatelessWidget {
  const _QuickPromptTile({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10.r),
        child: Ink(
          decoration: _emptyStateCardDecoration(radius: 10),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 12.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Iconsax.arrow_right_3,
                  size: 14.sp,
                  color: const Color(0xFFEBD2FF).withValues(alpha: 0.85),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.instrumentSans(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.92),
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _messageWidgetFor(ChatMessage m) {
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
        isCode: m.isCodeStream,
      );
    case MessageType.connectionsRequired:
      return _ConnectionPromptLine(
        providers: m.providers ?? const [],
        pending: m.connectionPromptPending,
      );
    case MessageType.systemConnectionStatus:
      return _SystemConnectionLine(text: m.text ?? '');
    case MessageType.draftReady:
      if (m.githubPrDraft != null) {
        return GithubPrDraftCard(message: m);
      }
      return DraftCard(message: m);
    case MessageType.actionResult:
      return _ActionResultLine(
        message: m.text ?? '',
        success: m.success == true,
      );
  }
}

/// Standalone scroll view (no app bar). Prefer [ChatMessagesSliver] with [SliverAppBar] on home.
class ChatMessageList extends StatelessWidget {
  const ChatMessageList({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          sliver: const ChatMessagesSliver(),
        ),
      ],
    );
  }
}

class _ConnectionPromptLine extends StatelessWidget {
  const _ConnectionPromptLine({required this.providers, required this.pending});

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
                    color: Color(0xFFC0C0C0),
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
                  color: Colors.white30,
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

class _ActionResultLine extends StatelessWidget {
  const _ActionResultLine({required this.message, required this.success});

  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 8.w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success ? Iconsax.tick_circle : Iconsax.close_circle,
            size: 18.sp,
            color: success ? const Color(0xFF34C759) : const Color(0xFFFF3B30),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.instrumentSans(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF3C3C43),
                height: 1.35,
              ),
            ),
          ),
        ],
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
            fontSize: 10.sp,
            fontWeight: FontWeight.w500,
            color: Colors.white54,
            letterSpacing: 0.25,
          ),
        ),
      ),
    );
  }
}
