from __future__ import annotations

import json
from typing import Any

import redis.asyncio as redis
import structlog

from src.config import Settings
from src.utils.service_log import err_ctx

logger = structlog.get_logger(__name__)

_SERVICE = "redis"


class RedisStore:
    def __init__(self, settings: Settings) -> None:
        self._url = settings.redis_url
        self._client: redis.Redis | None = None

    async def connect(self) -> None:
        self._client = redis.from_url(self._url, decode_responses=True)

    async def close(self) -> None:
        if self._client:
            await self._client.aclose()
            self._client = None

    @property
    def raw(self) -> redis.Redis:
        if not self._client:
            raise RuntimeError("Redis not connected")
        return self._client

    async def get_json(self, key: str) -> dict[str, Any] | None:
        try:
            raw = await self.raw.get(key)
            if raw is None:
                return None
            return json.loads(raw)
        except Exception as e:
            logger.warning(
                "redis_get_failed",
                service=_SERVICE,
                operation="get_json",
                key=key,
                **err_ctx(e),
                exc_info=True,
            )
            return None

    async def set_json(self, key: str, value: dict[str, Any], ex: int | None = None) -> bool:
        try:
            await self.raw.set(key, json.dumps(value), ex=ex)
            return True
        except Exception as e:
            logger.warning(
                "redis_set_failed",
                service=_SERVICE,
                operation="set_json",
                key=key,
                **err_ctx(e),
                exc_info=True,
            )
            return False

    async def delete(self, key: str) -> None:
        try:
            await self.raw.delete(key)
        except Exception as e:
            logger.warning(
                "redis_delete_failed",
                service=_SERVICE,
                operation="delete",
                key=key,
                **err_ctx(e),
                exc_info=True,
            )
