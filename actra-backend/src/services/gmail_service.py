from __future__ import annotations

from typing import Any

import httpx
import structlog

from src.utils.service_log import err_ctx

logger = structlog.get_logger(__name__)

_SERVICE = "google_gmail"


class GmailService:
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
