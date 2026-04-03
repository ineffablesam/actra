from __future__ import annotations

import asyncio
import json
from typing import Any

import structlog
from websockets import ServerConnection

logger = structlog.get_logger(__name__)


class ConnectionManager:
    """Tracks active WebSocket connections per session_id."""

    def __init__(self) -> None:
        self._lock = asyncio.Lock()
        self._by_session: dict[str, ServerConnection] = {}

    async def register(self, session_id: str, ws: ServerConnection) -> None:
        async with self._lock:
            self._by_session[session_id] = ws

    async def unregister(self, session_id: str) -> None:
        async with self._lock:
            self._by_session.pop(session_id, None)

    def get(self, session_id: str) -> ServerConnection | None:
        return self._by_session.get(session_id)

    async def send_json(self, session_id: str, payload: dict[str, Any]) -> bool:
        ws = self.get(session_id)
        if not ws:
            logger.warning("no_ws_for_session", session_id=session_id)
            return False
        try:
            await ws.send(json.dumps(payload))
            return True
        except Exception as e:
            logger.warning("ws_send_failed", session_id=session_id, error=str(e))
            return False
