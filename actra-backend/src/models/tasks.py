from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class PendingTask(BaseModel):
    """Cached in Redis when OAuth connections are missing."""

    user_id: str
    session_id: str
    original_text: str
    intent: str
    required_providers: list[str]
    entities: dict[str, Any] = Field(default_factory=dict)
    reasoning: str = ""
