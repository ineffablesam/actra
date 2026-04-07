# Actra backend

Async **Python** service for the Actra assistant: **WebSocket** agent pipeline (Gemini intent + drafting, Cartesia TTS), **Auth0** JWT verification, **Token Vault** federated token exchange for **Gmail**, **Google Calendar**, and **Slack**, **Redis** session state, **PostgreSQL** users, **Chroma** + **sentence-transformers** long-term memory.

The **Flutter client** lives in the repository root (`../`); point it at this host’s WebSocket and HTTP ports (see `lib/core/env.dart`).

---

## What runs

| Mode | WebSocket | HTTP (FastAPI) |
|------|-----------|----------------|
| **`ENVIRONMENT=development`** (default) | Standalone server on `WS_HOST`:`WS_PORT` (default **8765**) | Uvicorn on `HTTP_HOST`:`HTTP_PORT` (default **8000**) — `/health`, memory routes, `/users/me/connected-accounts`, etc. |
| **`ENVIRONMENT=production`** | Mounted at **`/ws`** on the same FastAPI app (single process) | Same port as HTTP |

Implementation: `src/main.py` + `src/api/app.py`.

---

## Requirements

- **Docker Compose** (recommended): Postgres 16, Redis 7, backend image — see `docker-compose.yml`
- Or **Python 3.12**, **Redis**, **Postgres**, and dependencies from `requirements.txt`
- API keys: **`GEMINI_API_KEY`**, **`CARTESIA_API_KEY`**
- **Auth0** tenant configured for your apps (below)

---

## Configuration

Copy **`.env.example`** → **`.env`** and fill values. Important variables:

| Variable | Role |
|----------|------|
| `REDIS_URL`, `DATABASE_URL` | Session cache, optional user upsert + memory tables |
| `REQUIRE_AUTH0_JWT` | If `true`, `session_auth` must send a valid Auth0 **access token**; agent events must match JWT `sub` |
| `AUTH0_DOMAIN`, `AUTH0_AUDIENCE` | Issuer/audience for `Auth0JwtService` (RS256 via JWKS) |
| `AUTH0_TOKEN_EXCHANGE_CLIENT_ID` / `AUTH0_TOKEN_EXCHANGE_CLIENT_SECRET` | Confidential **Custom API** client used only for **Token Vault** `/oauth/token` exchange |
| `AUTH0_GOOGLE_CONNECTION_NAME`, `AUTH0_SLACK_CONNECTION_NAME` | Auth0 **social connection names** (must match Dashboard slugs) |
| `GEMINI_*`, `CARTESIA_*` | Model and voice |
| `MEMORY_*` | Chroma path, short-term limits, embedding model, retrieval `MEMORY_RETRIEVAL_TOP_K` (default **8** for the transcript retrieval path) |

On first run, **sentence-transformers** may download `MEMORY_EMBEDDING_MODEL` (see `src/config.py`).

---

## Auth0 (backend)

### Applications

| Piece | Purpose |
|-------|---------|
| **Custom API** | Identifier = `AUTH0_AUDIENCE` (e.g. `https://actra-api`). Mobile login requests tokens for this audience; backend verifies JWTs. |
| **Confidential client** linked under **APIs → your API → Add Application** | `AUTH0_TOKEN_EXCHANGE_*`. Enable **Token Vault** grant. Used for **[access-token exchange](https://auth0.com/docs/secure/tokens/token-vault/access-token-exchange-with-token-vault)** — **subject** = user’s Auth0 API access token, **not** refresh-token exchange. |
| **Native app** (Flutter) | Not configured in this repo; lives in the mobile app. Public clients **cannot** use the Token Vault grant — that stays on the confidential client. |

### Connections

- **Google** (`AUTH0_GOOGLE_CONNECTION_NAME`, often `google-oauth2`): Token Vault + scopes for Gmail/Calendar as required by your Auth0 and Google connection settings.
- **Slack** (`AUTH0_SLACK_CONNECTION_NAME`): connection name must match **Authentication → Social → Slack**; enable Token Vault / Connected Accounts per Auth0 docs.

### Runtime behavior

- **`session_auth`**: Verifies access token; stores `sub` and token for `TokenVaultService.get_access_token(...)`.
- **Federated exchange**: `src/services/token_vault_service.py` calls Auth0 with grant `urn:auth0:params:oauth:grant-type:token-exchange:federated-connection-access-token`, caches short-lived provider tokens in Redis.

**Troubleshooting (common Auth0 responses)**

- `Token Vault is not enabled for the provided connection` → Enable Connected Accounts / Token Vault on that **connection** in the Dashboard.
- `federated_connection_refresh_token_not_found` → No vault entry for that user/connection; complete **Connected Accounts** in the app and/or sign out and sign in again after Dashboard changes.

---

## Run (Docker)

```bash
cp .env.example .env
# Edit .env — use service hostnames from .env.example for redis/postgres inside Compose

docker compose up --build
```

**Published ports (host)**

| Port | Service |
|------|---------|
| **8765** | WebSocket (dev: standalone) |
| **8000** | FastAPI |
| **5432** | Postgres |
| **6379** | Redis |

`docker compose` sets `MEMORY_CHROMA_PATH=/data/chroma` with a named volume. Optional: `docker compose --profile dev up` — Redis Commander on **8081**.

---

## Run (local, no Docker)

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
# Load .env (direnv, or export vars)
PYTHONPATH=. python -m src.main
```

---

## HTTP API (default port 8000)

- `GET /health` — liveness
- `GET /debug` — environment name
- `GET /users/me/connected-accounts` — Redis-tracked providers (requires auth per `REQUIRE_AUTH0_JWT`)
- `DELETE /users/me/connected-accounts/{provider}` — disconnect + clear cached vault tokens for that provider
- `POST /memory/save`, `GET /memory/search` — memory debugging (`top_k` query param; default **3** on the route)

---

## Agent memory

- **Short term**: Redis buffer (`memory_short_term_max` / `memory_short_term_context_n`, defaults **10**).
- **Long term**: Chroma at `MEMORY_CHROMA_PATH`, collection `memory_chroma_collection`; retrieval uses `MEMORY_RETRIEVAL_TOP_K` (default **8**) in the transcript pipeline (`src/memory/retrieval.py`).

---

## Tests

```bash
PYTHONPATH=. pytest tests/ -q
```

Structured logs go to stdout (JSON); **tokens are not logged** — only safe metadata (e.g. token length) where applicable.
