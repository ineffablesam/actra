from __future__ import annotations

import json
import time
import uuid
from typing import Any

import asyncpg
import structlog
import chromadb

from src.config import Settings
from src.memory.embedding import EmbeddingBackend
from src.repos.memories_repo import MemoriesRepository

logger = structlog.get_logger(__name__)


def _now_ts() -> float:
    return time.time()


class LongTermMemoryStore:
    """
    Chroma-backed vector store scoped per ``user_id`` via metadata filters.

    Optional Postgres rows mirror inserts for durability and SQL tooling.
    """

    def __init__(
        self,
        settings: Settings,
        embedding: EmbeddingBackend,
        pg_pool: asyncpg.Pool | None,
    ) -> None:
        self._settings = settings
        self._embedding = embedding
        self._pg_pool = pg_pool
        self._repo = MemoriesRepository(pg_pool) if pg_pool is not None else None
        self._client = chromadb.PersistentClient(path=settings.memory_chroma_path)
        self._collection = self._client.get_or_create_collection(
            name=settings.memory_chroma_collection,
            metadata={"hnsw:space": "cosine"},
        )

    async def save_memory(
        self,
        user_id: str,
        content: str,
        metadata: dict[str, Any] | None,
        importance_score: float,
    ) -> str:
        """
        Embed ``content``, upsert into Chroma, and optionally insert into Postgres.

        Returns the Chroma point id.
        """
        text = (content or "").strip()
        if not text:
            raise ValueError("content is empty")

        meta = dict(metadata or {})
        point_id = str(uuid.uuid4())
        ts = _now_ts()
        emb = await self._embedding.embed_text(text)

        meta_payload = {
            "user_id": user_id,
            "content": text,
            "timestamp": float(ts),
            "importance_score": float(importance_score),
            "meta_json": json.dumps(meta),
        }

        self._collection.add(
            ids=[point_id],
            embeddings=[emb],
            documents=[text],
            metadatas=[meta_payload],
        )

        if self._repo is not None:
            try:
                await self._repo.insert(
                    user_id=user_id,
                    content=text,
                    importance_score=importance_score,
                    metadata=meta,
                    chroma_id=point_id,
                )
            except Exception as e:
                logger.warning(
                    "memory_postgres_insert_failed",
                    user_id=user_id,
                    chroma_id=point_id,
                    error=str(e),
                    exc_info=True,
                )

        return point_id

    async def retrieve_memories(
        self,
        user_id: str,
        query: str,
        top_k: int = 3,
    ) -> list[dict[str, Any]]:
        """
        Return up to ``top_k`` relevant memories for ``user_id`` as dicts:

        ``user_id``, ``content``, ``timestamp``, ``importance_score``, ``metadata``, ``distance`` (if present).
        """
        q = (query or "").strip()
        if not q:
            return []

        emb = await self._embedding.embed_text(q)
        n = max(1, min(top_k, 25))

        raw = self._collection.query(
            query_embeddings=[emb],
            n_results=n,
            where={"user_id": user_id},
            include=["documents", "metadatas", "distances"],
        )

        ids = raw.get("ids") or []
        docs = raw.get("documents") or []
        metas = raw.get("metadatas") or []
        dists = raw.get("distances") or []

        row_ids = ids[0] if ids else []
        row_docs = docs[0] if docs else []
        row_metas = metas[0] if metas else []
        row_dists = dists[0] if dists else []

        out: list[dict[str, Any]] = []
        for i, cid in enumerate(row_ids):
            m = row_metas[i] if i < len(row_metas) else {}
            doc = row_docs[i] if i < len(row_docs) else ""
            if not isinstance(m, dict):
                m = {}
            meta_obj: dict[str, Any]
            try:
                meta_obj = json.loads(str(m.get("meta_json") or "{}"))
            except json.JSONDecodeError:
                meta_obj = {}

            item: dict[str, Any] = {
                "id": cid,
                "user_id": user_id,
                "content": doc or str(m.get("content") or ""),
                "timestamp": float(m.get("timestamp") or 0.0),
                "importance_score": float(m.get("importance_score") or 0.0),
                "metadata": meta_obj,
            }
            if i < len(row_dists):
                item["distance"] = float(row_dists[i])
            out.append(item)
        return out
