/// Build-time configuration. Override with `--dart-define=KEY=value`.
abstract final class Env {
  /// WebSocket backend. With **Docker Compose**, `actra-backend` publishes **8765** to the host.
  /// Use `ws://192.168.1.157:8765` from the iOS Simulator / desktop; on **Android emulator** use
  /// `ws://192.168.1.157:8765` (emulator’s alias for your machine). Physical device: use your LAN IP.
  static const String wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'ws://192.168.1.157:8765',
  );

  /// HTTP base for the FastAPI memory API (`/health`, `/memory/search`). Docker Compose publishes **8000**.
  /// Same Android rule: `http://10.0.2.2:8000` on emulator, `http://127.0.0.1:8000` on simulator.
  /// Leave empty if you do not call the HTTP API from the app.
  static const String memoryApiBaseUrl = String.fromEnvironment(
    'MEMORY_API_BASE_URL',
    defaultValue: 'http://192.168.1.157:8000',
  );

  /// When true, sends `X-User-Id` with the memory/linked-accounts HTTP API (use with backend `REQUIRE_AUTH0_JWT=false`).
  static const String backendTrustUserIdHeader = String.fromEnvironment(
    'BACKEND_TRUST_USER_ID_HEADER',
    defaultValue: 'false',
  );

  static bool get backendTrustUserIdHeaderBool =>
      backendTrustUserIdHeader.toLowerCase() == 'true';

  static const String auth0Domain = String.fromEnvironment(
    'AUTH0_DOMAIN',
    defaultValue: 'dev-0uu1-z5v.us.auth0.com',
  );

  /// Native app client ID from Auth0 Dashboard.
  static const String auth0ClientId = String.fromEnvironment(
    'AUTH0_CLIENT_ID',
    defaultValue: 'YsC2d2MKodUUJo7sdH60yu9tbPEgtUgR',
  );

  static const String auth0Audience = String.fromEnvironment(
    'AUTH0_AUDIENCE',
    defaultValue: 'https://actra-api',
  );

  /// When `true` (default), sends `audience` to Auth0. If login fails with
  /// `access_denied` / Unauthorized, authorize this app for your API in the Auth0
  /// Dashboard (Applications → Actra → APIs), or set to `false` and clear
  /// `AUTH0_AUDIENCE` on the backend for local dev only.
  static const String auth0RequestAudience = String.fromEnvironment(
    'AUTH0_REQUEST_AUDIENCE',
    defaultValue: 'true',
  );

  static bool get auth0RequestAudienceBool =>
      auth0RequestAudience.toLowerCase() != 'false';

  /// Must match Auth0 Allowed Callback URLs: `{auth0Scheme}://login-callback`
  static const String auth0Scheme = String.fromEnvironment(
    'AUTH0_SCHEME',
    defaultValue: 'com.actra.app',
  );

  /// Same as backend `AUTH0_GOOGLE_CONNECTION_NAME` (Auth0 Dashboard → Social → Google).
  static const String auth0GoogleConnectionName = String.fromEnvironment(
    'AUTH0_GOOGLE_CONNECTION_NAME',
    defaultValue: 'google-oauth2',
  );

  /// **Must match** Auth0 → Authentication → Social → [Slack] → **name** (slug), e.g. `sign-in-with-slack`
  /// or a custom name. If wrong, `/me/v1/connected-accounts/connect` returns 404.
  /// See [Slack + Token Vault](https://auth0.com/ai/docs/integrations/slack).
  static const String auth0SlackConnectionName = String.fromEnvironment(
    'AUTH0_SLACK_CONNECTION_NAME',
    defaultValue: 'sign-in-with-slack',
  );
}
