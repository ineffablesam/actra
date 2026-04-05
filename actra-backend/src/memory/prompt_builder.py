from __future__ import annotations

from typing import Any

# Predefined system instructions for how the downstream LLM should use memory.
ACTRA_MEMORY_SYSTEM_PROMPT = (
    "You are Actra, a voice AI assistant. Use **Recent Conversation** for immediate context "
    "and **Relevant Memory** for stable user-specific facts, preferences, and past actions. "
    "Treat remembered facts as authoritative unless the user clearly overrides them in the "
    "current query."
)


def _format_messages(messages: list[dict[str, Any]]) -> str:
    lines: list[str] = []
    for m in messages:
        role = str(m.get("role", "user"))
        content = str(m.get("content", "")).strip()
        if not content:
            continue
        ts = m.get("timestamp")
        ts_s = f" ({ts})" if ts is not None else ""
        lines.append(f"- {role}{ts_s}: {content}")
    return "\n".join(lines) if lines else "(none)"


def _format_long_term(memories: list[dict[str, Any]]) -> str:
    lines: list[str] = []
    for mem in memories:
        content = str(mem.get("content", "")).strip()
        if not content:
            continue
        imp = mem.get("importance_score")
        dist = mem.get("distance")
        bits: list[str] = []
        if isinstance(imp, int | float):
            bits.append(f"importance={float(imp):.2f}")
        if isinstance(dist, int | float):
            bits.append(f"distance={float(dist):.4f}")
        suffix = f" [{'; '.join(bits)}]" if bits else ""
        lines.append(f"- {content}{suffix}")
    return "\n".join(lines) if lines else "(none)"


def build_prompt(
    user_input: str,
    short_term_memory: list[dict[str, Any]],
    long_term_memory: list[dict[str, Any]],
    *,
    system_prompt: str | None = None,
) -> str:
    """
    Build the combined memory prompt block used upstream of the drafting model.

    Layout:

    System Prompt (predefined)

    Recent Conversation:
    ...

    Relevant Memory:
    ...

    User Query:
    ...
    """
    sys_p = system_prompt or ACTRA_MEMORY_SYSTEM_PROMPT
    u = (user_input or "").strip()

    parts = [
        "System Prompt (predefined)",
        sys_p,
        "",
        "Recent Conversation:",
        _format_messages(short_term_memory),
        "",
        "Relevant Memory:",
        _format_long_term(long_term_memory),
        "",
        "User Query:",
        u if u else "(empty)",
    ]
    return "\n".join(parts)
