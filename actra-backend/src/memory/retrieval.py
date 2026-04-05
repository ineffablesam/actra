from __future__ import annotations

from typing import Any

from src.config import Settings
from src.memory.long_term import LongTermMemoryStore
from src.memory.prompt_builder import build_prompt
from src.memory.short_term import ShortTermMemoryStore

# When the user asks about the past / earlier facts, cosine similarity often ranks the *latest*
# correction ("Samuel") above the *first* introduction ("Sam Yu"). Rerank by time for those queries.
_TEMPORAL_RERANK_MARKERS: tuple[str, ...] = (
    "previous",
    "earlier",
    "originally",
    "old name",
    "first ",
    "what was my",
    "before that",
    "before,",
    "used to",
    "you remembered",
)

# Second retrieval query pulls "introduction-style" memories when the user asks about earlier facts.
_SECONDARY_QUERY_HINT = (
    "first introduction stated name identity said earlier user preference"
)


def _wants_temporal_rerank(user_input: str) -> bool:
    u = (user_input or "").lower()
    return any(m in u for m in _TEMPORAL_RERANK_MARKERS)


def _wants_secondary_retrieval(user_input: str) -> bool:
    """Broaden recall when the question is about name/history, not only the latest turn."""
    u = (user_input or "").lower()
    if _wants_temporal_rerank(user_input):
        return True
    if "name" in u and any(x in u for x in ("remember", "remembered", "said", "told")):
        return True
    return False


def _rerank_memories_for_query(user_input: str, memories: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not memories:
        return memories
    if not _wants_temporal_rerank(user_input):
        return memories
    # Oldest first: "previous" / earlier facts tend to have smaller timestamps.
    return sorted(memories, key=lambda m: float(m.get("timestamp") or 0.0))


def _merge_memories_by_best_distance(a: list[dict[str, Any]], b: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_id: dict[str, dict[str, Any]] = {}
    for m in a + b:
        mid = str(m.get("id") or "")
        if not mid:
            continue
        d = float(m.get("distance", 1e9))
        if mid not in by_id or d < float(by_id[mid].get("distance", 1e9)):
            by_id[mid] = m
    return sorted(by_id.values(), key=lambda x: float(x.get("distance", 0.0)))


async def retrieve_context_bundle(
    *,
    user_id: str,
    user_input: str,
    short_term: ShortTermMemoryStore,
    long_term: LongTermMemoryStore,
    settings: Settings,
    top_k: int | None = None,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], str]:
    """
    Fetch short-term (last N) and long-term (vector search) and build the combined prompt block.

    Vector search is **approximate**: a single embedding of the user question may rank a recent
    correction above an older fact. We optionally run a second query with a neutral "introduction"
    hint and merge results, then rerank by **timestamp** (oldest first) when the user asks about
    *previous* / *earlier* information.

    Returns ``(short_term_messages, long_term_memories, prompt_block)``.
    """
    k = top_k if top_k is not None else settings.memory_retrieval_top_k
    stm = await short_term.get_recent(user_id, limit=settings.memory_short_term_context_n)

    primary = await long_term.retrieve_memories(user_id, user_input, top_k=k)
    if _wants_secondary_retrieval(user_input):
        secondary = await long_term.retrieve_memories(user_id, _SECONDARY_QUERY_HINT, top_k=k)
        ltm = _merge_memories_by_best_distance(primary, secondary)
        ltm = ltm[: min(2 * k, len(ltm))]
    else:
        ltm = primary

    ltm = _rerank_memories_for_query(user_input, ltm)
    ltm = ltm[:k]

    block = build_prompt(user_input, stm, ltm)
    return stm, ltm, block
