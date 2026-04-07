from __future__ import annotations

import asyncio
import base64
import re
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
from src.services.github_service import GitHubService
from src.services.slack_service import SlackService
from src.services.token_vault_service import TokenVaultExchangeError, TokenVaultService
from src.memory.retrieval import retrieve_context_bundle
from src.memory.service import MemoryService
from src.utils.service_log import err_ctx

logger = structlog.get_logger(__name__)


def _resolve_github_repo(entities: dict[str, Any], user_text: str) -> tuple[str | None, str | None]:
    o = str(entities.get("repo_owner") or "").strip()
    r = str(entities.get("repo_name") or "").strip()
    if o and r:
        return o, r
    m = re.search(r"([\w.-]+)/([\w.-]+)", user_text)
    if m:
        return m.group(1), m.group(2)
    return None, None


def _parse_issue_number(raw: Any) -> int | None:
    if raw is None:
        return None
    s = str(raw).strip()
    m = re.search(r"\d+", s)
    if m:
        return int(m.group(0))
    return None


def _parse_issue_number_with_text(raw: Any, user_text: str) -> int | None:
    """Prefer structured entities; fall back to phrases like ``issue 12`` or ``#12`` in the utterance."""
    n = _parse_issue_number(raw)
    if n is not None:
        return n
    m = re.search(r"(?:^|\s)(?:issue|fix)\s*#?\s*(\d{1,7})\b", user_text, re.I)
    if m:
        return int(m.group(1))
    m = re.search(r"#\s*(\d{1,7})\b", user_text)
    if m:
        return int(m.group(1))
    return None


def _user_uses_deictic_issue_reference(user_text: str) -> bool:
    """User points at a previously mentioned issue (e.g. "fix the issue") without repeating #N."""
    t = (user_text or "").strip()
    if not t:
        return False
    if re.search(r"#\s*\d{1,7}\b", t):
        return False
    if re.search(r"\b(?:issue|fix)\s*#?\s*\d{1,7}\b", t, re.I):
        return False
    needles = (
        "the issue",
        "that issue",
        "this issue",
        "fix it",
        "fix that",
        "address it",
        "resolve it",
        "resolve that",
        "close it",
        "fix the problem",
        "that problem",
        "that one",
    )
    return any(n in t.lower() for n in needles)


def _recent_conversation_section(memory_block: str) -> str:
    """Isolate the formatted short-term transcript from the combined memory prompt."""
    if not memory_block or not memory_block.strip():
        return ""
    m = re.search(
        r"Recent Conversation:\s*\n(.*?)(?:\n\nRelevant Memory:|\Z)",
        memory_block,
        re.DOTALL,
    )
    chunk = m.group(1).strip() if m else memory_block.strip()
    return chunk


def _parse_issue_number_from_recent_conversation_memory(
    user_text: str,
    memory_block: str | None,
) -> int | None:
    """When the user omits #N, take the last issue number cited in recent conversation (e.g. assistant listed #2)."""
    if not memory_block or not _user_uses_deictic_issue_reference(user_text):
        return None
    recent = _recent_conversation_section(memory_block)
    if not recent or recent == "(none)":
        return None
    matches = list(re.finditer(r"#\s*(\d{1,7})\b", recent))
    if not matches:
        matches = list(re.finditer(r"\bissue\s*#?\s*(\d{1,7})\b", recent, re.I))
    if not matches:
        return None
    return int(matches[-1].group(1))


def _parse_issue_number_with_memory(
    raw: Any,
    user_text: str,
    memory_block: str | None,
) -> int | None:
    n = _parse_issue_number_with_text(raw, user_text)
    if n is not None:
        return n
    return _parse_issue_number_from_recent_conversation_memory(user_text, memory_block)


def _sanitize_branch(name: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9._-]", "-", name.strip().lower())
    s = re.sub(r"-+", "-", s).strip("-")
    if not s.startswith("actra-fix-"):
        s = f"actra-fix-{s}"[:120]
    return s or "actra-fix-patch"


def _references_deictic_repo(text: str) -> bool:
    """Phrases like 'this repo' with no owner/name in the same utterance."""
    t = text.lower()
    needles = (
        "this repo",
        "that repo",
        "the repo",
        "this repository",
        "that repository",
        "my repo",
        "current repo",
        "in here",
    )
    return any(n in t for n in needles)


def _try_repo_from_memory(memory_block: str | None) -> tuple[str | None, str | None]:
    if not memory_block or not memory_block.strip():
        return None, None
    m = re.search(r"([\w.-]+)/([\w.-]+)", memory_block)
    if m:
        return m.group(1), m.group(2)
    return None, None


