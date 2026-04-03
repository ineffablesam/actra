from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

import httpx
import structlog

from src.utils.service_log import err_ctx

logger = structlog.get_logger(__name__)

_SERVICE = "google_calendar"


class CalendarService:
    async def list_next_events(self, access_token: str, max_results: int = 5) -> list[dict[str, Any]]:
        now = datetime.now(timezone.utc).isoformat()
        url = "https://www.googleapis.com/calendar/v3/calendars/primary/events"
        params = {"timeMin": now, "maxResults": max_results, "singleEvents": True, "orderBy": "startTime"}
        headers = {"Authorization": f"Bearer {access_token}"}
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                r = await client.get(url, headers=headers, params=params)
                r.raise_for_status()
                data = r.json()
            return list(data.get("items", []))
        except httpx.HTTPStatusError as e:
            body_preview = (e.response.text or "")[:400]
            logger.error(
                "google_calendar_list_events_failed",
                service=_SERVICE,
                operation="list_next_events",
                status_code=e.response.status_code,
                body_preview=body_preview,
                **err_ctx(e),
                exc_info=True,
            )
            raise
        except Exception as e:
            logger.error(
                "google_calendar_list_events_failed",
                service=_SERVICE,
                operation="list_next_events",
                **err_ctx(e),
                exc_info=True,
            )
            raise
