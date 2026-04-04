from __future__ import annotations

from typing import Any

import jwt
import structlog
from jwt import PyJWKClient

from src.config import Settings

logger = structlog.get_logger(__name__)


class Auth0JwtService:
    """Validates Auth0 RS256 access tokens (API audience)."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._jwks_url = f"https://{settings.auth0_domain}/.well-known/jwks.json"
        self._issuer = f"https://{settings.auth0_domain}/"
        self._jwks_client: PyJWKClient | None = None

    def _client(self) -> PyJWKClient:
        if self._jwks_client is None:
            self._jwks_client = PyJWKClient(self._jwks_url)
        return self._jwks_client

    def verify_access_token(self, token: str) -> dict[str, Any]:
        if not self._settings.auth0_domain:
            raise ValueError("AUTH0_DOMAIN is not configured")
        signing_key = self._client().get_signing_key_from_jwt(token)
        audience = self._settings.auth0_audience
        decode_kw: dict[str, Any] = {
            "algorithms": ["RS256"],
            "issuer": self._issuer,
        }
        if audience:
            decode_kw["audience"] = audience
        return jwt.decode(
            token,
            signing_key.key,
            **decode_kw,
        )
