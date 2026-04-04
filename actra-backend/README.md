# Actra backend

Python WebSocket server for the Actra voice assistant: Gemini intent + drafting, Auth0 JWT verification + PostgreSQL users, Auth0 Token Vault token exchange (Google APIs), Cartesia TTS streaming, Redis session state.

## Prerequisites

- Docker / Docker Compose (recommended), or Python 3.12 + Redis locally
- API keys: `GEMINI_API_KEY`, `CARTESIA_API_KEY`
- Auth0: **Native** app for login (Flutter), **Custom API** (`https://actra-api`), and a **Custom API Client** for Token Vault (see table below). Native apps are **public clients**, so the Dashboard will **not** offer the Token Vault grant on the Native application — that is expected. This backend uses **[access token exchange](https://auth0.com/docs/secure/tokens/token-vault/access-token-exchange-with-token-vault)** (subject = user’s Auth0 API JWT), not refresh-token exchange.

## Auth0 applications (your tenant)

| What | Where in Dashboard | Used for |
|------|-------------------|----------|
| **Actra** (Native) | Applications | **Flutter** — `AUTH0_CLIENT_ID`; login + refresh token; **cannot** enable Token Vault grant on this app. |
| **Actra API** | APIs → Create API, identifier `https://actra-api` | JWT **audience** (`AUTH0_AUDIENCE`). |
| **Custom API Client** | APIs → **Actra API** → **Add Application** → create/configure | **Backend** — `AUTH0_TOKEN_EXCHANGE_CLIENT_ID` / `AUTH0_TOKEN_EXCHANGE_CLIENT_SECRET`. This confidential client is **linked to the API** and has the Token Vault grant; it exchanges the user’s **access token** (not the refresh token) for Google tokens. |

Secrets (**client secrets**) live only in `.env` or Auth0 Dashboard — never commit them.

## Product auth flow (what the app is designed to do)

This matches Auth0’s split between **login** and **Connected Accounts → Token Vault** ([Connected Accounts for Token Vault](https://auth0.com/docs/secure/tokens/token-vault/connected-accounts-for-token-vault), [Access token exchange with Token Vault](https://auth0.com/docs/secure/tokens/token-vault/access-token-exchange-with-token-vault)).

1. **Login only (splash / “Get Started”)** — User signs in with Auth0 (`openid`, `profile`, `email`, `offline_access` + your **Custom API** audience). No Gmail connection is required here; this establishes the Auth0 user session and API JWT used for `session_auth` and the WebSocket.
2. **Inside the app (when needed)** — If the assistant needs Gmail/Calendar, the backend sends **`connections_required`** over the WebSocket. The Flutter **connection panel** then runs **Connected Accounts** (My Account API: connect → browser → complete) so Google tokens are **stored in Token Vault** for that user/connection—not a fake “connected” flag.
3. **Server-side Gmail/Calendar** — The Python backend uses the **Token Vault** grant on the **Custom API Client** to exchange the user’s **Auth0 access token** for a **Google access token** and call Gmail/Calendar APIs.

**Auth0 MCP:** `auth0_list_applications` / `auth0_get_application` / `auth0_update_application` can manage the **Native** app (callbacks, `refresh_token` including MRRT `policies`). Use a **Management API** token (`audience` = `https://<tenant>/api/v2/`) for updates—not a token for `https://actra-api`.

## Auth0 (dashboard steps the MCP cannot fully automate)

The Auth0 MCP created:

- **Tenant**: configure `AUTH0_DOMAIN` in `.env`.
- **Actra** (Native): **Flutter** — `AUTH0_CLIENT_ID`, callbacks, `offline_access` for refresh token.
- **Actra API**: identifier `https://actra-api` — `AUTH0_AUDIENCE`; Flutter requests tokens with this audience.
- **Custom API Client**: under **APIs → Actra API → Applications**, add the application Auth0 creates for Token Vault; copy its client id and secret into `AUTH0_TOKEN_EXCHANGE_*`.

You still need to **manually** in the Auth0 Dashboard:

1. Enable **Token Vault** / federated connection tokens for your tenant (per Auth0’s Token Vault docs).
2. On the **Custom API Client** used for exchange: **Advanced → Grant Types** → enable **Token Vault** (and ensure the client is confidential).
3. Add a **Google** social connection with scopes: `gmail.send`, `gmail.readonly`, `calendar.readonly`, `calendar.events`, and enable **store tokens** / federated access tokens on that connection.
4. Map `AUTH0_GOOGLE_CONNECTION_NAME` (default `google-oauth2`) to your connection name.

**If token exchange returns** `Token Vault is not enabled for the provided connection`: the **Google** connection itself is not configured for Token Vault. In **Authentication → Social → google-oauth2** (or your connection name), enable **Connected Accounts** for Token Vault and the Gmail/Calendar scopes (see [Connected Accounts for Token Vault](https://auth0.com/docs/secure/tokens/token-vault/connected-accounts-for-token-vault)). “Authentication” and “Connected Accounts” can both be enabled so users still log in with Google while tokens are stored in Token Vault. Ensure your tenant has the Token Vault feature (Auth0 may require enabling it for the tenant). If **Security → Multi-factor Authentication** policy is **Always**, change it for dev or Token Vault can block token retrieval (see Auth0 Configure Token Vault).

**If token exchange returns** `federated_connection_refresh_token_not_found` (HTTP 401): Auth0’s Token Vault has **no stored Google refresh token** for this user on that connection—often because they logged in **before** Connected Accounts / token storage was enabled, or only a login identity exists without a vault entry. Fix: sign **out** of the app and sign **in** again after Dashboard changes; if needed, use Auth0’s **Connected Accounts** / My Account API flow so Google tokens are stored (not only Universal Login).

Save client secrets via the Dashboard or by re-running the Auth0 MCP `auth0_save_credentials_to_file` tool into a **gitignored** file (never commit secrets).

## Cartesia

Documentation lists **sonic-3** with a featured voice ID (see Cartesia quickstart). Defaults in `.env.example` match the public examples; replace `CARTESIA_VOICE_ID` with a voice from [play.cartesia.ai/voices](https://play.cartesia.ai/voices) if you prefer.

## Run (Docker)

```bash
cp .env.example .env
# fill .env

docker compose up --build
```

WebSocket listens on **8765**. **PostgreSQL** is on **5432** (default credentials in `.env.example`). Redis is on **6379**. With `docker compose --profile dev up`, Redis Commander is on **8081**.

Set `DATABASE_URL` and `REQUIRE_AUTH0_JWT` in `.env`. The backend creates the `users` table on startup and upserts when `session_auth` includes a valid Auth0 access token.

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

### Auth0 + `session_auth`

1. Create a **Native** application in Auth0. Add **Allowed Callback URLs**: `com.actra.app://login-callback`, `com.actra.app://my-account-callback` (PKCE fallback for My Account when MRRT is not set), and `com.actra.app://connected-accounts-callback` (Google handoff). Use the same scheme as `AUTH0_SCHEME`.
2. Enable **Refresh Token** rotation / grant as needed so mobile receives a refresh token with `offline_access`.
3. Run the app with your **Regular Web / Native client id** and API audience:

```bash
flutter run --dart-define=WS_URL=ws://127.0.0.1:8765 \
  --dart-define=AUTH0_CLIENT_ID=YOUR_NATIVE_CLIENT_ID \
  --dart-define=AUTH0_DOMAIN=your-tenant.us.auth0.com \
  --dart-define=AUTH0_AUDIENCE=https://actra-api
```

**Get Started** on the splash screen runs Auth0 login (`flutter_appauth`). Tokens are stored in **flutter_secure_storage**. After the WebSocket connects, the app sends **`session_auth`** with **access_token** (JWT verified by the backend) and **refresh_token** (for Google Token Vault exchange).

**Authorize the app for your API** (fixes `access_denied` / `Unauthorized` when requesting `audience`): **Applications** → **Actra** → **APIs** tab → enable / **Authorize** the API whose identifier matches `AUTH0_AUDIENCE` (e.g. `https://actra-api`). If that tab is missing, use **APIs** → select your API → **Machine to Machine** is only for M2M; for mobile you need the application authorized under the API (Auth0 UI varies by version—search “Authorize Application API Auth0”). **Regular Web** apps sometimes reject custom URL schemes; if callbacks still fail, create an **Native** application and use its Client ID.

**Local dev without API audience:** `flutter run --dart-define=AUTH0_REQUEST_AUDIENCE=false` and set **`AUTH0_AUDIENCE=`** empty in the backend `.env` so JWT verification does not require that audience (still validates issuer/signature).

**Connected Accounts + My Account API (`invalid_target` / “requested audience is not authorized by the refresh token policy”):** Prefer exchanging the login **refresh token** for audience `https://<AUTH0_DOMAIN>/me/` (requires **MRRT** + `refresh_token.policies` as above). If that fails, the app **falls back** to a second **PKCE** sign-in with audience `https://<AUTH0_DOMAIN>/me/` and callback `…/my-account-callback` — **Applications** → your Native app → **APIs** → authorize **My Account API** with Connected Accounts scopes. **Allowed Callback URLs** must include `com.actra.app://my-account-callback` (or your `AUTH0_SCHEME`).

Backend logs include `session_auth_received`, `user_upserted`, `intent_analyzed`, `token_exchange_*`, etc. — **tokens are never logged**, only lengths and safe error hints.

## Tests

```bash
PYTHONPATH=. pytest tests/ -q
```
