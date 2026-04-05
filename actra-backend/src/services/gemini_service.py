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

INTENT_SYSTEM = """ You are Actra, a voice AI assistant. Analyze the user's request and return ONLY valid JSON with this exact schema - no markdown, no explanation, JSON only:
{ "intent": "send_email" | "create_event" | "read_emails" | "check_calendar" | "slack_workspace" | "unknown" | "unsupported",
  "required_providers": ["google_gmail", "google_calendar", "slack"],
  "confidence": 0.0-1.0,
  "entities": { "to": "person name or email if mentioned", "subject": "inferred subject line", "topic": "what the message is about", "date": "any date/time mentioned", "body_hints": ["key points to include"], "channel": "Slack channel name if mentioned" },
  "reasoning": "why these providers are needed, or why the request is out of scope",
  "user_message": "when intent is unsupported: one short friendly sentence the user will hear"
}

Hard rules:
- Actra integrations: google_gmail (email), google_calendar (calendar), slack (Slack workspace — channels, team context via Token Vault).
- Any request to read, list, summarize, or identify the latest or recent email (inbox, unread, "who wrote", "last message") MUST use intent "read_emails" and include "google_gmail" in required_providers.
- Requests about Slack: listing channels, what's in Slack, team/workspace, messages in a channel, posting to Slack, or "check Slack" MUST use intent "slack_workspace" and include "slack" in required_providers.
- In required_providers, use ONLY these exact strings when needed: "google_gmail", "google_calendar", "slack". Never invent other provider IDs.
- If the user asks for anything that needs another app or service not listed above (examples: Teams-only, Google Drive-only, Photos, Spotify, banking, generic web search, SMS, WhatsApp, Notion, Jira), set intent to "unsupported", required_providers to [], and put a warm, concise user_message explaining limits and one example of what they can ask instead.
- If the request is vague or chit-chat with no Google or Slack data needed, use intent "unknown" and required_providers []. """


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
                "user_message": "",
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
                "user_message": "",
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
                "user_message": "",
            }

    async def unsupported_capability_reply(
        self,
        *,
        user_text: str,
        reasoning: str | None,
        invalid_providers: list[str] | None,
    ) -> str:
        """Spoken reply when the user asks for capabilities outside Gmail/Calendar."""
        system = (
            "You are Actra, a concise voice assistant. Reply in plain text only, no markdown. "
            "The user asked for something you cannot do: Actra integrates Gmail, Google Calendar, and Slack. "
            "Be warm, brief (2-4 sentences). Acknowledge their request, explain the limit, "
            "and suggest something you can do (email, calendar, Slack, drafts)."
        )
        parts = [f"User said: {user_text}"]
        if reasoning:
            parts.append(f"Analysis: {reasoning}")
        if invalid_providers:
            parts.append(f"Invalid or unavailable integrations mentioned: {', '.join(invalid_providers)}")
        prompt = f"{system}\n\n" + "\n".join(parts)
        if not self._settings.gemini_api_key or self._client is None:
            return (
                "I can help with Gmail, Google Calendar, and Slack — things like email, your schedule, "
                "or your workspace. Ask me about mail, calendar, or Slack anytime."
            )
        try:
            resp = await self._client.aio.models.generate_content(
                model=self._settings.gemini_model,
                contents=prompt,
            )
            return (resp.text or "").strip()
        except Exception as e:
            logger.error(
                "gemini_unsupported_reply_failed",
                service=_SERVICE,
                operation="unsupported_capability_reply",
                model=self._settings.gemini_model,
                **err_ctx(e),
                exc_info=True,
            )
            return (
                "I can connect to Gmail, Google Calendar, and Slack. "
                "Try asking me to send an email, check your calendar, or something about Slack."
            )

    async def draft_full_text(
        self,
        *,
        user_text: str,
        intent: str,
        context_snippets: dict[str, Any],
        memory_context: str | None = None,
    ) -> str:
        system = (
            "You are Actra, a natural voice assistant. Reply in plain text only, no markdown. "
            "Sound human: warm, clear, and direct — never robotic or like a status message. "
            "When Context includes gmail (a list of messages with from, subject, date, snippet), "
            "use it to answer. For 'latest' or 'last' email with no specific search, use the first "
            "item (newest first). Mention sender and subject; summarize the snippet in your own words. "
            "Do not say you are retrieving, loading, or checking — you already have the data. "
            "If gmail is an empty list but gmail_search_note is present, follow that note: "
            "do not say there is no email from that sender everywhere — only that this search "
            "did not match; suggest Promotions, Updates, or Spam, or different wording. "
            "If the list is empty and there is no gmail_search_note, say the inbox looks empty. "
            "When Context includes calendar events, summarize them helpfully. "
            "When Context includes slack (team name, user, sample channel names), use it briefly; "
            "do not invent channels or messages not shown."
        )
        parts: list[str] = [system]
        if memory_context:
            parts.append(memory_context)
        parts.append(f"\n\nContext: {context_snippets}\n\nUser request: {user_text}\nIntent: {intent}\n")
        prompt = "\n".join(parts)
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
