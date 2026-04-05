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
        await conn.execute(
            """
            CREATE TABLE IF NOT EXISTS agent_memories (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT NOT NULL,
                content TEXT NOT NULL,
                importance_score DOUBLE PRECISION NOT NULL,
                metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
                chroma_id TEXT,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            );
            CREATE INDEX IF NOT EXISTS idx_agent_memories_user_created
                ON agent_memories (user_id, created_at DESC);
            """
        )


async def close_pool(pool: asyncpg.Pool | None) -> None:
    if pool is not None:
        await pool.close()
