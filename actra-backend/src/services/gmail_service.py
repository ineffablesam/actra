from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx
import structlog

from src.utils.service_log import err_ctx

logger = structlog.get_logger(__name__)

_SERVICE = "google_gmail"


def build_gmail_list_query(user_text: str) -> tuple[str, bool]:
    """
    Build Gmail `q` for users.messages.list from the user's spoken request.

    Returns (query, is_narrow_search). Narrow searches use in:anywhere + date/keywords
    so mail outside Primary inbox (e.g. Promotions, categories) and archived mail can match.
    """
    t = user_text.strip()
    lower = t.lower()
    now = datetime.now(timezone.utc)
    today = now.date()

    scope = "in:inbox"
    parts: list[str] = []

    # Time window (Gmail uses the account timezone for "after:" day boundaries in UI;
    # we still narrow by calendar day in UTC + optional newer_than for "recent".)
    if re.search(r"\btoday\b", lower) or re.search(r"\bthis morning\b", lower):
        parts.append(f"after:{today.year}/{today.month:02d}/{today.day:02d}")
    elif re.search(r"\byesterday\b", lower):
        y = today - timedelta(days=1)
        parts.append(f"after:{y.year}/{y.month:02d}/{y.day:02d}")
        parts.append(f"before:{today.year}/{today.month:02d}/{today.day:02d}")
    elif re.search(r"\blast\s+week\b", lower):
        parts.append("newer_than:7d")

    # Phrase after "from …" (sender or brand)
    phrase = ""
    for pattern in (
        r"\b(?:email|emails|mail|mails)\s+from\s+([^?]+?)(?:\s+and\s+|\s+received|\s+i\s+|\s+today|\s+yesterday|\s*$|\?)",
        r"\bfrom\s+([^?]+?)(?:\s+and\s+(?:i\s+)?received|\s+today|\s+yesterday|\s*$|\?)",
    ):
        m = re.search(pattern, t, re.I | re.DOTALL)
        if m:
            phrase = m.group(1).strip()
            break

    phrase = re.sub(r"\s+(email|emails|mail|mails)\s*$", "", phrase, flags=re.I).strip()

    narrow = bool(parts) or bool(phrase)
    if narrow:
        # Search all labels (inbox, categories, updates, archived) so Promotions etc. match.
        scope = "in:anywhere"

    if phrase:
        if " " in phrase:
            parts.append(f'"{phrase}"')
        else:
            parts.append(phrase)

    q = f"{scope} " + " ".join(parts)
    return q.strip(), narrow


def _gmail_query_without_date_filters(q: str) -> str:
    """Drop after:/before: so a second list matches if day boundaries missed the message."""
    parts = [p for p in q.split() if not p.startswith("after:") and not p.startswith("before:")]
    return " ".join(parts)


class GmailService:
    async def fetch_inbox_summary(
        self,
        access_token: str,
        *,
        max_results: int = 10,
        query: str | None = None,
        user_query: str | None = None,
    ) -> list[dict[str, Any]]:
        """Recent messages with From, Subject, Date, snippet for LLM context.

        If ``user_query`` is set, builds a Gmail search ``q`` from natural language
        (sender, "today", etc.) instead of only listing the newest inbox messages.
        """
        if user_query is not None:
            q, narrow = build_gmail_list_query(user_query)
            if narrow and max_results < 25:
                max_results = 25
        else:
            q = query if query is not None else "in:inbox"

        logger.info("gmail_list_query", q=q, max_results=max_results)
        headers = {"Authorization": f"Bearer {access_token}"}
        list_url = "https://gmail.googleapis.com/gmail/v1/users/me/messages"
        try:
            async with httpx.AsyncClient(timeout=45.0) as client:
                lr = await client.get(
                    list_url,
                    headers=headers,
                    params={"maxResults": max_results, "q": q},
                )
                lr.raise_for_status()
                mids = [m["id"] for m in (lr.json().get("messages") or []) if m.get("id")]

                if not mids and user_query is not None:
                    q_relaxed = _gmail_query_without_date_filters(q)
                    if q_relaxed != q:
                        logger.info("gmail_list_retry_relaxed_query", q=q_relaxed)
                        lr2 = await client.get(
                            list_url,
                            headers=headers,
                            params={"maxResults": max_results, "q": q_relaxed},
                        )
                        lr2.raise_for_status()
                        mids = [m["id"] for m in (lr2.json().get("messages") or []) if m.get("id")]

                out: list[dict[str, Any]] = []
                meta_params = [
                    ("format", "metadata"),
                    ("metadataHeaders", "From"),
                    ("metadataHeaders", "Subject"),
                    ("metadataHeaders", "Date"),
                ]
                for mid in mids:
                    mr = await client.get(
                        f"{list_url}/{mid}",
                        headers=headers,
                        params=meta_params,
                    )
                    mr.raise_for_status()
                    msg = mr.json()
                    pl = msg.get("payload") or {}
                    hdrs: dict[str, str] = {}
                    for h in pl.get("headers") or []:
                        name = (h.get("name") or "").lower()
                        if name in ("from", "subject", "date"):
                            hdrs[name] = h.get("value") or ""
                    internal_date = msg.get("internalDate")
                    try:
                        internal_ms = int(internal_date) if internal_date is not None else 0
                    except (TypeError, ValueError):
                        internal_ms = 0
                    out.append(
                        {
                            "id": mid,
                            "from": hdrs.get("from", ""),
                            "subject": hdrs.get("subject", ""),
                            "date": hdrs.get("date", ""),
                            "snippet": msg.get("snippet") or "",
                            "internalDate": internal_ms,
                        }
                    )
                out.sort(key=lambda m: m.get("internalDate") or 0, reverse=True)
                for m in out:
                    m.pop("internalDate", None)
                return out
        except httpx.HTTPStatusError as e:
            body_preview = (e.response.text or "")[:400]
            logger.error(
                "gmail_fetch_inbox_summary_failed",
                service=_SERVICE,
                operation="fetch_inbox_summary",
                status_code=e.response.status_code,
                body_preview=body_preview,
                **err_ctx(e),
                exc_info=True,
            )
            raise
        except Exception as e:
            logger.error(
                "gmail_fetch_inbox_summary_failed",
                service=_SERVICE,
                operation="fetch_inbox_summary",
                **err_ctx(e),
                exc_info=True,
            )
            raise

    async def draft_send_preview(
        self,
        access_token: str,
        *,
        to_email: str,
        subject: str,
        body: str,
    ) -> dict[str, Any]:
        """Returns a draft-shaped payload (does not send until user confirms)."""
        return {
            "to": to_email,
            "subject": subject,
            "body": body,
            "cc": [],
        }

    async def send_message(self, access_token: str, raw_rfc822: str) -> dict[str, Any]:
        import base64

        url = "https://gmail.googleapis.com/gmail/v1/users/me/messages/send"
        b64 = base64.urlsafe_b64encode(raw_rfc822.encode()).decode()
        headers = {"Authorization": f"Bearer {access_token}"}
        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                r = await client.post(url, json={"raw": b64}, headers=headers)
                r.raise_for_status()
                return r.json()
        except httpx.HTTPStatusError as e:
            body_preview = (e.response.text or "")[:400]
            logger.error(
                "gmail_send_message_failed",
                service=_SERVICE,
                operation="send_message",
                status_code=e.response.status_code,
                body_preview=body_preview,
                **err_ctx(e),
                exc_info=True,
            )
            raise
        except Exception as e:
            logger.error(
                "gmail_send_message_failed",
                service=_SERVICE,
                operation="send_message",
                **err_ctx(e),
                exc_info=True,
            )
            raise
