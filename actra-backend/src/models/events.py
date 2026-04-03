from __future__ import annotations

from typing import Any, Literal, Union

from pydantic import BaseModel, Field


class SessionAuthEvent(BaseModel):
    """Client sends Auth0 refresh token once per session for Token Vault exchange."""

    event: Literal["session_auth"] = "session_auth"
    session_id: str
    user_id: str
    refresh_token: str


class TranscriptReceivedEvent(BaseModel):
    event: Literal["transcript_received"] = "transcript_received"
    session_id: str
    user_id: str
    text: str
    timestamp: str


class AccountConnectedEvent(BaseModel):
    event: Literal["account_connected"] = "account_connected"
    session_id: str
    user_id: str
    provider: str


class ActionConfirmedEvent(BaseModel):
    event: Literal["action_confirmed"] = "action_confirmed"
    session_id: str
    user_id: str
    action_id: str
    confirmed: bool


class ActionEditedEvent(BaseModel):
    event: Literal["action_edited"] = "action_edited"
    session_id: str
    user_id: str = ""
    action_id: str
    edited_payload: dict[str, Any]


class AgentThinkingEvent(BaseModel):
    event: Literal["agent_thinking"] = "agent_thinking"
    session_id: str
    message: str


class ConnectionsRequiredEvent(BaseModel):
    event: Literal["connections_required"] = "connections_required"
    session_id: str
    providers: list[str]
    reason: str
    task_context: str


class AgentStreamEvent(BaseModel):
    event: Literal["agent_stream"] = "agent_stream"
    session_id: str
    chunk: str
    done: bool = False


class DraftReadyEvent(BaseModel):
    event: Literal["draft_ready"] = "draft_ready"
    session_id: str
    action_id: str
    type: str
    payload: dict[str, Any]


class ActionResultEvent(BaseModel):
    event: Literal["action_result"] = "action_result"
    session_id: str
    action_id: str
    success: bool
    message: str


class TtsAudioChunkEvent(BaseModel):
    event: Literal["tts_audio_chunk"] = "tts_audio_chunk"
    session_id: str
    audio_base64: str
    sample_rate: int = 44100
    done: bool = False


class ErrorEvent(BaseModel):
    event: Literal["error"] = "error"
    session_id: str
    code: str
    message: str
    recoverable: bool = True


ClientEvent = Union[
    SessionAuthEvent,
    TranscriptReceivedEvent,
    AccountConnectedEvent,
    ActionConfirmedEvent,
    ActionEditedEvent,
]

ServerEvent = Union[
    AgentThinkingEvent,
    ConnectionsRequiredEvent,
    AgentStreamEvent,
    DraftReadyEvent,
    ActionResultEvent,
    TtsAudioChunkEvent,
    ErrorEvent,
]


def parse_client_event(data: dict[str, Any]) -> ClientEvent:
    kind = data.get("event")
    if kind == "session_auth":
        return SessionAuthEvent.model_validate(data)
    if kind == "transcript_received":
        return TranscriptReceivedEvent.model_validate(data)
    if kind == "account_connected":
        return AccountConnectedEvent.model_validate(data)
    if kind == "action_confirmed":
        return ActionConfirmedEvent.model_validate(data)
    if kind == "action_edited":
        return ActionEditedEvent.model_validate(data)
    raise ValueError(f"Unknown client event: {kind}")
