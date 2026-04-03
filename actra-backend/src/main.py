from __future__ import annotations

import asyncio
import json
import logging
import sys
from typing import Any

import structlog
import websockets
from websockets import ServerConnection

from src.config import get_settings
from src.core.connection_manager import ConnectionManager
from src.core.session_manager import SessionManager
from src.handlers.action_handler import ActionHandler
from src.handlers.connection_handler import ConnectionHandler
from src.handlers.transcript_handler import TranscriptHandler
from src.models.events import ActionEditedEvent, SessionAuthEvent, parse_client_event
from src.services.calendar_service import CalendarService
from src.services.cartesia_service import CartesiaService
from src.services.gemini_service import GeminiService
from src.services.gmail_service import GmailService
from src.services.token_vault_service import TokenVaultService
from src.utils.redis_client import RedisStore
from src.utils.service_log import err_ctx


def configure_logging() -> None:
    structlog.configure(
        processors=[
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
        context_class=dict,
        logger_factory=structlog.PrintLoggerFactory(file=sys.stdout),
    )


log = structlog.get_logger(__name__)


class App:
    def __init__(self) -> None:
        self.settings = get_settings()
        self.redis = RedisStore(self.settings)
        self.connections = ConnectionManager()
        self.sessions = SessionManager(self.redis)
        self.gemini = GeminiService(self.settings)
        self.token_vault = TokenVaultService(self.settings, self.redis)
        self.cartesia = CartesiaService(self.settings)
        self.gmail = GmailService()
        self.calendar = CalendarService()
        self.transcript_handler = TranscriptHandler(
            connections=self.connections,
            sessions=self.sessions,
            gemini=self.gemini,
            token_vault=self.token_vault,
            cartesia=self.cartesia,
            gmail=self.gmail,
            calendar=self.calendar,
        )
        self.connection_handler = ConnectionHandler(
            sessions=self.sessions,
            transcript_handler=self.transcript_handler,
        )
        self.action_handler = ActionHandler(
            connections=self.connections,
            sessions=self.sessions,
            token_vault=self.token_vault,
            gmail=self.gmail,
        )

    async def process_message(self, ws: ServerConnection, data: dict[str, Any]) -> None:
        event = data.get("event")
        session_id = str(data.get("session_id", ""))
        user_id = str(data.get("user_id", ""))
        peer = getattr(ws, "remote_address", None)

        log.info(
            "ws_message",
            ws_event=event,
            session_id=session_id or None,
            user_id=user_id or None,
            client_peer=str(peer) if peer is not None else None,
        )

        if session_id:
            await self.connections.register(session_id, ws)

        if event == "session_auth":
            ev = SessionAuthEvent.model_validate(data)
            log.info(
                "session_auth_received",
                session_id=ev.session_id,
                user_id=ev.user_id,
                refresh_token_chars=len(ev.refresh_token),
            )
            await self.sessions.set_refresh_token(ev.session_id, ev.refresh_token)
            return

        if event == "transcript_received":
            ev = parse_client_event(data)
            if hasattr(ev, "text"):
                text_preview = (ev.text[:120] + "…") if len(ev.text) > 120 else ev.text
                log.info("transcript_received", text_len=len(ev.text), text_preview=text_preview)
                await self.transcript_handler.handle_transcript(session_id, user_id, ev.text)
            return

        if event == "account_connected":
            ev = parse_client_event(data)
            log.info("account_connected_event", provider=ev.provider)
            await self.connection_handler.on_account_connected(session_id, user_id, ev.provider)
            return

        if event == "action_confirmed":
            ev = parse_client_event(data)
            log.info("action_confirmed_event", action_id=ev.action_id, confirmed=ev.confirmed)
            await self.action_handler.handle_confirmed(
                session_id,
                user_id,
                ev.action_id,
                confirmed=ev.confirmed,
            )
            return

        if event == "action_edited":
            ev = ActionEditedEvent.model_validate(data)
            uid = ev.user_id or user_id
            log.info("action_edited_event", action_id=ev.action_id)
            await self.action_handler.handle_confirmed(
                session_id,
                uid,
                ev.action_id,
                confirmed=True,
                edited_payload=ev.edited_payload,
            )
            return

    async def ws_handler(self, ws: ServerConnection) -> None:
        try:
            async for message in ws:
                if isinstance(message, bytes):
                    continue
                try:
                    data = json.loads(message)
                except json.JSONDecodeError as e:
                    peer = getattr(ws, "remote_address", None)
                    log.warning(
                        "ws_message_invalid_json",
                        client_peer=str(peer) if peer is not None else None,
                        **err_ctx(e),
                    )
                    continue
                try:
                    await self.process_message(ws, data)
                except Exception as e:
                    log.error(
                        "handler_error",
                        ws_event=data.get("event"),
                        session_id=data.get("session_id") or None,
                        **err_ctx(e),
                        exc_info=True,
                    )
        finally:
            pass


async def run() -> None:
    configure_logging()
    app = App()
    await app.redis.connect()
    host = app.settings.ws_host
    port = app.settings.ws_port
    async with websockets.serve(app.ws_handler, host, port):
        structlog.get_logger(__name__).info("ws_listening", host=host, port=port)
        await asyncio.Future()


def main() -> None:
    asyncio.run(run())


if __name__ == "__main__":
    main()
