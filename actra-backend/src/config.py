from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    ws_host: str = "0.0.0.0"
    ws_port: int = 8765
    environment: str = "development"

    redis_url: str = "redis://localhost:6379/0"

    database_url: str = ""
    """asyncpg DSN, e.g. postgresql://actra:actra@localhost:5432/actra"""

    require_auth0_jwt: bool = True
    """If true, session_auth must include a valid access_token and all agent events must match verified sub."""

    auth0_domain: str = ""
    auth0_audience: str = "https://actra-api"
    # Custom API Client (Applications → APIs → your API → Add Application) linked to AUTH0_AUDIENCE.
    # Used for Token Vault *access-token* exchange (Native apps cannot use refresh-token exchange).
    auth0_token_exchange_client_id: str = ""
    auth0_token_exchange_client_secret: str = ""
    auth0_google_connection_name: str = "google-oauth2"

    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.0-flash"

    cartesia_api_key: str = ""
    cartesia_voice_id: str = "f786b574-daa5-4673-aa0c-cbe3e8534c02"
    cartesia_model_id: str = "sonic-3"
    cartesia_sample_rate: int = 44100


@lru_cache
def get_settings() -> Settings:
    return Settings()
