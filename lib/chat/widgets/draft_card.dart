import 'package:actra/chat/controllers/chat_controller.dart';
import 'package:actra/chat/models/chat_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

class DraftCard extends StatefulWidget {
  const DraftCard({super.key, required this.message});

  final ChatMessage message;

  @override
  State<DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends State<DraftCard> {
  late final TextEditingController _to;
  late final TextEditingController _subj;
  late final TextEditingController _body;
  bool _editing = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    final d = widget.message.draft!;
    _to = TextEditingController(text: d.to);
    _subj = TextEditingController(text: d.subject);
    _body = TextEditingController(text: d.body);
  }

  @override
  void dispose() {
    _to.dispose();
    _subj.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actionId = widget.message.actionId ?? '';
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _to,
            readOnly: !_editing,
            style: GoogleFonts.instrumentSans(color: Colors.white, fontSize: 13.sp),
            decoration: _dec('To'),
          ),
          SizedBox(height: 8.h),
          TextField(
            controller: _subj,
            readOnly: !_editing,
            style: GoogleFonts.instrumentSans(color: Colors.white, fontSize: 13.sp),
            decoration: _dec('Subject'),
          ),
          SizedBox(height: 8.h),
          TextField(
            controller: _body,
            readOnly: !_editing,
            maxLines: 4,
            style: GoogleFonts.instrumentSans(color: Colors.white70, fontSize: 13.sp),
            decoration: _dec('Body'),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              TextButton(
                onPressed: _sent ? null : () => setState(() => _editing = !_editing),
                child: const Text('Edit'),
              ),
              ElevatedButton.icon(
                onPressed: _sent || actionId.isEmpty
                    ? null
                    : () {
                        final chat = Get.find<ChatController>();
                        chat.confirmDraft(
                          actionId,
                          DraftPayload(
                            to: _to.text,
                            subject: _subj.text,
                            body: _body.text,
                          ),
                        );
                        setState(() => _sent = true);
                      },
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(_sent ? 'Sent!' : 'Send'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                ),
              ),
              if (_sent) ...[
                SizedBox(width: 8.w),
                const Icon(Icons.check_circle, color: Colors.greenAccent),
              ],
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.instrumentSans(color: Colors.white54),
      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF7C3AED))),
    );
  }
}
