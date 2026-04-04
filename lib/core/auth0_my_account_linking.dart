import 'package:actra/core/auth_session_service.dart';
import 'package:actra/core/env.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:get/get.dart';

/// Auth0 [My Account API](https://auth0.com/docs/manage-users/my-account-api) +
/// [Connected Accounts for Token Vault](https://auth0.com/docs/secure/call-apis-on-users-behalf/token-vault/connected-accounts-for-token-vault).
///
/// **Tenant setup (required):**
/// 1. Dashboard → **Applications → APIs** → activate **My Account API** (banner). If this
///    step is skipped, `/authorize` returns `access_denied` with *Service not found*
///    for `https://<your-tenant>/me/`.
/// 2. **Auth0 My Account API** → **Application Access** → your Native app → **User access**
///    (not *Client* / M2M — that row is disabled on purpose; My Account API is user-delegated only)
///    → **Authorized** → enable Connected Accounts scopes (`create/read/delete:me:connected_accounts`).
/// 3. For refresh-token exchange without a second browser step: enable **MRRT** on the Native
///    app and add audience `https://<domain>/me/` + scopes to refresh token policies.
/// 4. Native app **Allowed Callback URLs**: `{AUTH0_SCHEME}://my-account-callback` (PKCE fallback).
class Auth0MyAccountLinking extends GetxService {
  Auth0MyAccountLinking() : _dio = Dio();

  final Dio _dio;
  final FlutterAppAuth _appAuth = FlutterAppAuth();
  final isObtainingMyAccountToken = false.obs;

  /// Audience for all My Account API calls and tokens.
  /// See: https://auth0.com/docs/manage-users/my-account-api#audience
  static String audienceForDomain(String auth0Domain) =>
      'https://$auth0Domain/me/';

  String get _audience => audienceForDomain(Env.auth0Domain);

  /// Scopes for Connected Accounts (Token Vault). Must match Dashboard grants.
  static const List<String> connectedAccountsScopes = [
    'openid',
    'profile',
    'offline_access',
    'create:me:connected_accounts',
    'read:me:connected_accounts',
    'delete:me:connected_accounts',
  ];

  static String get _refreshGrantScopeString =>
      connectedAccountsScopes.join(' ');

  String get _pkceRedirect => '${Env.auth0Scheme}://my-account-callback';

  /// 1) MRRT / refresh-token exchange → access token for `audience`.
  /// 2) If that fails, Authorization Code + PKCE with same audience (public Native client).
  Future<String?> obtainAccessTokenForConnectedAccounts() async {
    final session = Get.find<AuthSessionService>();
    final refresh = await session.readRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      debugPrint('[MyAccount] no refresh token');
      Get.snackbar('Sign in required', 'Sign in again to link Google.');
      return null;
    }

    isObtainingMyAccountToken.value = true;
    try {
      final fromRt = await _exchangeRefreshTokenForMyAccount(refresh);
      if (fromRt != null) return fromRt;

      debugPrint(
        '[MyAccount] refresh exchange unavailable; PKCE for audience=$_audience',
      );
      return await _pkceForMyAccount();
    } finally {
      isObtainingMyAccountToken.value = false;
    }
  }

  /// Per docs: `grant_type=refresh_token` + `audience=https://{domain}/me/` + Connected Accounts scopes.
  Future<String?> _exchangeRefreshTokenForMyAccount(String refreshToken) async {
    final url = 'https://${Env.auth0Domain}/oauth/token';
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        url,
        data: {
          'grant_type': 'refresh_token',
          'client_id': Env.auth0ClientId,
          'refresh_token': refreshToken,
          'audience': _audience,
          'scope': _refreshGrantScopeString,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = resp.data;
      final at = data?['access_token'];
      if (at is String && at.isNotEmpty) {
        debugPrint('[MyAccount] access token from refresh OK');
        return at;
      }
      debugPrint('[MyAccount] refresh exchange: missing access_token');
      return null;
    } on DioException catch (e) {
      debugPrint(
        '[MyAccount] refresh exchange failed status=${e.response?.statusCode} '
        'data=${e.response?.data}',
      );
      return null;
    }
  }

  /// PKCE: same Native [client_id] as login; [audience] + Connected Accounts scopes.
  Future<String?> _pkceForMyAccount() async {
    final clientId = Env.auth0ClientId.trim();
    if (clientId.isEmpty) return null;

    final discovery =
        'https://${Env.auth0Domain}/.well-known/openid-configuration';

    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientId,
          _pkceRedirect,
          discoveryUrl: discovery,
          scopes: connectedAccountsScopes,
          additionalParameters: {'audience': _audience},
        ),
      );

      final access = result?.accessToken;
      if (access != null && access.isNotEmpty) return access;

      debugPrint('[MyAccount] PKCE: empty access_token');
      Get.snackbar(
        'Account linking',
        'No access token. Authorize the Native app for My Account API (Application Access).',
      );
      return null;
    } on PlatformException catch (e) {
      debugPrint(
        '[MyAccount] PKCE PlatformException code=${e.code} message=${e.message} '
        'details=${e.details}',
      );
      final msg = '${e.message ?? ''} ${e.details ?? ''}';
      final lower = msg.toLowerCase();
      if (lower.contains('service not found') && lower.contains('/me/')) {
        Get.snackbar(
          'My Account API inactive',
          'Dashboard → Applications → APIs → activate My Account API (Early Access). '
          'Then Application Access: authorize your Native app for Connected Accounts scopes.',
          duration: const Duration(seconds: 14),
        );
        return null;
      }
      // Auth0: Application Access — this Native client has no client grant for My Account API.
      if (lower.contains('not authorized to access resource server')) {
        Get.snackbar(
          'Authorize User access (not Client)',
          'My Account API ignores M2M. APIs → Auth0 My Account API → Application Access → '
          'Actra → User access → Authorized → Connected Accounts scopes.',
          duration: const Duration(seconds: 16),
        );
        return null;
      }
      if (lower.contains('access_denied') || lower.contains('unauthorized')) {
        Get.snackbar(
          'Account linking blocked',
          'Add $_pkceRedirect to Allowed Callback URLs; authorize My Account API for this app.',
          duration: const Duration(seconds: 10),
        );
        return null;
      }
      Get.snackbar('Account linking', e.message ?? '$e');
      return null;
    } catch (e) {
      debugPrint('[MyAccount] PKCE error: $e');
      Get.snackbar('Account linking failed', '$e');
      return null;
    }
  }
}
