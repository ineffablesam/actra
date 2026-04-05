from __future__ import annotations

from typing import Any

import asyncpg
import structlog

from src.config import Settings
from src.memory.embedding import EmbeddingBackend
from src.memory.long_term import LongTermMemoryStore
from src.memory.scoring import score_message_importance
from src.memory.short_term import ShortTermMemoryStore
from src.utils.redis_client import RedisStore

logger = structlog.get_logger(__name__)


class MemoryService:
    """
    Facade for short-term (Redis) + long-term (Chroma + optional Postgres) memory.

    Exposes ``short_term`` / ``long_term`` for direct access and helpers used by handlers.
    """

    def __init__(
        self,
        settings: Settings,
        redis: RedisStore,
        pg_pool: asyncpg.Pool | None,
    ) -> None:
        self._settings = settings
        self.short_term = ShortTermMemoryStore(redis, settings)
        self._embedding = EmbeddingBackend(settings.memory_embedding_model)
        self.long_term = LongTermMemoryStore(settings, self._embedding, pg_pool)

    async def warmup(self) -> None:
        """
        Load the sentence-transformers model at process start.

        Without this, the first user message blocks on HF download + load (~10s+ in Docker).
        Failures are logged but do not abort the server (first request may retry load).
        """
        try:
            await self._embedding.embed_text("warmup")
            logger.info("memory_warmup_complete", model=self._settings.memory_embedding_model)
        except Exception as e:
            logger.warning(
                "memory_warmup_failed",
                model=self._settings.memory_embedding_model,
                error=str(e),
                exc_info=True,
            )

    async def save_memory(
        self,
        user_id: str,
        content: str,
        metadata: dict[str, Any] | None,
        importance_score: float,
    ) -> str:
        """Persist a long-term memory row (embed + Chroma + optional Postgres)."""
        return await self.long_term.save_memory(user_id, content, metadata, importance_score)

    async def retrieve_memories(
        self,
        user_id: str,
        query: str,
        top_k: int = 3,
    ) -> list[dict[str, Any]]:
        """Vector search over memories for the user."""
        return await self.long_term.retrieve_memories(user_id, query, top_k=top_k)

    async def append_exchange(
        self,
        user_id: str,
        *,
        user_text: str,
        assistant_text: str,
    ) -> None:
        """Append both sides of a turn (used if you batch at end of request)."""
        await self.short_term.append(user_id, "user", user_text)
        await self.short_term.append(user_id, "assistant", assistant_text)

    async def maybe_persist_user_turn(
        self,
        user_id: str,
        user_text: str,
        *,
        metadata: dict[str, Any] | None = None,
    ) -> str | None:
        """
        Heuristically decide whether to store ``user_text`` long-term; if so, embed + persist.

        Returns the Chroma id when stored, otherwise ``None``.
        """
        decision = score_message_importance(user_text)
        if not decision.should_store:
            return None

        meta = dict(metadata or {})
        meta["importance_reason"] = decision.reason
        return await self.long_term.save_memory(
            user_id,
            user_text,
            meta,
            decision.score,
        )
