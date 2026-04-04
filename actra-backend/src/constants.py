"""Product limits shared by intent analysis and the transcript pipeline."""

# Token Vault + Google integrations wired in this codebase.
SUPPORTED_PROVIDERS: frozenset[str] = frozenset({"google_gmail", "google_calendar"})
