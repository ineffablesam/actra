"""Structured error context for logs. Never log secrets or tokens."""

from __future__ import annotations

from typing import Any


def err_ctx(exc: BaseException) -> dict[str, Any]:
    return {
        "error_type": type(exc).__name__,
        "error_message": str(exc),
    }
