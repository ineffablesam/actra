from __future__ import annotations

from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

import structlog

from src.core.connection_manager import ConnectionManager
from src.core.session_manager import SessionManager
from src.models.events import ActionResultEvent, ErrorEvent
from src.services.gmail_service import GmailService
from src.services.token_vault_service import TokenVaultService
from src.utils.service_log import err_ctx

logger = structlog.get_logger(__name__)


class ActionHandler:
    def __init__(
        self,
        *,
        connections: ConnectionManager,
        sessions: SessionManager,
        token_vault: TokenVaultService,
        gmail: GmailService,
    ) -> None:
        self._connections = connections
        self._sessions = sessions
        self._token_vault = token_vault
        self._gmail = gmail

    async def _send(self, session_id: str, payload: dict) -> None:
        await self._connections.send_json(session_id, payload)

    async def handle_confirmed(
        self,
        session_id: str,
        user_id: str,
        action_id: str,
        *,
        confirmed: bool,
        edited_payload: dict | None = None,
    ) -> None:
        if not confirmed:
            await self._send(
                session_id,
                ActionResultEvent(
                    session_id=session_id,
                    action_id=action_id,
                    success=False,
                    message="Action cancelled.",
                ).model_dump(),
            )
            return

        refresh = await self._sessions.get_refresh_token(session_id)
        if not refresh:
            await self._send(
                session_id,
                ErrorEvent(
                    session_id=session_id,
                    code="AUTH_REQUIRED",
                    message="Missing refresh token for sending.",
                    recoverable=True,
                ).model_dump(),
            )
            return

        try:
            access = await self._token_vault.get_access_token(
                user_id,
                "google_gmail",
                refresh_token=refresh,
            )
        except Exception as e:
            logger.error(
                "action_gmail_token_failed",
                service="token_vault",
                operation="get_access_token",
                **err_ctx(e),
                exc_info=True,
            )
            await self._send(
                session_id,
                ErrorEvent(
                    session_id=session_id,
                    code="TOKEN_VAULT_ERROR",
                    message="Could not retrieve Gmail token",
                    recoverable=True,
                ).model_dump(),
            )
            return

        payload = edited_payload or {}
        to_addr = str(payload.get("to", ""))
        subject = str(payload.get("subject", ""))
        body = str(payload.get("body", ""))

        msg = MIMEMultipart()
        msg["to"] = to_addr
        msg["subject"] = subject
        msg.attach(MIMEText(body, "plain"))
        raw = msg.as_string()

        try:
            await self._gmail.send_message(access, raw)
            await self._send(
                session_id,
                ActionResultEvent(
                    session_id=session_id,
                    action_id=action_id,
                    success=True,
                    message="Email sent successfully!",
                ).model_dump(),
            )
        except Exception as e:
            logger.error(
                "action_gmail_send_failed",
                service="google_gmail",
                operation="send_message",
                **err_ctx(e),
                exc_info=True,
            )
            await self._send(
                session_id,
                ActionResultEvent(
                    session_id=session_id,
                    action_id=action_id,
                    success=False,
                    message=f"Send failed: {e}",
                ).model_dump(),
            )
