from __future__ import annotations

import time
from typing import Any

import httpx
import structlog

from src.config import Settings
from src.utils.auth0_client import Auth0HttpClient
from src.utils.redis_client import RedisStore
from src.utils.service_log import err_ctx

logger = structlog.get_logger(__name__)

_SERVICE = "token_vault"

# Google API resource server audience for access tokens
GOOGLE_API_AUDIENCE = "https://www.googleapis.com/"


def _provider_audience(provider: str) -> str:
    if provider in ("google_gmail", "google_calendar"):
        return GOOGLE_API_AUDIENCE
    return GOOGLE_API_AUDIENCE


class TokenVaultService:
    def __init__(self, settings: Settings, redis: RedisStore) -> None:
        self._settings = settings
        self._redis = redis
        self._auth0 = Auth0HttpClient(settings)

    def _cache_key(self, user_id: str, provider: str) -> str:
        return f"token:{user_id}:{provider}"

    async def get_access_token(
        self,
        user_id: str,
        provider: str,
        *,
        refresh_token: str,
    ) -> str:
        ck = self._cache_key(user_id, provider)
        try:
            cached = await self._redis.get_json(ck)
            if cached and cached.get("access_token") and cached.get("exp", 0) > time.time() + 30:
                logger.info(
                    "google_access_token_cache_hit",
                    user_id=user_id,
                    provider=provider,
                )
                return str(cached["access_token"])
        except Exception as e:
            logger.warning(
                "token_vault_cache_read_failed",
                service=_SERVICE,
                operation="read_cached_token",
                user_id=user_id,
                provider=provider,
                **err_ctx(e),
                exc_info=True,
            )

        logger.info(
            "token_exchange_attempt",
            service=_SERVICE,
            operation="exchange_refresh_for_access",
            user_id=user_id,
            provider=provider,
            connection=self._settings.auth0_google_connection_name,
        )

        body = {
            "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
            "subject_token": refresh_token,
            "subject_token_type": "urn:ietf:params:oauth:token-type:refresh_token",
            "requested_token_type": "urn:ietf:params:oauth:token-type:access_token",
            "audience": _provider_audience(provider),
            "connection": self._settings.auth0_google_connection_name,
            "client_id": self._settings.auth0_custom_api_client_id,
            "client_secret": self._settings.auth0_custom_api_client_secret,
        }

        resp = await self._auth0.post_token(body)
        if resp.status_code >= 400:
            err_hint = ""
            try:
                err_body = resp.json()
                err_hint = str(err_body.get("error", ""))[:120]
                desc = err_body.get("error_description")
                if isinstance(desc, str) and desc:
                    err_hint = f"{err_hint}:{desc[:160]}"
            except Exception:
                err_hint = (resp.text or "")[:200]
            logger.warning(
                "token_exchange_failed",
                service=_SERVICE,
                operation="exchange_refresh_for_access",
                user_id=user_id,
                provider=provider,
                status=resp.status_code,
                error_hint=err_hint,
            )
            raise RuntimeError(f"token_exchange_failed:{resp.status_code}")

        data: dict[str, Any] = resp.json()
        access = str(data.get("access_token", ""))
        expires_in = int(data.get("expires_in", 3600))
        exp = time.time() + expires_in
        logger.info(
            "token_exchanged",
            service=_SERVICE,
            operation="exchange_refresh_for_access",
            provider=provider,
            expires_at=int(exp),
        )
        ttl = max(30, expires_in - 60)
        await self._redis.set_json(ck, {"access_token": access, "exp": exp}, ex=ttl)
        return access

    async def get_connected_providers(self, user_id: str) -> list[str]:
        """Placeholder: Token Vault connection status is enforced via successful token exchange."""
        cached = await self._redis.get_json(f"user:{user_id}:connected_providers")
        if cached and "providers" in cached:
            return list(cached["providers"])
        return []
