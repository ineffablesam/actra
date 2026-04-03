from __future__ import annotations

import asyncio
import base64
import uuid
from typing import Any

import structlog

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
from src.services.token_vault_service import TokenVaultService
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
    ) -> None:
        self._connections = connections
        self._sessions = sessions
        self._gemini = gemini
        self._token_vault = token_vault
        self._cartesia = cartesia
        self._gmail = gmail
        self._calendar = calendar

    async def _send(self, session_id: str, payload: dict[str, Any]) -> None:
        await self._connections.send_json(session_id, payload)

    async def handle_transcript(self, session_id: str, user_id: str, text: str) -> None:
        log = logger.bind(session_id=session_id, user_id=user_id)
        await self._send(
            session_id,
            AgentThinkingEvent(
                session_id=session_id,
                message="Let me figure out what I need for this...",
            ).model_dump(),
        )

        analysis = await self._gemini.analyze_intent(text)
        intent = str(analysis.get("intent", "unknown"))
        required = list(analysis.get("required_providers", []))
        entities = dict(analysis.get("entities", {}))
        reasoning = str(analysis.get("reasoning", ""))

        log.info(
            "intent_analyzed",
            intent=intent,
            required_providers=required,
            confidence=analysis.get("confidence"),
        )

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
            refresh = await self._sessions.get_refresh_token(session_id)
            if not refresh:
                log.warning(
                    "auth_required_no_refresh_token",
                    hint="Client must send session_auth event with Auth0 refresh_token after WS connect.",
                )
                await self._send(
                    session_id,
                    ErrorEvent(
                        session_id=session_id,
                        code="AUTH_REQUIRED",
                        message="Send session_auth with a refresh token so the server can reach Google APIs.",
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
                        refresh_token=refresh,
                    )
                    if provider == "google_calendar":
                        events = await self._calendar.list_next_events(tok, max_results=3)
                        context_snippets["calendar"] = events
                    if provider == "google_gmail":
                        context_snippets["gmail"] = "ready"
                except Exception as e:
                    log.error(
                        "context_fetch_failed",
                        service=provider,
                        operation="token_exchange_or_google_fetch",
                        **err_ctx(e),
                        exc_info=True,
                    )
                    await self._send(
                        session_id,
                        ErrorEvent(
                            session_id=session_id,
                            code="TOKEN_VAULT_ERROR",
                            message="Could not retrieve Google access token. Reconnect your account.",
                            recoverable=True,
                        ).model_dump(),
                    )
                    return
            log.info("google_context_ready", keys=list(context_snippets.keys()))

        full = await self._gemini.draft_full_text(
            user_text=text,
            intent=intent,
            context_snippets=context_snippets,
        )

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
            self._gemini.emit_stream_chunks(full, emit_agent),
            self._cartesia.stream_tts(full, session_id, on_audio),
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

    async def resume_after_connections(self, session_id: str, user_id: str) -> None:
        pending = await self._sessions.get_pending_task(session_id)
        if not pending:
            return
        await self._sessions.clear_pending_task(session_id)
        await self.handle_transcript(session_id, user_id, pending.original_text)
