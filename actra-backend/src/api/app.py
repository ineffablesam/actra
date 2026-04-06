from __future__ import annotations

from typing import Annotated, Any

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from src.config import Settings
from src.constants import SUPPORTED_PROVIDERS
from src.core.session_manager import SessionManager
from src.memory.service import MemoryService
from src.services.auth0_jwt_service import Auth0JwtService
from src.services.token_vault_service import TokenVaultService


class SaveMemoryBody(BaseModel):
    user_id: str = Field(min_length=1)
    content: str = Field(min_length=1)
    metadata: dict[str, Any] = Field(default_factory=dict)
    importance_score: float = Field(ge=0.0, le=1.0)


def create_http_app(
    memory: MemoryService,
    sessions: SessionManager,
    auth0_jwt: Auth0JwtService,
    token_vault: TokenVaultService,
    settings: Settings,
) -> FastAPI:
    """HTTP surface: health, memory debugging, and user linked integrations."""

    app = FastAPI(title="Actra API", version="1.0.0")

    def _current_user_sub(authorization: str | None) -> str:
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")
        raw = authorization.removeprefix("Bearer ").strip()
        if not raw:
            raise HTTPException(status_code=401, detail="Empty bearer token")
        try:
            claims = auth0_jwt.verify_access_token(raw)
        except Exception as e:
            raise HTTPException(status_code=401, detail="Invalid or expired access token") from e
        sub = str(claims.get("sub", "")).strip()
        if not sub:
            raise HTTPException(status_code=401, detail="Token missing sub")
        return sub

    async def current_user_sub(
        authorization: Annotated[str | None, Header()] = None,
        x_user_id: Annotated[str | None, Header()] = None,
    ) -> str:
        if settings.require_auth0_jwt:
            return _current_user_sub(authorization)
        uid = (x_user_id or "").strip()
        if uid:
            return uid
        raise HTTPException(
            status_code=401,
            detail="When REQUIRE_AUTH0_JWT is false, send X-User-Id (dev only).",
        )

    @app.get("/health")
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/users/me/connected-accounts")
    async def get_connected_accounts(user_id: str = Depends(current_user_sub)) -> dict[str, Any]:
        providers = await sessions.get_user_connected_providers(user_id) or []
        return {"user_id": user_id, "providers": providers}

    @app.delete("/users/me/connected-accounts/{provider}")
    async def disconnect_connected_account(
        provider: str,
        user_id: str = Depends(current_user_sub),
    ) -> dict[str, Any]:
        if provider not in SUPPORTED_PROVIDERS:
            raise HTTPException(
                status_code=400,
                detail=f"Unknown provider; expected one of {sorted(SUPPORTED_PROVIDERS)}",
            )
        # Gmail and Calendar share one Google OAuth connection in Auth0 Token Vault.
        if provider in ("google_gmail", "google_calendar"):
            await sessions.remove_connected_provider(user_id, "google_gmail")
            await sessions.remove_connected_provider(user_id, "google_calendar")
            await token_vault.clear_cached_access_token(user_id, "google_gmail")
            await token_vault.clear_cached_access_token(user_id, "google_calendar")
        else:
            await sessions.remove_connected_provider(user_id, provider)
            await token_vault.clear_cached_access_token(user_id, provider)
        return {"user_id": user_id, "disconnected": provider}

    @app.post("/memory/save")
    async def save_memory(body: SaveMemoryBody) -> dict[str, str]:
        try:
            mid = await memory.save_memory(
                body.user_id,
                body.content,
                body.metadata,
                body.importance_score,
            )
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e)) from e
        return {"id": mid}

    @app.get("/memory/search")
    async def search_memory(user_id: str, q: str, top_k: int = 3) -> dict[str, Any]:
        if not user_id.strip():
            raise HTTPException(status_code=400, detail="user_id is required")
        rows = await memory.retrieve_memories(user_id, q, top_k=top_k)
        return {"user_id": user_id, "query": q, "results": rows}

    return app


