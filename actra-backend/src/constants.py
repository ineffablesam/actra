"""Product limits shared by intent analysis and the transcript pipeline."""

# Token Vault–backed integrations (Auth0 federated connection per provider).
SUPPORTED_PROVIDERS: frozenset[str] = frozenset(
    {"google_gmail", "google_calendar", "slack"},
)
