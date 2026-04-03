import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

class AgentBubble extends StatelessWidget {
  const AgentBubble({
    super.key,
    required this.text,
    this.isStreaming = false,
  });

  final String text;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(right: 48.w, bottom: 10.h),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E2E),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('✦', style: TextStyle(color: Colors.purple.shade200, fontSize: 12.sp)),
            SizedBox(width: 8.w),
            Flexible(
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.instrumentSans(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 14.sp,
                    height: 1.35,
                  ),
                  children: [
                    TextSpan(text: text),
                    if (isStreaming)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: _BlinkCursor(),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlinkCursor extends StatefulWidget {
  @override
  State<_BlinkCursor> createState() => _BlinkCursorState();
}

class _BlinkCursorState extends State<_BlinkCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: const Text('▍', style: TextStyle(color: Colors.white70)),
    );
  }
}
