from __future__ import annotations

import time
from typing import Any

import structlog

from src.config import Settings
from src.utils.redis_client import RedisStore

logger = structlog.get_logger(__name__)


def _key(user_id: str) -> str:
    return f"stm:v1:{user_id}"


class ShortTermMemoryStore:
    """
    Rolling conversation buffer per user (Redis JSON list).

    Keeps the last ``max_messages`` turns; older entries are dropped from the left.
    """

    def __init__(self, redis: RedisStore, settings: Settings) -> None:
        self._redis = redis
        self._max = max(5, min(settings.memory_short_term_max, 50))

    async def append(self, user_id: str, role: str, content: str) -> None:
        """Append one message and trim to the configured maximum length."""
        entry: dict[str, Any] = {
            "role": role,
            "content": (content or "").strip(),
            "timestamp": time.time(),
        }
        if not entry["content"]:
            return

        data = await self._redis.get_json(_key(user_id)) or {"messages": []}
        messages: list[dict[str, Any]] = list(data.get("messages") or [])
        messages.append(entry)
        overflow = max(0, len(messages) - self._max)
        if overflow:
            messages = messages[overflow:]
        await self._redis.set_json(_key(user_id), {"messages": messages})

    async def get_recent(self, user_id: str, limit: int = 5) -> list[dict[str, Any]]:
        """Return up to ``limit`` most recent messages (each dict has role, content, timestamp)."""
        data = await self._redis.get_json(_key(user_id)) or {"messages": []}
        messages: list[dict[str, Any]] = list(data.get("messages") or [])
        if limit <= 0:
            return []
        return messages[-limit:]

    async def clear(self, user_id: str) -> None:
        await self._redis.delete(_key(user_id))
