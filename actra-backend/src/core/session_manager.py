from __future__ import annotations

from typing import Any

import structlog

from src.models.tasks import PendingTask
from src.utils.redis_client import RedisStore

logger = structlog.get_logger(__name__)

SESSION_STATE_TTL = 3600
PENDING_TASK_TTL = 1800
USER_PROVIDERS_TTL = 60


class SessionManager:
    def __init__(self, redis: RedisStore) -> None:
        self._redis = redis

    def _session_key(self, session_id: str) -> str:
        return f"session:{session_id}:state"

    def _pending_key(self, session_id: str) -> str:
        return f"session:{session_id}:pending_task"

    def _refresh_key(self, session_id: str) -> str:
        return f"session:{session_id}:refresh_token"

    def _auth0_access_key(self, session_id: str) -> str:
        return f"session:{session_id}:auth0_access_token"

    def _verified_sub_key(self, session_id: str) -> str:
        return f"session:{session_id}:verified_sub"

    def _user_providers_key(self, user_id: str) -> str:
        return f"user:{user_id}:connected_providers"

    async def get_session_state(self, session_id: str) -> dict[str, Any] | None:
        return await self._redis.get_json(self._session_key(session_id))

    async def set_session_state(self, session_id: str, state: dict[str, Any]) -> None:
        await self._redis.set_json(self._session_key(session_id), state, ex=SESSION_STATE_TTL)

    async def set_pending_task(self, session_id: str, task: PendingTask) -> None:
        await self._redis.set_json(
            self._pending_key(session_id),
            task.model_dump(),
            ex=PENDING_TASK_TTL,
        )

    async def get_pending_task(self, session_id: str) -> PendingTask | None:
        data = await self._redis.get_json(self._pending_key(session_id))
        if not data:
            return None
        return PendingTask.model_validate(data)

    async def clear_pending_task(self, session_id: str) -> None:
        await self._redis.delete(self._pending_key(session_id))

    async def set_user_connected_providers(self, user_id: str, providers: list[str]) -> None:
        await self._redis.set_json(
            self._user_providers_key(user_id),
            {"providers": providers},
            ex=USER_PROVIDERS_TTL,
        )

    async def get_user_connected_providers(self, user_id: str) -> list[str] | None:
        data = await self._redis.get_json(self._user_providers_key(user_id))
        if not data:
            return None
        return list(data.get("providers", []))

    async def invalidate_user_providers(self, user_id: str) -> None:
        await self._redis.delete(self._user_providers_key(user_id))

    async def set_refresh_token(self, session_id: str, refresh_token: str) -> None:
        await self._redis.set_json(
            self._refresh_key(session_id),
            {"refresh_token": refresh_token},
            ex=SESSION_STATE_TTL,
        )
        logger.info(
            "session_refresh_token_stored",
            session_id=session_id,
            refresh_token_chars=len(refresh_token),
        )

    async def set_verified_sub(self, session_id: str, sub: str) -> None:
        await self._redis.set_json(
            self._verified_sub_key(session_id),
            {"sub": sub},
            ex=SESSION_STATE_TTL,
        )
        logger.info("session_verified_sub_stored", session_id=session_id, auth0_sub=sub)

    async def get_verified_sub(self, session_id: str) -> str | None:
        data = await self._redis.get_json(self._verified_sub_key(session_id))
        if not data:
            return None
        s = str(data.get("sub", "")).strip()
        return s or None

    async def verify_session_user(self, session_id: str, user_id: str) -> bool:
        """Returns True if [require_auth0_jwt] gate passes: user_id matches stored verified sub."""
        if not session_id or not user_id:
            return False
        verified = await self.get_verified_sub(session_id)
        if not verified:
            return False
        return verified == user_id

    async def get_refresh_token(self, session_id: str) -> str | None:
        data = await self._redis.get_json(self._refresh_key(session_id))
        if not data:
            logger.info("session_refresh_token_miss", session_id=session_id)
            return None
        tok = str(data.get("refresh_token", "")) or None
        if tok:
            logger.debug(
                "session_refresh_token_hit",
                session_id=session_id,
                refresh_token_chars=len(tok),
            )
        return tok

    async def set_auth0_access_token(self, session_id: str, access_token: str) -> None:
        await self._redis.set_json(
            self._auth0_access_key(session_id),
            {"access_token": access_token},
            ex=SESSION_STATE_TTL,
        )
        logger.info(
            "session_auth0_access_token_stored",
            session_id=session_id,
            access_token_chars=len(access_token),
        )

    async def get_auth0_access_token(self, session_id: str) -> str | None:
        data = await self._redis.get_json(self._auth0_access_key(session_id))
        if not data:
            logger.info("session_auth0_access_token_miss", session_id=session_id)
            return None
        tok = str(data.get("access_token", "")) or None
        if tok:
            logger.debug(
                "session_auth0_access_token_hit",
                session_id=session_id,
                access_token_chars=len(tok),
            )
        return tok

    async def add_connected_provider(self, user_id: str, provider: str) -> None:
        existing = await self.get_user_connected_providers(user_id) or []
        merged = list(dict.fromkeys([*existing, provider]))
        await self.set_user_connected_providers(user_id, merged)

    async def clear_session(self, session_id: str) -> None:
        """Remove Redis state for a WebSocket session (logout or disconnect)."""
        await self._redis.delete(self._session_key(session_id))
        await self._redis.delete(self._pending_key(session_id))
        await self._redis.delete(self._refresh_key(session_id))
        await self._redis.delete(self._auth0_access_key(session_id))
        await self._redis.delete(self._verified_sub_key(session_id))
