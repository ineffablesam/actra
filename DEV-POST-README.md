# Devpost submission — Auth0 Token Vault Hackathon


## Project name *(60 characters max)*

**Actra — Voice AI with Auth0 Token Vault**

*(Short alternative: **Actra** — 5 characters if Devpost wants a minimal title.)*

---

## Elevator pitch *(200 characters max)*

**Actra showcases Auth0 Token Vault for voice AI: OIDC login, Connected Accounts, server-side JWT exchange for Gmail/Calendar/Slack—no provider secrets in-app—plus Gemini, Cartesia & Flutter.**

*(189 characters — room to tweak wording in Devpost’s counter.)*

---

## Project details — public project page

### Project Story — *About the project*

#### Why Auth0 Token Vault (for everyone)

This project is a **submission for the Auth0 Token Vault hackathon**. The core idea: a voice assistant should be able to **read your mail, check your calendar, or use Slack** only when *you* connect those accounts—and those connections should be **managed by identity infrastructure**, not by copying API keys into a mobile app.

**Auth0** is the front door: users sign in with your tenant (OIDC). **Connected Accounts** (My Account API) lets them link **Google** and **Slack** in a browser flow you trust. **Token Vault** stores the federated tokens. Our **Python backend** then uses Auth0’s **access-token exchange** (with a **confidential API client** linked to your Custom API) to swap the user’s **Auth0 API JWT** for short-lived **Google** or **Slack** access tokens and call Gmail, Calendar, or Slack APIs **server-side**.

That means: **no Google client secrets in Flutter**, no Slack bot tokens in the client, and a clear story for judges—**Token Vault is how the assistant gets real work done safely.**

---

#### For everyone

**What it is.** Actra is a voice-first assistant. You speak; it understands; when a task needs Gmail, Calendar, or Slack, the app only proceeds after Auth0-backed connections exist. Replies stream as text and natural speech. The UI is **Flutter**; intelligence and Token Vault exchange run on **your backend**.

**What inspired it.** Hackathon assistants should prove **secure delegated access**: the AI acts *as the user* with OAuth-connected tools, not with a shared service account. Token Vault makes that pattern first-class—so we centered the product on **login vs. connect accounts** as two distinct steps, exactly as Auth0 documents for Token Vault.

**What we learned.** **Voice UX** and **identity UX** intersect: users must understand *why* a sheet appeared (“connect Google”) without feeling blocked. Wiring **Native app** login, **Custom API** audience JWTs, **Token Vault grant** on a **confidential client**, and **deep links** for Connected Accounts taught us the real-world shape of Auth0’s split between public mobile clients and server-side exchange.

**How we built it (plain English).** **Auth0** handles sign-in and stores federated tokens. The app opens **Connected Accounts** when the server says **`connections_required`**. After links exist, the user’s session includes an **API JWT**; the WebSocket sends **`session_auth`** so the backend can exchange for provider tokens and fetch context. **Gemini** drafts answers; **Cartesia** speaks them; **Whisper** on-device handles speech-to-text.

**Challenges.** Aligning **Auth0 Dashboard** settings (Token Vault on the connection, scopes for Gmail/Calendar/Slack, Custom API client authorized for exchange) with **Flutter** callbacks and **PKCE** fallbacks for My Account took iteration—as did streaming **parallel TTS and agent text** without breaking the mic path.

---

#### For technical readers — Auth0 first

**Auth0 architecture (this hackathon’s centerpiece).**

| Piece | Role in Actra |
|--------|----------------|
| **Native application** | Flutter app — `flutter_appauth`, PKCE; **cannot** use Token Vault grant on the public client (by design). |
| **Custom API** (`https://actra-api`) | **Audience** for JWTs used on the WebSocket (`session_auth`); backend verifies signature/issuer/audience. |
| **Confidential “Token Exchange” client** | Linked under **APIs → Actra API → Applications**; has **Token Vault** grant; holds **client secret** only on the server. |
| **Access-token exchange** | Backend exchanges the user’s **Auth0 access token** (API audience) for **Google** / **Slack** access via Token Vault—not refresh-token exchange. |
| **Connected Accounts** | User connects Google/Slack so Vault has federated tokens; Flutter uses My Account / browser flows + deep links. |
| **`connections_required`** | When Gemini intent needs `google_gmail`, `google_calendar`, or `slack` but the session cache says they’re missing, server emits this WebSocket event; UI prompts connection; **pending task** can resume after link. |

**Frontend (Flutter)** — **flutter_appauth** + **flutter_secure_storage**; **`session_auth`** after WebSocket connect; **Wolt** sheet / connection UX when `connections_required` fires; **web_socket_channel**, **flutter_soloud** (TTS PCM), **flutter_whisper_kit** (STT). See repo `auth0_my_account_linking`, `connected_accounts_service`, `env.dart` for audience and URLs.

**Backend (Python)** — **Auth0 JWT** verification (`auth0_jwt_service`); **`TokenVaultService`** wraps exchange errors into safe WebSocket **`ErrorEvent`** codes; **Gmail**, **Calendar**, **Slack** services consume exchanged tokens only. **Gemini** intent + draft; **Cartesia** stream TTS; **Redis** / **Chroma** memory; **Postgres** users; **FastAPI** memory routes.

**Security narrative for judges.** Long-lived **provider credentials stay in Auth0 Token Vault**; the mobile app holds **Auth0 tokens** for your API, not Google/Slack secrets. The server is the only place that performs **exchange + API calls**—matching Auth0’s recommended split for Native + Vault.

**Architecture (Auth0 in the loop).**

```text
[Flutter] ── OIDC / refresh ──► [Auth0]     Connected Accounts ──► Token Vault
     │                              │                                      │
     │ session_auth (API JWT)       │                                      │
     └────────────────── WebSocket ──┼──► [Python] ── token exchange ──────┘
                                            │              │
                                            ▼              ▼
                                    Gmail / Calendar / Slack APIs
                                            │
                    Whisper → intent → Gemini draft → Cartesia → PCM → Flutter
```

---

#### Memory & context *(optional LaTeX)*

Long-term recall uses embedding similarity (top-\(k\) retrieval + short-term buffer in prompt). Memory is orthogonal to Auth0; identity is still the trust boundary for **all** provider API access.

---

*Trim sections to fit Devpost field limits; keep the **Auth0 Token Vault** and **access-token exchange** sentences in any shortened “About” blurb.*
