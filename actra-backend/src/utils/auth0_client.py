from __future__ import annotations

import httpx
import structlog

from src.config import Settings

logger = structlog.get_logger(__name__)


class Auth0HttpClient:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._base = f"https://{settings.auth0_domain}"

    async def post_token(self, body: dict) -> httpx.Response:
        url = f"{self._base}/oauth/token"
        async with httpx.AsyncClient(timeout=30.0) as client:
            return await client.post(url, json=body)
