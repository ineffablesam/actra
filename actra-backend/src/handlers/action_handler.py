from __future__ import annotations

from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

import structlog

from src.core.connection_manager import ConnectionManager
from src.core.session_manager import SessionManager
from src.models.events import ActionResultEvent, ErrorEvent
from src.services.github_service import GitHubService, user_facing_github_error
from src.services.gmail_service import GmailService
from src.services.token_vault_service import TokenVaultExchangeError, TokenVaultService
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
        github: GitHubService,
    ) -> None:
        self._connections = connections
        self._sessions = sessions
        self._token_vault = token_vault
        self._gmail = gmail
        self._github = github

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

        payload = edited_payload or {}
        if str(payload.get("draft_type") or "") == "github_pr":
            await self._send_github_pr(session_id, user_id, action_id, payload)
            return

        auth0_at = await self._sessions.get_auth0_access_token(session_id)
        if not auth0_at:
            await self._send(
                session_id,
                ErrorEvent(
                    session_id=session_id,
                    code="AUTH_REQUIRED",
                    message="Missing Auth0 access token for sending.",
                    recoverable=True,
                ).model_dump(),
            )
            return

        try:
            access = await self._token_vault.get_access_token(
                user_id,
                "google_gmail",
                auth0_access_token=auth0_at,
            )
        except TokenVaultExchangeError as e:
            logger.error(
                "action_gmail_token_failed",
                service="token_vault",
                operation="get_access_token",
                auth0_hint=e.auth0_hint[:200] if e.auth0_hint else None,
                **err_ctx(e),
                exc_info=True,
            )
            msg = e.client_message or "Could not retrieve Gmail token."
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

    async def _send_github_pr(
        self,
        session_id: str,
        user_id: str,
        action_id: str,
        payload: dict,
    ) -> None:
        auth0_at = await self._sessions.get_auth0_access_token(session_id)
        if not auth0_at:
            await self._send(
                session_id,
                ErrorEvent(
                    session_id=session_id,
                    code="AUTH_REQUIRED",
                    message="Missing Auth0 access token for GitHub.",
                    recoverable=True,
                ).model_dump(),
            )
            return
        try:
            access = await self._token_vault.get_access_token(
                user_id,
                "github",
                auth0_access_token=auth0_at,
            )
        except TokenVaultExchangeError as e:
            msg = e.client_message or "Could not retrieve GitHub token."
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
            logger.error(
                "action_github_token_failed",
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
                    message="Could not retrieve GitHub token.",
                    recoverable=True,
                ).model_dump(),
            )
            return

        owner = str(payload.get("owner") or "").strip()
        repo = str(payload.get("repo") or "").strip()
        base_branch = str(payload.get("base_branch") or "main").strip()
        head_branch = str(payload.get("head_branch") or "").strip()
        file_path = str(payload.get("file_path") or "").strip()
        file_content = str(payload.get("file_content") or "")
        pr_title = str(payload.get("pr_title") or "Actra patch")
        pr_body = str(payload.get("pr_body") or "")
        commit_message = str(payload.get("commit_message") or "chore: actra patch")

        if not owner or not repo or not head_branch or not file_path:
            await self._send(
                session_id,
                ActionResultEvent(
                    session_id=session_id,
                    action_id=action_id,
                    success=False,
                    message="Invalid GitHub PR draft (missing owner, repo, branch, or path).",
                ).model_dump(),
            )
            return

        try:
            pr = await self._github.create_branch_commit_and_pr(
                access,
                owner=owner,
                repo=repo,
                base_branch=base_branch,
                head_branch=head_branch,
                file_path=file_path,
                file_content=file_content,
                commit_message=commit_message,
                pr_title=pr_title,
                pr_body=pr_body,
            )
            num = pr.get("number")
            url = pr.get("html_url") or ""
            msg = f"Pull request opened: #{num} — {url}".strip()
            await self._send(
                session_id,
                ActionResultEvent(
                    session_id=session_id,
                    action_id=action_id,
                    success=True,
                    message=msg,
                ).model_dump(),
            )
        except Exception as e:
            logger.error(
                "action_github_pr_failed",
                service="github",
                operation="create_branch_commit_and_pr",
                **err_ctx(e),
                exc_info=True,
            )
            await self._send(
                session_id,
                ActionResultEvent(
                    session_id=session_id,
                    action_id=action_id,
                    success=False,
                    message=user_facing_github_error(e),
                ).model_dump(),
            )
