import 'dart:math' as math;

import 'package:actra/widgets/realtime_typewriter_transcript.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gradient_borders/box_borders/gradient_box_border.dart';
import 'package:url_launcher/url_launcher.dart';

/// Soft glass-style assistant bubble tuned for light mesh backgrounds.
class AgentBubble extends StatelessWidget {
  const AgentBubble({
    super.key,
    required this.text,
    this.isStreaming = false,
    this.isCode = false,
  });

  final String text;
  final bool isStreaming;
  final bool isCode;

  static const Color _kText = Color(0xFFFFFFFF);
  static const Color _kMuted = Color(0x993C3C43);

  @override
  Widget build(BuildContext context) {
    final baseStyle = isCode
        ? GoogleFonts.robotoMono(
            color: const Color(0xFFE8E0FF),
            fontSize: 12.sp,
            height: 1.4,
            fontWeight: FontWeight.w400,
          )
        : GoogleFonts.instrumentSans(
            color: _kText,
            fontSize: 15.sp,
            height: 1.38,
            fontWeight: FontWeight.w400,
          );

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(right: 40.w, bottom: 10.h),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: isCode ? const Color(0x22000000) : Colors.white.withValues(alpha: 0.1),
          image: DecorationImage(
            fit: BoxFit.cover,
            image: AssetImage("assets/images/chat_bubble_bg.png"),
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
          border: const GradientBoxBorder(
            gradient: LinearGradient(
              begin: AlignmentGeometry.topLeft,
              end: AlignmentGeometry.bottomRight,
              colors: [Color(0xFFEDD9FF), Colors.white10, Color(0xFFC887FF)],
            ),
            width: 0.7,
          ),
        ),
        child: isStreaming && text.trim().isEmpty
            ? const _StreamPrimingDots()
            : isStreaming
            ? RealtimeTypewriterTranscript(
                text: text,
                showListeningWhenEmpty: false,
                wrapAlignment: WrapAlignment.start,
                lineTextAlign: TextAlign.left,
                style: baseStyle,
                placeholderStyle: baseStyle.copyWith(color: _kMuted),
                wordDelay: const Duration(milliseconds: 42),
              )
            : isCode
                ? SelectableText(text, style: baseStyle)
                : _AgentMarkdown(
                    data: text,
                    styleSheet: _agentBubbleMarkdownStyle(baseStyle),
                  ),
      ),
    );
  }
}

MarkdownStyleSheet _agentBubbleMarkdownStyle(TextStyle base) {
  final muted = base.copyWith(color: AgentBubble._kMuted);
  final code = GoogleFonts.robotoMono(
    color: const Color(0xFFE8E0FF),
    fontSize: 12.sp,
    height: 1.35,
    fontWeight: FontWeight.w400,
  );
  return MarkdownStyleSheet(
    p: base,
    pPadding: EdgeInsets.only(bottom: 6.h),
    h1: base.copyWith(fontSize: 17.sp, fontWeight: FontWeight.w700, height: 1.25),
    h2: base.copyWith(fontSize: 16.sp, fontWeight: FontWeight.w700, height: 1.28),
    h3: base.copyWith(fontSize: 15.sp, fontWeight: FontWeight.w600, height: 1.3),
    h1Padding: EdgeInsets.only(top: 4.h, bottom: 4.h),
    h2Padding: EdgeInsets.only(top: 4.h, bottom: 4.h),
    h3Padding: EdgeInsets.only(top: 2.h, bottom: 4.h),
    strong: base.copyWith(fontWeight: FontWeight.w700),
    em: base.copyWith(fontStyle: FontStyle.italic),
    code: code.copyWith(
      backgroundColor: Colors.black.withValues(alpha: 0.22),
    ),
    blockquote: muted,
    blockquotePadding: EdgeInsets.only(left: 10.w, top: 2.h, bottom: 2.h),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: const Color(0xFFEDD9FF).withValues(alpha: 0.65),
          width: 3,
        ),
      ),
    ),
    a: base.copyWith(
      color: const Color(0xFFEBD2FF),
      decoration: TextDecoration.underline,
      decorationColor: const Color(0xFFEBD2FF).withValues(alpha: 0.5),
    ),
    listBullet: base,
    tableHead: base.copyWith(fontWeight: FontWeight.w600),
    tableBody: base,
    tableBorder: TableBorder.all(
      color: Colors.white.withValues(alpha: 0.12),
      width: 0.5,
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
      ),
    ),
  );
}

/// GitHub-flavored markdown for completed assistant text; links open externally.
class _AgentMarkdown extends StatelessWidget {
  const _AgentMarkdown({
    required this.data,
    required this.styleSheet,
  });

  final String data;
  final MarkdownStyleSheet styleSheet;

  Future<void> _onTapLink(String text, String? href, String title) async {
    if (href == null || href.isEmpty) return;
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: styleSheet,
      shrinkWrap: true,
      fitContent: true,
      onTapLink: _onTapLink,
    );
  }
}

/// Shown for the first frames of a stream before any token arrives.
class _StreamPrimingDots extends StatefulWidget {
  const _StreamPrimingDots();

  @override
  State<_StreamPrimingDots> createState() => _StreamPrimingDotsState();
}

class _StreamPrimingDotsState extends State<_StreamPrimingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          const base = 0.35;
          const amp = 0.55;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final phase = _c.value * 2 * math.pi + i * (math.pi / 2.2);
              final opacity = base + amp * (0.5 + 0.5 * math.sin(phase));
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: 3.w),
                child: Opacity(
                  opacity: opacity.clamp(0.25, 1.0),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF8E8E93),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
