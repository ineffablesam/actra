import 'package:actra/chat/controllers/chat_controller.dart';
import 'package:actra/chat/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

class ConnectionPanel extends StatelessWidget {
  const ConnectionPanel({
    super.key,
    required this.providers,
    required this.reason,
  });

  final List<String> providers;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: const Color(0xFF252536),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connect accounts to continue',
            style: GoogleFonts.instrumentSans(
              color: Colors.white,
              fontSize: 15.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            reason,
            style: GoogleFonts.instrumentSans(
              color: Colors.white70,
              fontSize: 12.sp,
            ),
          ),
          SizedBox(height: 12.h),
          ...providers.map((p) => _tile(p)),
        ],
      ),
    );
  }

  Widget _tile(String provider) {
    final isGmail = provider.contains('gmail');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isGmail ? Icons.mail_outline : Icons.calendar_month,
        color: isGmail ? Colors.redAccent : Colors.blueAccent,
      ),
      title: Text(
        isGmail ? 'Gmail' : 'Calendar',
        style: GoogleFonts.instrumentSans(color: Colors.white),
      ),
      subtitle: Text(
        'Not connected',
        style: GoogleFonts.instrumentSans(color: Colors.white38, fontSize: 11.sp),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
        onPressed: () {
          Get.find<WebSocketService>().sendAccountConnected(provider);
          Get.find<ChatController>().pendingProviders.remove(provider);
        },
      ),
    );
  }
}
