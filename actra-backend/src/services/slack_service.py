from __future__ import annotations

from typing import Any

import httpx
import structlog

from src.utils.service_log import err_ctx

logger = structlog.get_logger(__name__)

_SERVICE = "slack"
_SLACK_API = "https://slack.com/api"


class SlackService:
    """Minimal Slack Web API client using a user or bot token from Auth0 Token Vault."""

    async def fetch_workspace_context(self, access_token: str) -> dict[str, Any]:
        """
        Return auth.test plus a short list of public channels for drafting context.

        Requires scopes such as ``channels:read`` (and optionally ``channels:history``).
        """
        headers = {"Authorization": f"Bearer {access_token}"}
        async with httpx.AsyncClient(timeout=30.0) as client:
            auth_resp = await client.post(f"{_SLACK_API}/auth.test", headers=headers)
            try:
                auth_data = auth_resp.json()
            except Exception as e:
                logger.error(
                    "slack_auth_test_json_failed",
                    service=_SERVICE,
                    status=auth_resp.status_code,
                    **err_ctx(e),
                    exc_info=True,
                )
                return {"ok": False, "error": "invalid_response"}

            if not auth_data.get("ok"):
                logger.warning(
                    "slack_auth_test_failed",
                    service=_SERVICE,
                    error=auth_data.get("error"),
                )
                return auth_data

            channels: list[dict[str, Any]] = []
            try:
                conv_resp = await client.get(
                    f"{_SLACK_API}/conversations.list",
                    headers=headers,
                    params={"types": "public_channel", "limit": "20"},
                )
                conv_data = conv_resp.json()
                if conv_data.get("ok") and isinstance(conv_data.get("channels"), list):
                    for ch in conv_data["channels"][:15]:
                        if isinstance(ch, dict):
                            channels.append(
                                {
                                    "id": ch.get("id"),
                                    "name": ch.get("name"),
                                    "num_members": ch.get("num_members"),
                                }
                            )
            except Exception as e:
                logger.warning(
                    "slack_conversations_list_failed",
                    service=_SERVICE,
                    **err_ctx(e),
                    exc_info=True,
                )

            return {
                "ok": True,
                "team": auth_data.get("team"),
                "team_id": auth_data.get("team_id"),
                "user": auth_data.get("user"),
                "user_id": auth_data.get("user_id"),
                "url": auth_data.get("url"),
                "channels_sample": channels,
            }
