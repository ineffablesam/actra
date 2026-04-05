enum MessageType {
  userTranscript,
  agentThinking,
  agentStream,
  agentFinal,
  connectionsRequired,
  /// Minimal centered line after a successful Token Vault link (e.g. "Connected to Slack").
  systemConnectionStatus,
  draftReady,
  actionResult,
}
