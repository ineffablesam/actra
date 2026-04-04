from __future__ import annotations

from typing import Any

import asyncpg
import structlog

logger = structlog.get_logger(__name__)


class UsersRepository:
    def __init__(self, pool: asyncpg.Pool) -> None:
        self._pool = pool

    async def upsert_from_claims(self, *, auth0_sub: str, email: str | None) -> None:
        async with self._pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO users (auth0_sub, email, updated_at)
                VALUES ($1, $2, NOW())
                ON CONFLICT (auth0_sub) DO UPDATE SET
                    email = COALESCE(EXCLUDED.email, users.email),
                    updated_at = NOW();
                """,
                auth0_sub,
                email,
            )
        logger.info("user_upserted", auth0_sub=auth0_sub)
