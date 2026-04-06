import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gradient_borders/box_borders/gradient_box_border.dart';

class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.text});

  final String text;

  static const Color _kText = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: EdgeInsets.only(left: 40.w, bottom: 10.h),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 11.h),
        decoration: BoxDecoration(
          // color: Colors.white.withOpacity(0.1),
          // image: DecorationImage(
          //   fit: BoxFit.cover,
          //   image: AssetImage("assets/images/chat_bubble_bg.png"),
          // ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(0),
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
          // boxShadow: [
          //   BoxShadow(
          //     color: Color.fromRGBO(0, 0, 0, 0.15),
          //     blurRadius: 25,
          //     spreadRadius: 0,
          //     offset: Offset(0, 15),
          //   ),
          //   BoxShadow(
          //     color: Color.fromRGBO(0, 0, 0, 0.05),
          //     blurRadius: 10,
          //     spreadRadius: 0,
          //     offset: Offset(0, 5),
          //   ),
          // ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                text,
                style: GoogleFonts.instrumentSans(
                  color: _kText,
                  fontSize: 15.sp,
                  height: 1.38,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
