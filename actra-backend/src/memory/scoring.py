from __future__ import annotations

import re
from dataclasses import dataclass

# Casual / filler — do not persist to long-term memory.
_CASUAL_PATTERNS = (
    r"^(hi|hey|hello|yo|sup|thanks|thank you|ok|okay|k|sure|cool|nice|bye|goodbye)\s*[!.?]*$",
    r"^(lol|haha|ha)\s*$",
)

# Strong preference / identity signals → HIGH importance.
_HIGH_PHRASES = (
    "remember",
    "always",
    "never forget",
    "i prefer",
    "i'd prefer",
    "i like",
    "i don't like",
    "i hate",
    "i love",
    "my favorite",
    "my email",
    "my name",
    "call me",
    "i'm ",
    "i am ",
)

# App / integration actions (heuristic).
_MEDIUM_KEYWORDS = (
    "connect",
    "connected",
    "disconnect",
    "calendar",
    "gmail",
    "google",
    "slack",
    "send email",
    "draft",
    "schedule",
    "meeting",
    "inbox",
    "token",
    "authorize",
    "permission",
)


@dataclass(frozen=True)
class ImportanceResult:
    """Outcome of heuristic importance scoring for a single user utterance."""

    score: float
    should_store: bool
    reason: str


def score_message_importance(text: str) -> ImportanceResult:
    """
    Assign an importance score in [0, 1] and whether the message should be stored long-term.

    Rules (hackathon-simple):
    - Casual / ultra-short chit-chat → skip storage.
    - Phrases suggesting preferences, identity, or explicit memory requests → HIGH (0.8–1.0).
    - App/integration/action language → MEDIUM (0.5–0.7).
    - Default substantive messages → MEDIUM (0.55).
    """
    raw = (text or "").strip()
    if not raw:
        return ImportanceResult(0.0, False, "empty")

    lower = raw.lower()
    if len(lower) <= 2:
        return ImportanceResult(0.15, False, "too_short")

    for pat in _CASUAL_PATTERNS:
        if re.match(pat, lower, flags=re.IGNORECASE):
            return ImportanceResult(0.2, False, "casual_pattern")

    # Explicit memory / preference language (avoid flagging "connect my Gmail" as identity).
    if (
        any(p in lower for p in _HIGH_PHRASES)
        or lower.startswith("my ")
        or lower.startswith("i'm ")
        or lower.startswith("i am ")
    ):
        # Cap score in [0.8, 1.0]
        score = 0.85
        if "remember" in lower or "never forget" in lower:
            score = 0.95
        return ImportanceResult(min(1.0, score), True, "high_preference_or_memory")

    if any(k in lower for k in _MEDIUM_KEYWORDS):
        return ImportanceResult(0.62, True, "app_or_action_context")

    if len(lower.split()) >= 6:
        return ImportanceResult(0.58, True, "substantive_message")

    # Short but not matched as casual — still skip to reduce noise.
    if len(lower.split()) <= 3:
        return ImportanceResult(0.35, False, "short_non_action")

    return ImportanceResult(0.55, True, "default")
