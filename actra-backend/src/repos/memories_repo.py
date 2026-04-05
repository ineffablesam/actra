from __future__ import annotations

import json
from typing import Any

import asyncpg
import structlog

logger = structlog.get_logger(__name__)


class MemoriesRepository:
    """Persist long-term memory rows for audit / SQL access (optional when DATABASE_URL is set)."""

    def __init__(self, pool: asyncpg.Pool) -> None:
        self._pool = pool

    async def insert(
        self,
        *,
        user_id: str,
        content: str,
        importance_score: float,
        metadata: dict[str, Any],
        chroma_id: str,
    ) -> None:
        meta_json = json.dumps(metadata)
        async with self._pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO agent_memories (user_id, content, importance_score, metadata, chroma_id)
                VALUES ($1, $2, $3, $4::jsonb, $5)
                """,
                user_id,
                content,
                float(importance_score),
                meta_json,
                chroma_id,
            )
