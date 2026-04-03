from unittest.mock import AsyncMock, MagicMock

import pytest

from src.handlers.transcript_handler import TranscriptHandler
from src.services.calendar_service import CalendarService
from src.services.cartesia_service import CartesiaService
from src.services.gemini_service import GeminiService
from src.services.gmail_service import GmailService
from src.services.token_vault_service import TokenVaultService


@pytest.mark.asyncio
async def test_handle_transcript_missing_connections():
    connections = MagicMock()
    connections.send_json = AsyncMock()
    sessions = MagicMock()
    sessions.get_user_connected_providers = AsyncMock(return_value=[])
    sessions.set_pending_task = AsyncMock()
    gemini = MagicMock()
    gemini.analyze_intent = AsyncMock(
        return_value={
            "intent": "send_email",
            "required_providers": ["google_gmail"],
            "entities": {},
            "reasoning": "need gmail",
        }
    )
    tv = MagicMock(spec=TokenVaultService)
    cartesia = MagicMock(spec=CartesiaService)
    gmail = MagicMock(spec=GmailService)
    cal = MagicMock(spec=CalendarService)

    h = TranscriptHandler(
        connections=connections,
        sessions=sessions,
        gemini=gemini,
        token_vault=tv,
        cartesia=cartesia,
        gmail=gmail,
        calendar=cal,
    )

    await h.handle_transcript("sid", "uid", "email sam")

    sessions.set_pending_task.assert_called_once()
    assert connections.send_json.await_count >= 2
