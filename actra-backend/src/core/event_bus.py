from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from typing import Any

import structlog

logger = structlog.get_logger(__name__)


class EventBus:
    """Simple in-process async pub/sub for server-side coordination."""

    def __init__(self) -> None:
        self._subs: dict[str, list[Callable[[dict[str, Any]], Awaitable[None]]]] = {}
        self._lock = asyncio.Lock()

    async def subscribe(
        self,
        channel: str,
        handler: Callable[[dict[str, Any]], Awaitable[None]],
    ) -> None:
        async with self._lock:
            self._subs.setdefault(channel, []).append(handler)

    async def publish(self, channel: str, payload: dict[str, Any]) -> None:
        async with self._lock:
            handlers = list(self._subs.get(channel, []))
        for h in handlers:
            try:
                await h(payload)
            except Exception as e:
                logger.warning("event_handler_failed", channel=channel, error=str(e))
