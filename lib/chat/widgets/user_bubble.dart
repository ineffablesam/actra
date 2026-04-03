import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: EdgeInsets.only(left: 48.w, bottom: 10.h),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          ),
          gradient: LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic, color: Colors.white.withOpacity(0.9), size: 16.sp),
            SizedBox(width: 8.w),
            Flexible(
              child: Text(
                text,
                style: GoogleFonts.instrumentSans(
                  color: Colors.white,
                  fontSize: 14.sp,
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
