from __future__ import annotations

import asyncpg

from src.config import Settings


async def create_pool(settings: Settings) -> asyncpg.Pool:
    if not settings.database_url:
        raise RuntimeError("DATABASE_URL is not set")
    return await asyncpg.create_pool(settings.database_url, min_size=1, max_size=10)


async def init_schema(pool: asyncpg.Pool) -> None:
    async with pool.acquire() as conn:
        await conn.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                auth0_sub TEXT PRIMARY KEY,
                email TEXT,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            );
            """
        )


async def close_pool(pool: asyncpg.Pool | None) -> None:
    if pool is not None:
        await pool.close()
