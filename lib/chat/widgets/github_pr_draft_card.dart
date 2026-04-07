import 'package:actra/chat/controllers/chat_controller.dart';
import 'package:actra/chat/models/chat_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gradient_borders/box_borders/gradient_box_border.dart';

class GithubPrDraftCard extends StatefulWidget {
  const GithubPrDraftCard({super.key, required this.message});

  final ChatMessage message;

  @override
  State<GithubPrDraftCard> createState() => _GithubPrDraftCardState();
}

class _GithubPrDraftCardState extends State<GithubPrDraftCard> {
  late final TextEditingController _filePath;
  late final TextEditingController _code;
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _commit;
  bool _editing = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    final d = widget.message.githubPrDraft!;
    _filePath = TextEditingController(text: d.filePath);
    _code = TextEditingController(text: d.fileContent);
    _title = TextEditingController(text: d.prTitle);
    _body = TextEditingController(text: d.prBody);
    _commit = TextEditingController(text: d.commitMessage);
  }

  @override
  void dispose() {
    _filePath.dispose();
    _code.dispose();
    _title.dispose();
    _body.dispose();
    _commit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actionId = widget.message.actionId ?? '';
    final d = widget.message.githubPrDraft!;
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        image: const DecorationImage(
          fit: BoxFit.cover,
          image: AssetImage('assets/images/chat_bubble_bg.png'),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${d.owner}/${d.repo} · ${d.baseBranch} ← ${d.headBranch}',
            style: GoogleFonts.instrumentSans(
              color: Colors.white70,
              fontSize: 11.sp,
            ),
          ),
          SizedBox(height: 8.h),
          TextField(
            controller: _title,
            readOnly: !_editing,
            style: GoogleFonts.instrumentSans(
              color: Colors.white,
              fontSize: 13.sp,
            ),
            decoration: _dec('PR title'),
          ),
          SizedBox(height: 8.h),
          TextField(
            controller: _filePath,
            readOnly: !_editing,
            style: GoogleFonts.instrumentSans(
              color: Colors.white70,
              fontSize: 12.sp,
            ),
            decoration: _dec('File path'),
          ),
          SizedBox(height: 8.h),
          TextField(
            controller: _code,
            readOnly: !_editing,
            maxLines: 10,
            style: GoogleFonts.robotoMono(
              color: const Color(0xFFE8E0FF),
              fontSize: 11.sp,
              height: 1.35,
            ),
            decoration: _dec('Proposed file contents'),
          ),
          SizedBox(height: 8.h),
          TextField(
            controller: _body,
            readOnly: !_editing,
            maxLines: 3,
            style: GoogleFonts.instrumentSans(
              color: Colors.white70,
              fontSize: 12.sp,
            ),
            decoration: _dec('PR description (markdown)'),
          ),
          SizedBox(height: 8.h),
          TextField(
            controller: _commit,
            readOnly: !_editing,
            style: GoogleFonts.instrumentSans(
              color: Colors.white54,
              fontSize: 11.sp,
            ),
            decoration: _dec('Commit message'),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              TextButton(
                onPressed: _sent
                    ? null
                    : () => setState(() => _editing = !_editing),
                child: Text(
                  'Edit',
                  style: TextStyle(
                    color: !_sent ? Color(0xFFEBD2FF) : Color(0x77CBCBCB),
                  ),
                ),
              ),
              InkWell(
                onTap: (_sent || actionId.isEmpty)
                    ? null
                    : () {
                        final chat = Get.find<ChatController>();
                        chat.confirmGithubPrDraft(
                          actionId,
                          GithubPrDraftPayload(
                            owner: d.owner,
                            repo: d.repo,
                            baseBranch: d.baseBranch,
                            headBranch: d.headBranch,
                            filePath: _filePath.text,
                            fileContent: _code.text,
                            prTitle: _title.text,
                            prBody: _body.text,
                            commitMessage: _commit.text,
                          ),
                        );
                        setState(() => _sent = true);
                      },
                borderRadius: BorderRadius.circular(20.r),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 8.h,
                  ),
                  decoration: BoxDecoration(
                    color: (_sent || actionId.isEmpty)
                        ? Colors.white.withOpacity(0.05)
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20.r),
                    border: const GradientBoxBorder(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        transform: GradientRotation(1),
                        colors: [
                          Color(0xFFFFFFFF),
                          Colors.white10,
                          Color(0xFFFFFFFF),
                        ],
                      ),
                      width: 0.7,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.merge_type_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        _sent ? 'Opened' : 'Open PR',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
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
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.white24),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF7C3AED)),
      ),
    );
  }
}
