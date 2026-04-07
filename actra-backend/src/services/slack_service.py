from __future__ import annotations

import re
from typing import Any

import httpx
import structlog

from src.utils.service_log import err_ctx

logger = structlog.get_logger(__name__)

_SERVICE = "slack"
_SLACK_API = "https://slack.com/api"


class SlackService:
    """Slack Web API using a user token from Auth0 Token Vault (Sign in with Slack)."""

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
                    params={"types": "public_channel", "limit": "50"},
                )
                conv_data = conv_resp.json()
                if conv_data.get("ok") and isinstance(conv_data.get("channels"), list):
                    for ch in conv_data["channels"][:30]:
                        if isinstance(ch, dict):
                            channels.append(
                                {
                                    "id": ch.get("id"),
                                    "name": ch.get("name"),
                                    "num_members": ch.get("num_members"),
                                    "is_member": ch.get("is_member"),
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

    def _pick_channel_id(self, user_text: str, channels: list[dict[str, Any]]) -> tuple[str | None, str | None]:
        """Return (channel_id, channel_name) to read history from.

        Slack returns ``not_in_channel`` for ``conversations.history`` when the **user** is not in
        the channel — OAuth scopes are not enough. Prefer channels the user has joined
        (``is_member``), which ``conversations.list`` includes for user tokens.
        """
        if not channels:
            return None, None
        joined = [c for c in channels if c.get("is_member") is True]
        text_lower = user_text.lower()
        # Explicit #channel: resolve ID from full list (history still requires membership).
        hash_m = re.search(r"#([a-z0-9_-]+)", user_text, re.I)
        if hash_m:
            want = hash_m.group(1).lower()
            for ch in channels:
                if (ch.get("name") or "").lower() == want:
                    return ch.get("id"), ch.get("name")
            return None, None
        # Heuristics below: only channels the user has joined (avoids ``not_in_channel``).
        if not joined:
            return None, None
        pool = joined
        # Word match against channel name (prefer longer names first)
        scored: list[tuple[int, dict[str, Any]]] = []
        for ch in pool:
            name = (ch.get("name") or "").lower()
            if not name:
                continue
            if re.search(rf"\b{re.escape(name)}\b", text_lower):
                scored.append((len(name), ch))
        if scored:
            scored.sort(key=lambda x: -x[0])
            ch = scored[0][1]
            return ch.get("id"), ch.get("name")
        # Default: #general if present, else first channel (from pool)
        for ch in pool:
            if (ch.get("name") or "").lower() == "general":
                return ch.get("id"), ch.get("name")
        ch0 = pool[0]
        return ch0.get("id"), ch0.get("name")

    async def _fetch_users_display_map(
        self,
        client: httpx.AsyncClient,
        headers: dict[str, str],
    ) -> dict[str, str]:
        """One ``users.list`` call (needs ``users:read``) — avoids N × ``users.info``."""
        out: dict[str, str] = {}
        try:
            r = await client.get(
                f"{_SLACK_API}/users.list",
                headers=headers,
                params={"limit": "200"},
            )
            data = r.json()
            if not data.get("ok"):
                return out
            for m in data.get("members") or []:
                if not isinstance(m, dict):
                    continue
                uid = m.get("id")
                if not uid:
                    continue
                prof = m.get("profile") or {}
                name = (
                    prof.get("display_name_normalized")
                    or prof.get("real_name")
                    or m.get("real_name")
                    or m.get("name")
                    or uid
                )
                out[str(uid)] = str(name)
        except Exception as e:
            logger.warning(
                "slack_users_list_failed",
                service=_SERVICE,
                **err_ctx(e),
                exc_info=True,
            )
        return out

    async def _fetch_channel_history(
        self,
        client: httpx.AsyncClient,
        headers: dict[str, str],
        channel_id: str,
        user_names: dict[str, str],
        *,
        limit: int = 10,
    ) -> tuple[list[dict[str, Any]], str | None]:
        """Returns normalized messages and Slack API error string if not ok."""
        try:
            r = await client.get(
                f"{_SLACK_API}/conversations.history",
                headers=headers,
                params={"channel": channel_id, "limit": str(limit)},
            )
            data = r.json()
        except Exception as e:
            logger.error(
                "slack_conversations_history_request_failed",
                service=_SERVICE,
                **err_ctx(e),
                exc_info=True,
            )
            return [], str(e)

        if not data.get("ok"):
            err = str(data.get("error") or "unknown_error")
            logger.warning(
                "slack_conversations_history_failed",
                service=_SERVICE,
                error=err,
            )
            return [], err

        raw = data.get("messages")
        if not isinstance(raw, list):
            return [], None

        out: list[dict[str, Any]] = []
        for m in raw:
            if not isinstance(m, dict):
                continue
            if m.get("subtype") in ("channel_join", "channel_leave", "channel_topic"):
                continue
            text = (m.get("text") or "").strip()
            if not text:
                continue
            ts = m.get("ts")
            if m.get("bot_id") or m.get("subtype") == "bot_message":
                who = m.get("username") or (m.get("bot_profile") or {}).get("name") or "Bot"
            else:
                uid = str(m.get("user") or "")
                who = user_names.get(uid, uid or "unknown")
            out.append(
                {
                    "from": who,
                    "text": text[:2000],
                    "ts": ts,
                }
            )
        return out, None

    async def fetch_slack_context(self, access_token: str, user_text: str) -> dict[str, Any]:
        """
        Workspace metadata, channel list, and **recent messages** from one channel.

        Uses ``conversations.history`` (needs ``channels:history`` on the Slack app / connection).
        """
        base = await self.fetch_workspace_context(access_token)
        if not base.get("ok"):
            return base

        channels = base.get("channels_sample") or []
        cid, cname = self._pick_channel_id(user_text, channels)
        base["messages_channel_name"] = cname
        base["recent_messages"] = []
        base["messages_error"] = None

        if not cid:
            if channels and not any(c.get("is_member") for c in channels):
                base["messages_note"] = (
                    "Open a public channel in Slack (so your account joins it) — then Actra can load recent messages."
                )
            else:
                base["messages_note"] = "No channel available to read message history."
            return base

        headers = {"Authorization": f"Bearer {access_token}"}
        async with httpx.AsyncClient(timeout=45.0) as client:
            user_names = await self._fetch_users_display_map(client, headers)
            msgs, err = await self._fetch_channel_history(
                client,
                headers,
                cid,
                user_names,
                limit=12,
            )
            base["recent_messages"] = msgs
            if err:
                base["messages_error"] = err
                if err == "missing_scope":
                    base["messages_note"] = (
                        "Slack token is missing channels:history — reconnect Slack or add that scope."
                    )
                elif err == "not_in_channel":
                    base["messages_note"] = (
                        "Slack only returns history for channels you have joined. "
                        "Open that channel once in Slack (or use /invite) so your account is a member, then try again."
                    )
            elif not msgs:
                base["messages_note"] = "No recent messages in this channel (or only system events)."

        return base