def _resolve_github_repo_with_memory(
    entities: dict[str, Any],
    user_text: str,
    memory_block: str | None,
) -> tuple[str | None, str | None]:
    o, r = _resolve_github_repo(entities, user_text)
    if o and r:
        return o, r
    return _try_repo_from_memory(memory_block)


def _github_search_needs_clarification(entities: dict[str, Any], user_text: str) -> bool:
    q = str(entities.get("search_query") or user_text).strip()
    if len(q) < 2:
        return True
    low = q.lower()
    vague_only = {
        "github",
        "repos",
        "repo",
        "repository",
        "repositories",
        "search repos",
        "find repos",
        "search for repos",
        "find a repo",
    }
    if low in vague_only:
        return True
    if re.fullmatch(r"(search|find)(\s+a)?\s+repos?", low):
        return True
    return False


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
        github: GitHubService,
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
        self._github = github
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

        if intent == "github_issues" and "github" in required:
            owner, repo = _resolve_github_repo_with_memory(entities, text, memory_block)
            if not owner or not repo:
                kind = "ambiguous_this_repo" if _references_deictic_repo(text) else "need_repo"
                reply = await self._gemini.github_followup_reply(
                    user_text=text,
                    kind=kind,
                    memory_context=memory_block,
                )
                await self._stream_agent_response(session_id, reply, log)
                await self._finalize_memory_turn(
                    user_id=user_id,
                    user_text=text,
                    intent=intent,
                    assistant_text=reply,
                )
                return

        if intent == "github_repo_search" and "github" in required:
            if _github_search_needs_clarification(entities, text):
                reply = await self._gemini.github_followup_reply(
                    user_text=text,
                    kind="need_search_query",
                    memory_context=memory_block,
                )
                await self._stream_agent_response(session_id, reply, log)
                await self._finalize_memory_turn(
                    user_id=user_id,
                    user_text=text,
                    intent=intent,
                    assistant_text=reply,
                )
                return

        if intent == "github_fix_pr" and "github" in required:
            await self._handle_github_fix_pr(
                session_id,
                user_id,
                text,
                entities,
                log,
                memory_block=memory_block,
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
                        slack_ctx = await self._slack.fetch_slack_context(tok, text)
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
                    if provider == "github":
                        owner, repo = _resolve_github_repo_with_memory(entities, text, memory_block)
                        if intent == "github_repo_search":
                            q = str(entities.get("search_query") or text).strip()
                            repos = await self._github.search_repositories(tok, q)
                            context_snippets["github"] = {
                                "repo_search": [
                                    {
                                        "full_name": r.get("full_name"),
                                        "description": r.get("description"),
                                        "html_url": r.get("html_url"),
                                    }
                                    for r in repos[:8]
                                ]
                            }
                        elif intent == "github_issues":
                            inum = _parse_issue_number_with_text(entities.get("issue_number"), text)
                            if inum is not None:
                                issue = await self._github.get_issue(tok, owner, repo, inum)
                                context_snippets["github"] = {"issue_detail": issue}
                            else:
                                issues = await self._github.list_issues(tok, owner, repo)
                                context_snippets["github"] = {
                                    "issues": [
                                        {
                                            "number": i.get("number"),
                                            "title": i.get("title"),
                                            "state": i.get("state"),
                                        }
                                        for i in issues[:15]
                                    ]
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

    async def _stream_code_preview(self, session_id: str, code: str, log: Any) -> None:
        async def emit_agent(chunk: str) -> None:
            await self._send(
                session_id,
                AgentStreamEvent(
                    session_id=session_id,
                    chunk=chunk,
                    done=False,
                    segment="code",
                ).model_dump(),
            )

        try:
            await self._gemini.emit_stream_code_lines(code, emit_agent)
        except Exception as e:
            log.error(
                "code_preview_stream_failed",
                service="transcript",
                operation="emit_stream_code_lines",
                **err_ctx(e),
                exc_info=True,
            )
        await self._send(
            session_id,
            AgentStreamEvent(session_id=session_id, chunk="", done=True, segment="code").model_dump(),
        )

    async def _handle_github_fix_pr(
        self,
        session_id: str,
        user_id: str,
        text: str,
        entities: dict[str, Any],
        log: Any,
        *,
        memory_block: str | None,
    ) -> None:
        owner, repo = _resolve_github_repo_with_memory(entities, text, memory_block)
        inum = _parse_issue_number_with_memory(entities.get("issue_number"), text, memory_block)
        if not owner or not repo or inum is None:
            reply = await self._gemini.github_followup_reply(
                user_text=text,
                kind="need_fix_details",
                memory_context=memory_block,
            )
            await self._stream_agent_response(session_id, reply, log)
            await self._finalize_memory_turn(
                user_id=user_id,
                user_text=text,
                intent="github_fix_pr",
                assistant_text=reply,
            )
            return

        auth0_at = await self._sessions.get_auth0_access_token(session_id)
        if not auth0_at:
            await self._send(
                session_id,
                ErrorEvent(
                    session_id=session_id,
                    code="AUTH_REQUIRED",
                    message="Send session_auth with an access token so the server can reach GitHub.",
                    recoverable=True,
                ).model_dump(),
            )
            return

        try:
            tok = await self._token_vault.get_access_token(
                user_id,
                "github",
                auth0_access_token=auth0_at,
            )
        except TokenVaultExchangeError as e:
            msg = (
                e.client_message
                if e.client_message
                else "Could not retrieve GitHub token. Reconnect GitHub in Connected Accounts."
            )
            await self._send(
                session_id,
                ErrorEvent(
                    session_id=session_id,
                    code=e.ws_error_code,
                    message=msg,
                    recoverable=True,
                ).model_dump(),
            )
            return
        except Exception as e:
            log.error(
                "github_token_failed",
                **err_ctx(e),
                exc_info=True,
            )
            await self._send(
                session_id,
                ErrorEvent(
                    session_id=session_id,
                    code="TOKEN_VAULT_ERROR",
                    message="Could not retrieve GitHub token.",
                    recoverable=True,
                ).model_dump(),
            )
            return

        try:
            issue = await self._github.get_issue(tok, owner, repo, inum)
            base = await self._github.get_default_branch(tok, owner, repo)
        except Exception as e:
            log.error(
                "github_issue_or_repo_failed",
                **err_ctx(e),
                exc_info=True,
            )
            err_msg = f"I could not read that issue or repository on GitHub: {e}"
            await self._stream_agent_response(session_id, err_msg, log)
            await self._finalize_memory_turn(
                user_id=user_id,
                user_text=text,
                intent="github_fix_pr",
                assistant_text=err_msg,
            )
            return

        title = str(issue.get("title") or "")
        body = str(issue.get("body") or "")
        user_request = text
        if memory_block:
            user_request = f"{text}\n\nMemory context:\n{memory_block}"

        patch = await self._gemini.generate_github_pr_patch(
            user_request=user_request,
            issue_title=title,
            issue_body=body,
            repo_full_name=f"{owner}/{repo}",
            default_branch=base,
        )
        explanation = str(patch.get("explanation") or "Here is a proposed fix.")
        file_content = str(patch.get("file_content") or "")
        file_path = str(patch.get("file_path") or "actra-fix/patch.txt")
        pr_title = str(patch.get("pr_title") or f"Fix issue #{inum}")
        pr_body = str(patch.get("pr_body") or f"Resolves #{inum}")
        commit_message = str(patch.get("commit_message") or f"fix: issue #{inum}")
        head_branch = _sanitize_branch(str(patch.get("head_branch") or f"actra-fix-{inum}"))

        await self._stream_agent_response(session_id, explanation, log)
        if file_content.strip():
            await self._stream_code_preview(session_id, file_content, log)

        action_id = str(uuid.uuid4())
        await self._send(
            session_id,
            DraftReadyEvent(
                session_id=session_id,
                action_id=action_id,
                type="github_pr",
                payload={
                    "draft_type": "github_pr",
                    "owner": owner,
                    "repo": repo,
                    "base_branch": base,
                    "head_branch": head_branch,
                    "file_path": file_path,
                    "file_content": file_content,
                    "pr_title": pr_title,
                    "pr_body": pr_body,
                    "commit_message": commit_message,
                },
            ).model_dump(),
        )
        combined = f"{explanation}\n\n```\n{file_content}\n```"
        await self._finalize_memory_turn(
            user_id=user_id,
            user_text=text,
            intent="github_fix_pr",
            assistant_text=combined,
        )

    async def _stream_agent_response(self, session_id: str, full_text: str, log: Any) -> None:
        async def emit_agent(chunk: str) -> None:
            await self._send(
                session_id,
                AgentStreamEvent(
                    session_id=session_id,
                    chunk=chunk,
                    done=False,
                    segment="text",
                ).model_dump(),
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
            AgentStreamEvent(session_id=session_id, chunk="", done=True, segment="text").model_dump(),
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
