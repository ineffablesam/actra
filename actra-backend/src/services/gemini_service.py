from __future__ import annotations

import json
import re
from collections.abc import Awaitable, Callable
from typing import Any

import structlog
from google import genai

from src.config import Settings
from src.utils.service_log import err_ctx

logger = structlog.get_logger(__name__)

_SERVICE = "gemini"

INTENT_SYSTEM = """ You are Actra, a voice AI assistant. Analyze the user's request and return ONLY valid JSON with this exact schema - no markdown, no explanation, JSON only: { "intent": "send_email" | "create_event" | "read_emails" | "check_calendar" | "unknown", "required_providers": ["google_gmail", "google_calendar"], "confidence": 0.0-1.0, "entities": { "to": "person name or email if mentioned", "subject": "inferred subject line", "topic": "what the message is about", "date": "any date/time mentioned", "body_hints": ["key points to include"] }, "reasoning": "why these providers are needed" } """


class GeminiService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._client: genai.Client | None = None
        if settings.gemini_api_key:
            self._client = genai.Client(api_key=settings.gemini_api_key)

    async def analyze_intent(self, text: str) -> dict[str, Any]:
        if not self._settings.gemini_api_key or self._client is None:
            logger.warning(
                "gemini_config_missing",
                service=_SERVICE,
                operation="analyze_intent",
                reason="GEMINI_API_KEY not set or client not initialized",
            )
            return {
                "intent": "unknown",
                "required_providers": [],
                "confidence": 0.0,
                "entities": {},
                "reasoning": "GEMINI_API_KEY not configured",
            }
        prompt = f"{INTENT_SYSTEM}\n\nUser said:\n{text}\n"
        try:
            resp = await self._client.aio.models.generate_content(
                model=self._settings.gemini_model,
                contents=prompt,
            )
            raw = (resp.text or "").strip()
            return self._parse_json_response(raw)
        except Exception as e:
            logger.error(
                "gemini_analyze_intent_failed",
                service=_SERVICE,
                operation="analyze_intent",
                model=self._settings.gemini_model,
                **err_ctx(e),
                exc_info=True,
            )
            return {
                "intent": "unknown",
                "required_providers": [],
                "confidence": 0.0,
                "entities": {},
                "reasoning": str(e),
            }

    def _parse_json_response(self, raw: str) -> dict[str, Any]:
        raw = raw.strip()
        fence = re.search(r"```(?:json)?\s*([\s\S]*?)```", raw)
        if fence:
            raw = fence.group(1).strip()
        try:
            return json.loads(raw)
        except json.JSONDecodeError as e:
            logger.error(
                "gemini_intent_json_parse_failed",
                service=_SERVICE,
                operation="parse_intent_json",
                raw_preview=raw[:400],
                **err_ctx(e),
                exc_info=True,
            )
            return {
                "intent": "unknown",
                "required_providers": [],
                "confidence": 0.0,
                "entities": {},
                "reasoning": f"Model returned invalid JSON: {e}",
            }

    async def draft_full_text(
        self,
        *,
        user_text: str,
        intent: str,
        context_snippets: dict[str, Any],
    ) -> str:
        system = (
            "You are Actra, a concise voice assistant. Reply in plain text only, "
            "no markdown fences. Help the user with their request."
        )
        prompt = f"{system}\n\nContext: {context_snippets}\n\nUser request: {user_text}\nIntent: {intent}\n"
        if not self._settings.gemini_api_key or self._client is None:
            logger.warning(
                "gemini_config_missing",
                service=_SERVICE,
                operation="draft_full_text",
                reason="GEMINI_API_KEY not set",
            )
            return "Actra needs GEMINI_API_KEY configured on the server to draft responses."
        try:
            resp = await self._client.aio.models.generate_content(
                model=self._settings.gemini_model,
                contents=prompt,
            )
            return (resp.text or "").strip()
        except Exception as e:
            logger.error(
                "gemini_draft_full_text_failed",
                service=_SERVICE,
                operation="draft_full_text",
                model=self._settings.gemini_model,
                **err_ctx(e),
                exc_info=True,
            )
            return f"I hit an error while drafting: {e}"

    async def emit_stream_chunks(
        self,
        full_text: str,
        on_chunk: Callable[[str], Awaitable[None]],
    ) -> None:
        """Emit agent_stream chunk deltas (whitespace-separated words)."""
        try:
            words = full_text.split()
            if not words:
                await on_chunk("")
                return
            for w in words:
                await on_chunk(w + " ")
        except Exception as e:
            logger.error(
                "gemini_emit_stream_failed",
                service=_SERVICE,
                operation="emit_stream_chunks",
                **err_ctx(e),
                exc_info=True,
            )
            raise
