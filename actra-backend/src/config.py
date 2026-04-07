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
    """Auth0 social connection name for Google (Token Vault federated exchange)."""

    auth0_slack_connection_name: str = "sign-in-with-slack"
    """Auth0 Slack social connection name (Dashboard → Authentication → Social → Slack)."""

    auth0_github_connection_name: str = "github"
    """Auth0 GitHub social connection name (Dashboard → Authentication → Social → GitHub)."""

    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.0-flash"

    cartesia_api_key: str = ""
    cartesia_voice_id: str = "f786b574-daa5-4673-aa0c-cbe3e8534c02"
    cartesia_model_id: str = "sonic-3"
    cartesia_sample_rate: int = 44100

    # HTTP API (memory + health) — runs alongside the WebSocket server.
    http_host: str = "0.0.0.0"
    http_port: int = 8000

    # Agent memory: Redis short-term buffer + Chroma long-term vectors (+ optional Postgres rows).
    memory_short_term_max: int = 10
    memory_short_term_context_n: int = 10
    """How many recent messages to inject into the prompt (must be <= memory_short_term_max)."""
    memory_chroma_path: str = "./data/chroma"
    memory_chroma_collection: str = "agent_memories"
    memory_retrieval_top_k: int = 8
    """Chroma ANN hits per query (merged + reranked before the prompt)."""
    memory_embedding_model: str = "sentence-transformers/all-MiniLM-L6-v2"
    """Local sentence-transformers model id (downloads on first use)."""


@lru_cache
def get_settings() -> Settings:
    return Settings()
