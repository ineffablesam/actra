from __future__ import annotations

import structlog

from src.core.session_manager import SessionManager
from src.handlers.transcript_handler import TranscriptHandler
from src.utils.service_log import err_ctx

logger = structlog.get_logger(__name__)


class ConnectionHandler:
    def __init__(
        self,
        *,
        sessions: SessionManager,
        transcript_handler: TranscriptHandler,
    ) -> None:
        self._sessions = sessions
        self._transcript = transcript_handler

    async def on_account_connected(self, session_id: str, user_id: str, provider: str) -> None:
        await self._sessions.add_connected_provider(user_id, provider)
        logger.info("account_connected", session_id=session_id, user_id=user_id, provider=provider)
        try:
            await self._transcript.resume_after_connections(session_id, user_id)
        except Exception as e:
            logger.error(
                "resume_after_connections_failed",
                service="transcript",
                operation="resume_after_connections",
                session_id=session_id,
                user_id=user_id,
                provider=provider,
                **err_ctx(e),
                exc_info=True,
            )
            raise
