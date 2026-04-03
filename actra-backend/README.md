# Actra backend

Python WebSocket server for the Actra voice assistant: Gemini intent + drafting, Auth0 Token Vault token exchange (Google APIs), Cartesia TTS streaming, Redis session state.

## Prerequisites

- Docker / Docker Compose (recommended), or Python 3.12 + Redis locally
- API keys: `GEMINI_API_KEY`, `CARTESIA_API_KEY`
- Auth0: Regular Web Application, Custom API (`https://actra-api`), and a **Machine to Machine** (non-interactive) application used as `AUTH0_CUSTOM_API_CLIENT_*` for token exchange against Google connections

## Auth0 applications (your tenant)

| Dashboard name | Type | Client ID | Used where |
|----------------|------|-----------|------------|
| **Actra** | Regular Web Application | `YsC2d2MKodUUJo7sdH60yu9tbPEgtUgR` | **Flutter** — `flutter_appauth`, `--dart-define=AUTH0_CLIENT_ID=...`, callback URLs for your bundle ID / scheme. |
| **Actra Backend Token Exchange** | Machine to Machine | `N63Yb5OqoOWrlUCTbA9i64rj9NPCFCnU` | **This backend** — `AUTH0_CUSTOM_API_CLIENT_ID` / `AUTH0_CUSTOM_API_CLIENT_SECRET` in `.env` for Google token exchange. |

Secrets (**client secrets**) live only in `.env` or Auth0 Dashboard — never commit them.

## Auth0 (dashboard steps the MCP cannot fully automate)

The Auth0 MCP created:

- **Tenant**: configure `AUTH0_DOMAIN` in `.env`.
- **Actra** (Regular Web Application): use for mobile / `flutter_appauth` — set `AUTH0_CLIENT_ID` / `AUTH0_CLIENT_SECRET` and callback URLs for your app.
- **Actra API** Custom Resource Server: identifier `https://actra-api` — set `AUTH0_AUDIENCE`.
- **Actra Backend Token Exchange** (non-interactive client): set `AUTH0_CUSTOM_API_CLIENT_ID` and `AUTH0_CUSTOM_API_CLIENT_SECRET`.

You still need to **manually** in the Auth0 Dashboard:

1. Enable **Token Vault** / federated connection tokens for your tenant and applications (per Auth0’s current Token Vault docs).
2. Add a **Google** social connection with scopes: `gmail.send`, `gmail.readonly`, `calendar.readonly`, `calendar.events`, and enable **store tokens** / federated access tokens on that connection.
3. Map `AUTH0_GOOGLE_CONNECTION_NAME` (default `google-oauth2`) to your connection name.

Save client secrets via the Dashboard or by re-running the Auth0 MCP `auth0_save_credentials_to_file` tool into a **gitignored** file (never commit secrets).

## Cartesia

Documentation lists **sonic-3** with a featured voice ID (see Cartesia quickstart). Defaults in `.env.example` match the public examples; replace `CARTESIA_VOICE_ID` with a voice from [play.cartesia.ai/voices](https://play.cartesia.ai/voices) if you prefer.

## Run (Docker)

```bash
cp .env.example .env
# fill .env

docker compose up --build
```

WebSocket listens on **8765**. Redis is on **6379**. With `docker compose --profile dev up`, Redis Commander is on **8081**.

## Run (local)

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export $(grep -v '^#' .env | xargs)   # or use direnv
PYTHONPATH=. python -m src.main
```

## Flutter client

The app plays TTS with **[flutter_soloud](https://pub.dev/packages/flutter_soloud)** buffer streams (`f32le` PCM). Version **^3.5.4** matches Dart **3.10**; upgrade to **^4.0.0** when you move to Dart **3.11+**.

Point the app at your server, for example:

```bash
flutter run --dart-define=WS_URL=ws://127.0.0.1:8765
```

### `session_auth` (fixes `AUTH_REQUIRED`)

After the WebSocket connects, the app sends **`session_auth`** with your Auth0 **refresh token** so the backend can exchange it for Google access tokens.

- **Production:** implement Auth0 login with `flutter_appauth`, then call `AuthSessionService.saveSession(refreshToken: …, userId: …)` (tokens are stored in **flutter_secure_storage**).
- **Local dev only:** pass a refresh token once (never commit or ship this):
  ```bash
  flutter run --dart-define=WS_URL=ws://127.0.0.1:8765 \
    --dart-define=AUTH0_REFRESH_TOKEN='your-auth0-refresh-token' \
    --dart-define=ACTRA_USER_ID='auth0|your-sub'
  ```

Backend logs (JSON to stdout) include `session_auth_received`, `session_refresh_token_miss`, `auth_required_no_refresh_token`, `intent_analyzed`, `token_exchange_*`, etc. — **tokens are never logged**, only lengths and safe error hints.

## Tests

```bash
PYTHONPATH=. pytest tests/ -q
```
