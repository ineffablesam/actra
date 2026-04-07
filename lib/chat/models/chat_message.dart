import 'package:actra/chat/models/message_type.dart';

class DraftPayload {
  DraftPayload({
    required this.to,
    required this.subject,
    required this.body,
    this.cc = const [],
  });

  final String to;
  final String subject;
  final String body;
  final List<String> cc;
}

/// GitHub PR approval card (from backend `draft_ready` type `github_pr`).
class GithubPrDraftPayload {
  GithubPrDraftPayload({
    required this.owner,
    required this.repo,
    required this.baseBranch,
    required this.headBranch,
    required this.filePath,
    required this.fileContent,
    required this.prTitle,
    required this.prBody,
    required this.commitMessage,
  });

  final String owner;
  final String repo;
  final String baseBranch;
  final String headBranch;
  final String filePath;
  final String fileContent;
  final String prTitle;
  final String prBody;
  final String commitMessage;

  factory GithubPrDraftPayload.fromJson(Map<String, dynamic> j) {
    return GithubPrDraftPayload(
      owner: j['owner'] as String? ?? '',
      repo: j['repo'] as String? ?? '',
      baseBranch: j['base_branch'] as String? ?? 'main',
      headBranch: j['head_branch'] as String? ?? '',
      filePath: j['file_path'] as String? ?? '',
      fileContent: j['file_content'] as String? ?? '',
      prTitle: j['pr_title'] as String? ?? '',
      prBody: j['pr_body'] as String? ?? '',
      commitMessage: j['commit_message'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'draft_type': 'github_pr',
        'owner': owner,
        'repo': repo,
        'base_branch': baseBranch,
        'head_branch': headBranch,
        'file_path': filePath,
        'file_content': fileContent,
        'pr_title': prTitle,
        'pr_body': prBody,
        'commit_message': commitMessage,
      };
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.type,
    this.text,
    this.providers,
    this.draft,
    this.githubPrDraft,
    this.success,
    required this.timestamp,
    this.isStreaming = false,
    this.isCodeStream = false,
    this.reason,
    this.taskContext,
    this.actionId,
    this.connectionPromptPending = false,
  });

  final String id;
  MessageType type;
  String? text;
  List<String>? providers;
  final DraftPayload? draft;
  final GithubPrDraftPayload? githubPrDraft;
  final bool? success;
  final DateTime timestamp;
  bool isStreaming;
  final bool isCodeStream;
  final String? reason;
  final String? taskContext;
  final String? actionId;

  /// When [type] is [MessageType.connectionsRequired], true until resolved or partially updated.
  bool connectionPromptPending;
}
