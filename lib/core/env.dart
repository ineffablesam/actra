/// Build-time configuration. Override with `--dart-define=KEY=value`.
abstract final class Env {
  static const String wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'ws://192.168.1.157:8765',
  );

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
}
