from __future__ import annotations

import asyncio
from functools import lru_cache
from typing import Any

import numpy as np
import structlog

logger = structlog.get_logger(__name__)


@lru_cache(maxsize=1)
def _load_model(model_id: str) -> Any:
    """Load sentence-transformers model once per process (CPU)."""
    from sentence_transformers import SentenceTransformer

    logger.info("embedding_model_loading", model_id=model_id)
    return SentenceTransformer(model_id)


class EmbeddingBackend:
    """Thin async-friendly wrapper around sentence-transformers (runs encode in a thread)."""

    def __init__(self, model_id: str) -> None:
        self._model_id = model_id

    async def embed_text(self, text: str) -> list[float]:
        """Return a single embedding vector for ``text``."""
        t = (text or "").strip()
        if not t:
            raise ValueError("Cannot embed empty text")

        def _encode() -> list[float]:
            model = _load_model(self._model_id)
            vec = model.encode(t, convert_to_numpy=True, normalize_embeddings=True)
            if isinstance(vec, np.ndarray):
                return vec.astype(np.float32).tolist()
            raise RuntimeError("Unexpected embedding type")

        return await asyncio.to_thread(_encode)

    async def embed_batch(self, texts: list[str]) -> list[list[float]]:
        """Encode multiple strings in one model call."""

        def _encode_batch() -> list[list[float]]:
            model = _load_model(self._model_id)
            vecs = model.encode(
                texts,
                convert_to_numpy=True,
                normalize_embeddings=True,
            )
            if isinstance(vecs, np.ndarray):
                return vecs.astype(np.float32).tolist()
            raise RuntimeError("Unexpected embedding batch type")

        return await asyncio.to_thread(_encode_batch)
