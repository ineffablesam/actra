from __future__ import annotations

import asyncio
import json
import logging
import sys
from typing import Any

import asyncpg
import structlog
import uvicorn
import websockets
from websockets import ServerConnection
from websockets.exceptions import ConnectionClosedError

from src.api.app import create_http_app
from src.config import get_settings
from src.core.connection_manager import ConnectionManager
from src.core.session_manager import SessionManager
from src.db.postgres import close_pool, create_pool, init_schema
from src.handlers.action_handler import ActionHandler
from src.handlers.connection_handler import ConnectionHandler
from src.handlers.transcript_handler import TranscriptHandler
from src.memory.service import MemoryService
from src.models.events import (
    ActionEditedEvent,
    ErrorEvent,
    SessionAuthEvent,
    SessionLogoutEvent,
    parse_client_event,
)
from src.repos.users_repo import UsersRepository
from src.services.auth0_jwt_service import Auth0JwtService
from src.services.calendar_service import CalendarService
from src.services.cartesia_service import CartesiaService
from src.services.gemini_service import GeminiService
from src.services.gmail_service import GmailService
from src.services.slack_service import SlackService
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
    def __init__(self, *, pg_pool: asyncpg.Pool | None = None) -> None:
        self.settings = get_settings()
        self.pg_pool = pg_pool
        self.redis = RedisStore(self.settings)
        self.memory = MemoryService(self.settings, self.redis, pg_pool)
        self.connections = ConnectionManager()
        self.sessions = SessionManager(self.redis)
        self.users_repo = UsersRepository(pg_pool) if pg_pool is not None else None
        self.auth0_jwt = Auth0JwtService(self.settings)
        self.gemini = GeminiService(self.settings)
        self.token_vault = TokenVaultService(self.settings, self.redis)
        self.cartesia = CartesiaService(self.settings)
        self.gmail = GmailService()
        self.calendar = CalendarService()
        self.slack = SlackService()
        self.transcript_handler = TranscriptHandler(
            connections=self.connections,
            sessions=self.sessions,
            gemini=self.gemini,
            token_vault=self.token_vault,
            cartesia=self.cartesia,
            gmail=self.gmail,
            calendar=self.calendar,
            slack=self.slack,
            settings=self.settings,
            memory=self.memory,
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

    async def _send_ws_error(self, session_id: str, code: str, message: str) -> None:
        if not session_id:
            return
        await self.connections.send_json(
            session_id,
            ErrorEvent(session_id=session_id, code=code, message=message).model_dump(),
        )

    async def _require_verified_user(self, session_id: str, user_id: str) -> bool:
        ok = await self.sessions.verify_session_user(session_id, user_id)
        if not ok:
            await self._send_ws_error(
                session_id,
                "UNAUTHENTICATED",
                "Send session_auth first; user_id must match the authenticated session.",
            )
        return ok

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
            s = self.settings
            effective_sub: str

            if s.require_auth0_jwt:
                raw = (ev.access_token or "").strip()
                if not raw:
                    await self._send_ws_error(
                        ev.session_id,
                        "AUTH_REQUIRED",
                        "session_auth must include access_token.",
                    )
                    return
                try:
                    claims = self.auth0_jwt.verify_access_token(raw)
                except Exception as e:
                    log.warning("session_auth_jwt_invalid", **err_ctx(e), exc_info=True)
                    await self._send_ws_error(
                        ev.session_id,
                        "INVALID_TOKEN",
                        "Invalid or expired access token.",
                    )
                    return
                sub = str(claims.get("sub", "")).strip()
                if not sub:
                    await self._send_ws_error(ev.session_id, "INVALID_TOKEN", "Token missing sub claim.")
                    return
                if ev.user_id and ev.user_id != sub:
                    log.warning(
                        "session_auth_user_id_mismatch",
                        client_user_id=ev.user_id,
                        token_sub=sub,
                    )
                effective_sub = sub
                email = claims.get("email") if isinstance(claims.get("email"), str) else None
                if self.users_repo is not None:
                    await self.users_repo.upsert_from_claims(auth0_sub=sub, email=email)
                await self.sessions.set_verified_sub(ev.session_id, effective_sub)
                await self.sessions.set_auth0_access_token(ev.session_id, raw)
            else:
                effective_sub = (ev.user_id or "").strip()
                if not effective_sub:
                    await self._send_ws_error(
                        ev.session_id,
                        "AUTH_REQUIRED",
                        "user_id is required when REQUIRE_AUTH0_JWT is false.",
                    )
                    return
                await self.sessions.set_verified_sub(ev.session_id, effective_sub)
                at = (ev.access_token or "").strip()
                if at:
                    await self.sessions.set_auth0_access_token(ev.session_id, at)

            if ev.refresh_token:
                await self.sessions.set_refresh_token(ev.session_id, ev.refresh_token)
            log.info(
                "session_auth_received",
                session_id=ev.session_id,
                user_id=effective_sub,
                refresh_token_chars=len(ev.refresh_token or ""),
                access_token_chars=len((ev.access_token or "").strip()),
            )
            return

        if event == "session_logout":
            ev = SessionLogoutEvent.model_validate(data)
            if not await self._require_verified_user(ev.session_id, user_id):
                return
            await self.sessions.clear_session(ev.session_id)
            await self.sessions.invalidate_user_providers(user_id)
            await self.token_vault.clear_cached_access_tokens(user_id)
            await self.connections.unregister(ev.session_id)
            log.info("session_logout", session_id=ev.session_id, user_id=user_id)
            return

        if event == "transcript_received":
            if not await self._require_verified_user(session_id, user_id):
                return
            ev = parse_client_event(data)
            if hasattr(ev, "text"):
                text_preview = (ev.text[:120] + "…") if len(ev.text) > 120 else ev.text
                log.info("transcript_received", text_len=len(ev.text), text_preview=text_preview)
                await self.transcript_handler.handle_transcript(session_id, user_id, ev.text)
            return

        if event == "account_connected":
            if not await self._require_verified_user(session_id, user_id):
                return
            ev = parse_client_event(data)
            log.info("account_connected_event", provider=ev.provider)
            await self.connection_handler.on_account_connected(session_id, user_id, ev.provider)
            return

        if event == "action_confirmed":
            if not await self._require_verified_user(session_id, user_id):
                return
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
            if not await self._require_verified_user(session_id, user_id):
                return
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
        peer = getattr(ws, "remote_address", None)
        peer_s = str(peer) if peer is not None else None
        try:
            async for message in ws:
                if isinstance(message, bytes):
                    continue
                try:
                    data = json.loads(message)
                except json.JSONDecodeError as e:
                    log.warning(
                        "ws_message_invalid_json",
                        client_peer=peer_s,
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
        except ConnectionClosedError:
            pass
        finally:
            pass


async def run() -> None:
    configure_logging()
    settings = get_settings()
    pool: asyncpg.Pool | None = None
    if settings.database_url:
        pool = await create_pool(settings)
        await init_schema(pool)
    else:
        log.warning("database_url_missing", hint="PostgreSQL user upsert disabled; set DATABASE_URL")

    app = App(pg_pool=pool)
    await app.redis.connect()
    await app.memory.warmup()

    # Use Settings (Pydantic), not raw os.getenv: .env / env vars are merged into Settings but are
    # not always exported to os.environ, so getenv("ENVIRONMENT") can stay "development" while
    # settings.environment is "production" — that would skip mounting /ws on FastAPI.
    is_production = app.settings.environment.strip().lower() == "production"

    http_app = create_http_app(
        app.memory,
        app.sessions,
        app.auth0_jwt,
        app.token_vault,
        app.settings,
        ws_handler=app.ws_handler if is_production else None,
    )
    log.info(
        "http_app_created",
        environment=app.settings.environment,
        production_mode=is_production,
        ws_on_fastapi=is_production,
        ws_standalone_port=not is_production,
    )

    uv_cfg = uvicorn.Config(
        http_app,
        host=settings.http_host,
        port=settings.http_port,
        log_level="info",
    )
    uv_server = uvicorn.Server(uv_cfg)

    if is_production:
        try:
            await uv_server.serve()
        finally:
            await app.redis.close()
            await close_pool(pool)
    else:
        async def _ws_forever() -> None:
            async with websockets.serve(app.ws_handler, settings.ws_host, settings.ws_port):
                log.info("ws_listening", host=settings.ws_host, port=settings.ws_port)
                await asyncio.Future()

        try:
            await asyncio.gather(_ws_forever(), uv_server.serve())
        finally:
            await app.redis.close()
            await close_pool(pool)


def main() -> None:
    asyncio.run(run())


if __name__ == "__main__":
    main()
