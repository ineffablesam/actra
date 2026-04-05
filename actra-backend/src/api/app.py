from __future__ import annotations

from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from src.memory.service import MemoryService


class SaveMemoryBody(BaseModel):
    user_id: str = Field(min_length=1)
    content: str = Field(min_length=1)
    metadata: dict[str, Any] = Field(default_factory=dict)
    importance_score: float = Field(ge=0.0, le=1.0)


def create_memory_app(memory: MemoryService) -> FastAPI:
    """Small HTTP surface for health checks and manual memory debugging (hackathon-friendly)."""

    app = FastAPI(title="Actra Memory API", version="1.0.0")

    @app.get("/health")
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/memory/save")
    async def save_memory(body: SaveMemoryBody) -> dict[str, str]:
        try:
            mid = await memory.save_memory(
                body.user_id,
                body.content,
                body.metadata,
                body.importance_score,
            )
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e)) from e
        return {"id": mid}

    @app.get("/memory/search")
    async def search_memory(user_id: str, q: str, top_k: int = 3) -> dict[str, Any]:
        if not user_id.strip():
            raise HTTPException(status_code=400, detail="user_id is required")
        rows = await memory.retrieve_memories(user_id, q, top_k=top_k)
        return {"user_id": user_id, "query": q, "results": rows}

    return app
