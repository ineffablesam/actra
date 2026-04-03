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

  static const String auth0ClientId = String.fromEnvironment(
    'AUTH0_CLIENT_ID',
    defaultValue: '',
  );

  static const String auth0Audience = String.fromEnvironment(
    'AUTH0_AUDIENCE',
    defaultValue: 'https://actra-api',
  );

  static const String auth0Scheme = String.fromEnvironment(
    'AUTH0_SCHEME',
    defaultValue: 'com.actra.app',
  );

  /// Dev placeholder until Auth0 login persists a real subject.
  static const String devUserId = String.fromEnvironment(
    'ACTRA_USER_ID',
    defaultValue: 'auth0|actra-dev',
  );

  /// **Dev only:** Auth0 refresh token for `session_auth` (do not ship in production builds).
  static const String devAuth0RefreshToken = String.fromEnvironment(
    'AUTH0_REFRESH_TOKEN',
    defaultValue: '',
  );
}
