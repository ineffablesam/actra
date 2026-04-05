from __future__ import annotations

import asyncio
import base64
import uuid
from typing import Any

import structlog

from src.config import Settings
from src.constants import SUPPORTED_PROVIDERS
from src.core.connection_manager import ConnectionManager
from src.core.session_manager import SessionManager
from src.models.events import (
    ActionResultEvent,
    AgentStreamEvent,
    AgentThinkingEvent,
    ConnectionsRequiredEvent,
    DraftReadyEvent,
    ErrorEvent,
    TtsAudioChunkEvent,
)
from src.models.tasks import PendingTask
from src.services.cartesia_service import CartesiaService
from src.services.gemini_service import GeminiService
from src.services.calendar_service import CalendarService
from src.services.gmail_service import GmailService
from src.services.slack_service import SlackService
from src.services.token_vault_service import TokenVaultExchangeError, TokenVaultService
from src.memory.retrieval import retrieve_context_bundle
from src.memory.service import MemoryService
from src.utils.service_log import err_ctx

logger = structlog.get_logger(__name__)


class TranscriptHandler:
    def __init__(
        self,
        *,
        connections: ConnectionManager,
        sessions: SessionManager,
        gemini: GeminiService,
        token_vault: TokenVaultService,
        cartesia: CartesiaService,
        gmail: GmailService,
        calendar: CalendarService,
        slack: SlackService,
        settings: Settings,
        memory: MemoryService | None = None,
    ) -> None:
        self._connections = connections
        self._sessions = sessions
        self._gemini = gemini
        self._token_vault = token_vault
        self._cartesia = cartesia
        self._gmail = gmail
        self._calendar = calendar
        self._slack = slack
        self._settings = settings
        self._memory = memory

    async def _send(self, session_id: str, payload: dict[str, Any]) -> None:
        await self._connections.send_json(session_id, payload)

    async def _finalize_memory_turn(
        self,
        *,
        user_id: str,
        user_text: str,
        intent: str,
        assistant_text: str | None,
    ) -> None:
        """Append assistant turn to short-term buffer and optionally persist the user message."""
        if not self._memory:
            return
        if assistant_text:
            await self._memory.short_term.append(user_id, "assistant", assistant_text.strip())
        await self._memory.maybe_persist_user_turn(
            user_id,
            user_text,
            metadata={"intent": intent},
        )

    async def handle_transcript(self, session_id: str, user_id: str, text: str) -> None:
        log = logger.bind(session_id=session_id, user_id=user_id)
        await self._send(
            session_id,
            AgentThinkingEvent(
                session_id=session_id,
                message="Let me figure out what I need for this...",
            ).model_dump(),
        )

        memory_block: str | None = None
        if self._memory:
            await self._memory.short_term.append(user_id, "user", text)
            # Run intent analysis and memory retrieval in parallel (both only need ``text``).
            analysis, mem_tuple = await asyncio.gather(
                self._gemini.analyze_intent(text),
                retrieve_context_bundle(
                    user_id=user_id,
                    user_input=text,
                    short_term=self._memory.short_term,
                    long_term=self._memory.long_term,
                    settings=self._settings,
                ),
            )
            _, _, memory_block = mem_tuple
        else:
            analysis = await self._gemini.analyze_intent(text)
        intent = str(analysis.get("intent", "unknown"))
        raw_required = list(analysis.get("required_providers", []))
        required = [p for p in raw_required if p in SUPPORTED_PROVIDERS]
        unsupported_req = [p for p in raw_required if p not in SUPPORTED_PROVIDERS]
        entities = dict(analysis.get("entities", {}))
        reasoning = str(analysis.get("reasoning", ""))
        user_message = str(analysis.get("user_message", "")).strip()

        log.info(
            "intent_analyzed",
            intent=intent,
            required_providers=required,
            raw_required_providers=raw_required,
            unsupported_req=unsupported_req,
            confidence=analysis.get("confidence"),
        )

        is_unsupported_intent = intent in ("unsupported", "not_supported")
        if is_unsupported_intent or unsupported_req:
            log.info(
                "unsupported_capability",
                is_unsupported_intent=is_unsupported_intent,
                unsupported_req=unsupported_req,
            )
            if is_unsupported_intent and user_message:
                full_reply = user_message
            else:
                full_reply = await self._gemini.unsupported_capability_reply(
                    user_text=text,
                    reasoning=reasoning or None,
                    invalid_providers=unsupported_req or None,
                )
            await self._stream_agent_response(session_id, full_reply, log)
            await self._finalize_memory_turn(
                user_id=user_id,
                user_text=text,
                intent=intent,
                assistant_text=full_reply,
            )
            return

        connected = await self._sessions.get_user_connected_providers(user_id) or []
        missing = [p for p in required if p not in connected]

        log.info(
            "provider_check",
            connected_cached=connected,
            missing=missing,
        )

        if missing:
            task = PendingTask(
                user_id=user_id,
                session_id=session_id,
                original_text=text,
                intent=intent,
                required_providers=required,
                entities=entities,
                reasoning=reasoning,
            )
            await self._sessions.set_pending_task(session_id, task)
            log.info(
                "connections_required_sent",
                missing=missing,
                task_context=intent,
            )
            await self._send(
                session_id,
                ConnectionsRequiredEvent(
                    session_id=session_id,
                    providers=missing,
                    reason=reasoning or "Connect the requested accounts to continue.",
                    task_context=intent,
                ).model_dump(),
            )
            await self._finalize_memory_turn(
                user_id=user_id,
                user_text=text,
                intent=intent,
                assistant_text=None,
            )
            return

        # Greetings and other turns that need no Google data: draft with Gemini (+ TTS) only.
        if not required:
            log.info(
                "transcript_pipeline_start",
                providers_to_fetch=[],
                skip_google_auth=True,
            )
            context_snippets: dict[str, Any] = {}
        else:
            auth0_at = await self._sessions.get_auth0_access_token(session_id)
            if not auth0_at:
                log.warning(
                    "auth_required_no_access_token",
                    hint="Client must send session_auth with Auth0 access_token (API audience) after WS connect.",
                )
                await self._send(
                    session_id,
                    ErrorEvent(
                        session_id=session_id,
                        code="AUTH_REQUIRED",
                        message="Send session_auth with an access token (for your API audience) so the server can reach Google or Slack APIs.",
                        recoverable=True,
                    ).model_dump(),
                )
                return

            log.info("transcript_pipeline_start", providers_to_fetch=required)

            context_snippets = {}
            for provider in required:
                try:
                    tok = await self._token_vault.get_access_token(
                        user_id,
                        provider,
                        auth0_access_token=auth0_at,
                    )
                    if provider == "google_calendar":
                        events = await self._calendar.list_next_events(tok, max_results=3)
                        context_snippets["calendar"] = events
                    if provider == "slack":
                        slack_ctx = await self._slack.fetch_workspace_context(tok)
                        context_snippets["slack"] = slack_ctx
                    if provider == "google_gmail":
                        if intent == "read_emails":
                            rows = await self._gmail.fetch_inbox_summary(
                                tok,
                                max_results=10,
                                user_query=text,
                            )
                            context_snippets["gmail"] = rows
                            if not rows:
                                context_snippets["gmail_search_note"] = (
                                    "Gmail search returned zero messages for this query. "
                                    "Do not claim the user has no mail in general. Say no matches "
                                    "for this search; sender names may differ (e.g. bank codes), "
                                    "or the message may be under Promotions, Updates, or Spam."
                                )
                        else:
                            context_snippets["gmail"] = {
                                "connected": True,
                                "intent": intent,
                            }
                except TokenVaultExchangeError as e:
                    log.error(
                        "context_fetch_failed",
                        service=provider,
                        operation="token_exchange_or_provider_fetch",
                        auth0_hint=e.auth0_hint[:200] if e.auth0_hint else None,
                        **err_ctx(e),
                        exc_info=True,
                    )
                    msg = (
                        e.client_message
                        if e.client_message
                        else "Could not retrieve access token for this connection. Reconnect your account."
                    )
                    code = e.ws_error_code
                    await self._send(
                        session_id,
                        ErrorEvent(
                            session_id=session_id,
                            code=code,
                            message=msg,
                            recoverable=True,
                        ).model_dump(),
                    )
                    return
                except Exception as e:
                    log.error(
                        "context_fetch_failed",
                        service=provider,
                        operation="token_exchange_or_provider_fetch",
                        **err_ctx(e),
                        exc_info=True,
                    )
                    await self._send(
                        session_id,
                        ErrorEvent(
                            session_id=session_id,
                            code="TOKEN_VAULT_ERROR",
                            message="Could not retrieve access token for this connection. Reconnect your account.",
                            recoverable=True,
                        ).model_dump(),
                    )
                    return
            log.info("provider_context_ready", keys=list(context_snippets.keys()))

        full = await self._gemini.draft_full_text(
            user_text=text,
            intent=intent,
            context_snippets=context_snippets,
            memory_context=memory_block,
        )

        await self._stream_agent_response(session_id, full, log)
        await self._finalize_memory_turn(
            user_id=user_id,
            user_text=text,
            intent=intent,
            assistant_text=full,
        )

        if intent == "send_email":
            action_id = str(uuid.uuid4())
            to_addr = str(entities.get("to", "recipient@example.com"))
            if "@" not in to_addr:
                to_addr = f"{to_addr}@example.com"
            subj = str(entities.get("subject", "Message from Actra"))
            body = full
            draft = await self._gmail.draft_send_preview(
                "",
                to_email=to_addr,
                subject=subj,
                body=body,
            )
            await self._send(
                session_id,
                DraftReadyEvent(
                    session_id=session_id,
                    action_id=action_id,
                    type="email",
                    payload=draft,
                ).model_dump(),
            )

    async def _stream_agent_response(self, session_id: str, full_text: str, log: Any) -> None:
        async def emit_agent(chunk: str) -> None:
            await self._send(
                session_id,
                AgentStreamEvent(session_id=session_id, chunk=chunk, done=False).model_dump(),
            )

        async def on_audio(b: bytes) -> None:
            await self._send(
                session_id,
                TtsAudioChunkEvent(
                    session_id=session_id,
                    audio_base64=base64.b64encode(b).decode("ascii"),
                    sample_rate=44100,
                    done=False,
                ).model_dump(),
            )

        parallel = await asyncio.gather(
            self._gemini.emit_stream_chunks(full_text, emit_agent),
            self._cartesia.stream_tts(full_text, session_id, on_audio),
            return_exceptions=True,
        )
        gemini_result, cartesia_result = parallel
        gemini_failed = isinstance(gemini_result, BaseException)
        cartesia_failed = isinstance(cartesia_result, BaseException)

        if gemini_failed:
            r = gemini_result
            assert isinstance(r, BaseException)
            log.error(
                "transcript_parallel_task_failed",
                service="gemini",
                operation="emit_stream_chunks",
                **err_ctx(r),
                exc_info=(type(r), r, r.__traceback__),
            )
        if cartesia_failed:
            r = cartesia_result
            assert isinstance(r, BaseException)
            log.error(
                "transcript_parallel_task_failed",
                service="cartesia",
                operation="stream_tts",
                **err_ctx(r),
                exc_info=(type(r), r, r.__traceback__),
            )

        if gemini_failed:
            await self._send(
                session_id,
                ErrorEvent(
                    session_id=session_id,
                    code="PIPELINE_ERROR",
                    message=f"Agent stream failed: {gemini_result}",
                    recoverable=True,
                ).model_dump(),
            )
        elif cartesia_failed:
            await self._send(
                session_id,
                ErrorEvent(
                    session_id=session_id,
                    code="TTS_UNAVAILABLE",
                    message=f"Reply text is ready but speech failed: {cartesia_result}",
                    recoverable=True,
                ).model_dump(),
            )

        await self._send(
            session_id,
            AgentStreamEvent(session_id=session_id, chunk="", done=True).model_dump(),
        )
        await self._send(
            session_id,
            TtsAudioChunkEvent(
                session_id=session_id,
                audio_base64="",
                sample_rate=44100,
                done=True,
            ).model_dump(),
        )

    async def resume_after_connections(self, session_id: str, user_id: str) -> None:
        pending = await self._sessions.get_pending_task(session_id)
        if not pending:
            return
        await self._sessions.clear_pending_task(session_id)
        await self.handle_transcript(session_id, user_id, pending.original_text)
