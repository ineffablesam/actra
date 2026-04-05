from unittest.mock import AsyncMock, MagicMock

import pytest

from src.config import Settings
from src.handlers.transcript_handler import TranscriptHandler
from src.services.calendar_service import CalendarService
from src.services.cartesia_service import CartesiaService
from src.services.gemini_service import GeminiService
from src.services.gmail_service import GmailService
from src.services.slack_service import SlackService
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
    slack = MagicMock(spec=SlackService)
    settings = MagicMock(spec=Settings)
    settings.memory_short_term_context_n = 5

    h = TranscriptHandler(
        connections=connections,
        sessions=sessions,
        gemini=gemini,
        token_vault=tv,
        cartesia=cartesia,
        gmail=gmail,
        calendar=cal,
        slack=slack,
        settings=settings,
        memory=None,
    )

    await h.handle_transcript("sid", "uid", "email sam")

    sessions.set_pending_task.assert_called_once()
    assert connections.send_json.await_count >= 2


@pytest.mark.asyncio
async def test_handle_transcript_unsupported_capability():
    connections = MagicMock()
    connections.send_json = AsyncMock()
    sessions = MagicMock()
    sessions.get_user_connected_providers = AsyncMock(return_value=["google_gmail", "google_calendar"])
    gemini = MagicMock()
    gemini.analyze_intent = AsyncMock(
        return_value={
            "intent": "unsupported",
            "required_providers": [],
            "entities": {},
            "reasoning": "User asked for Slack",
            "user_message": "I only work with Gmail and Calendar right now.",
        }
    )
    gemini.emit_stream_chunks = AsyncMock()
    tv = MagicMock(spec=TokenVaultService)
    cartesia = MagicMock(spec=CartesiaService)
    cartesia.stream_tts = AsyncMock()
    gmail = MagicMock(spec=GmailService)
    cal = MagicMock(spec=CalendarService)
    slack = MagicMock(spec=SlackService)
    settings = MagicMock(spec=Settings)
    settings.memory_short_term_context_n = 5

    h = TranscriptHandler(
        connections=connections,
        sessions=sessions,
        gemini=gemini,
        token_vault=tv,
        cartesia=cartesia,
        gmail=gmail,
        calendar=cal,
        slack=slack,
        settings=settings,
        memory=None,
    )

    await h.handle_transcript("sid", "uid", "post this to Microsoft Teams")

    gemini.unsupported_capability_reply.assert_not_called()
    gemini.emit_stream_chunks.assert_called_once()
    cartesia.stream_tts.assert_called_once()
    sessions.set_pending_task.assert_not_called()


@pytest.mark.asyncio
async def test_handle_transcript_invalid_provider_id_fallback():
    """Model hallucinates an unknown provider string — treat as unsupported."""
    connections = MagicMock()
    connections.send_json = AsyncMock()
    sessions = MagicMock()
    sessions.get_user_connected_providers = AsyncMock(return_value=["google_gmail"])
    gemini = MagicMock()
    gemini.analyze_intent = AsyncMock(
        return_value={
            "intent": "send_email",
            "required_providers": ["google_drive"],
            "entities": {},
            "reasoning": "need drive",
            "user_message": "",
        }
    )
    gemini.unsupported_capability_reply = AsyncMock(return_value="Sorry, I can't use Drive.")
    gemini.emit_stream_chunks = AsyncMock()
    tv = MagicMock(spec=TokenVaultService)
    cartesia = MagicMock(spec=CartesiaService)
    cartesia.stream_tts = AsyncMock()
    gmail = MagicMock(spec=GmailService)
    cal = MagicMock(spec=CalendarService)
    slack = MagicMock(spec=SlackService)
    settings = MagicMock(spec=Settings)
    settings.memory_short_term_context_n = 5

    h = TranscriptHandler(
        connections=connections,
        sessions=sessions,
        gemini=gemini,
        token_vault=tv,
        cartesia=cartesia,
        gmail=gmail,
        calendar=cal,
        slack=slack,
        settings=settings,
        memory=None,
    )

    await h.handle_transcript("sid", "uid", "attach from Drive")

    gemini.unsupported_capability_reply.assert_called_once()
    sessions.set_pending_task.assert_not_called()
