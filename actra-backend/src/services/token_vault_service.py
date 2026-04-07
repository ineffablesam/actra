from __future__ import annotations

import time
from typing import Any

import structlog

from src.config import Settings
from src.constants import SUPPORTED_PROVIDERS
from src.utils.auth0_client import Auth0HttpClient
from src.utils.redis_client import RedisStore
from src.utils.service_log import err_ctx

logger = structlog.get_logger(__name__)

_SERVICE = "token_vault"

_FEDERATED_TOKEN_EXCHANGE_GRANT = (
    "urn:auth0:params:oauth:grant-type:token-exchange:federated-connection-access-token"
)
_REQUESTED_TOKEN_TYPE_FEDERATED = "http://auth0.com/oauth/token-type/federated-connection-access-token"
_SUBJECT_ACCESS_TOKEN = "urn:ietf:params:oauth:token-type:access_token"


class TokenVaultExchangeError(Exception):
    """Auth0 /oauth/token rejected federated token exchange (see [client_message] for user-facing text)."""

    def __init__(
        self,
        status_code: int,
        *,
        auth0_hint: str = "",
        client_message: str | None = None,
        ws_error_code: str = "TOKEN_VAULT_ERROR",
    ) -> None:
        self.status_code = status_code
        self.auth0_hint = auth0_hint
        self.client_message = client_message
        self.ws_error_code = ws_error_code
        super().__init__(auth0_hint or f"token_exchange_failed:{status_code}")


class TokenVaultService:
    def __init__(self, settings: Settings, redis: RedisStore) -> None:
        self._settings = settings
        self._redis = redis
        self._auth0 = Auth0HttpClient(settings)

    def _cache_key(self, user_id: str, provider: str) -> str:
        return f"token:{user_id}:{provider}"

    def _connection_for_provider(self, provider: str) -> str:
        """Auth0 social connection name used in federated token exchange."""
        if provider in ("google_gmail", "google_calendar"):
            return self._settings.auth0_google_connection_name
        if provider == "slack":
            return self._settings.auth0_slack_connection_name
        if provider == "github":
            return self._settings.auth0_github_connection_name
        raise ValueError(f"Unknown Token Vault provider: {provider}")

    async def clear_cached_access_tokens(self, user_id: str) -> None:
        for provider in SUPPORTED_PROVIDERS:
            await self._redis.delete(self._cache_key(user_id, provider))

    async def clear_cached_access_token(self, user_id: str, provider: str) -> None:
        if provider not in SUPPORTED_PROVIDERS:
            return
        await self._redis.delete(self._cache_key(user_id, provider))

    async def get_access_token(
        self,
        user_id: str,
        provider: str,
        *,
        auth0_access_token: str,
    ) -> str:
        ck = self._cache_key(user_id, provider)
        try:
            cached = await self._redis.get_json(ck)
            if cached and cached.get("access_token") and cached.get("exp", 0) > time.time() + 30:
                logger.info(
                    "federated_access_token_cache_hit",
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

        connection = self._connection_for_provider(provider)
        logger.info(
            "token_exchange_attempt",
            service=_SERVICE,
            operation="exchange_auth0_access_for_federated",
            user_id=user_id,
            provider=provider,
            connection=connection,
        )

        body = {
            "grant_type": _FEDERATED_TOKEN_EXCHANGE_GRANT,
            "subject_token": auth0_access_token,
            "subject_token_type": _SUBJECT_ACCESS_TOKEN,
            "requested_token_type": _REQUESTED_TOKEN_TYPE_FEDERATED,
            "connection": connection,
            "client_id": self._settings.auth0_token_exchange_client_id,
            "client_secret": self._settings.auth0_token_exchange_client_secret,
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
                operation="exchange_auth0_access_for_federated",
                user_id=user_id,
                provider=provider,
                status=resp.status_code,
                error_hint=err_hint,
            )
            combined = (err_hint or "").lower()
            client_message: str | None = None
            ws_error_code = "TOKEN_VAULT_ERROR"
            cn = self._connection_for_provider(provider)
            if "token vault is not enabled" in combined:
                client_message = (
                    f'Token Vault is not enabled for Auth0 connection "{cn}". '
                    "In Auth0 Dashboard: Authentication → Social → [your connection] → enable "
                    "Connected Accounts for Token Vault. Then sign out and sign in again."
                )
                ws_error_code = "TOKEN_VAULT_NOT_CONFIGURED"
            elif "federated_connection_refresh_token_not_found" in combined:
                client_message = (
                    f'Auth0 has no federated refresh token in Token Vault for connection "{cn}". '
                    "Sign out, sign in again, and complete the Connected Accounts link (My Account API) "
                    "so Auth0 can store tokens for that provider."
                )
                ws_error_code = "FEDERATED_TOKEN_NOT_IN_VAULT"
            raise TokenVaultExchangeError(
                resp.status_code,
                auth0_hint=err_hint,
                client_message=client_message,
                ws_error_code=ws_error_code,
            )

        data: dict[str, Any] = resp.json()
        access = str(data.get("access_token", ""))
        expires_in = int(data.get("expires_in", 3600))
        exp = time.time() + expires_in
        logger.info(
            "token_exchanged",
            service=_SERVICE,
            operation="exchange_auth0_access_for_federated",
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
