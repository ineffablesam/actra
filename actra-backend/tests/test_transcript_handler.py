from unittest.mock import AsyncMock, MagicMock

import pytest

from src.config import Settings
from src.handlers.transcript_handler import (
    TranscriptHandler,
    _parse_issue_number_with_memory,
    _user_uses_deictic_issue_reference,
)
from src.services.calendar_service import CalendarService
from src.services.cartesia_service import CartesiaService
from src.services.gemini_service import GeminiService
from src.services.gmail_service import GmailService
from src.services.github_service import GitHubService
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
    github = MagicMock(spec=GitHubService)
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
        github=github,
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
    github = MagicMock(spec=GitHubService)
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
        github=github,
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
    github = MagicMock(spec=GitHubService)
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
        github=github,
        settings=settings,
        memory=None,
    )

    await h.handle_transcript("sid", "uid", "attach from Drive")

    gemini.unsupported_capability_reply.assert_called_once()
    sessions.set_pending_task.assert_not_called()


def test_parse_issue_number_from_prior_assistant_turn_with_hash():
    mem = """Recent Conversation:
- user: List open issues in ineffablesam/codi
- assistant: There's one open issue in the ineffablesam/codi repository: * #2: Readme is Not Accurate for the Installation

Relevant Memory:
(none)

User Query:
Fix the Issue"""
    assert _parse_issue_number_with_memory(None, "Fix the Issue", mem) == 2
    assert _user_uses_deictic_issue_reference("Fix the Issue") is True


def test_parse_issue_number_explicit_in_utterance_wins_over_memory():
    mem = """Recent Conversation:
- assistant: Issue #2 is open.

User Query:
fix issue 3"""
    assert _parse_issue_number_with_memory(None, "fix issue 3", mem) == 3


def test_user_uses_deictic_issue_reference_false_when_number_in_utterance():
    assert _user_uses_deictic_issue_reference("fix #2") is False
    assert _user_uses_deictic_issue_reference("fix issue 2") is False
