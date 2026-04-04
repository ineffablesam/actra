import 'dart:convert';

import 'package:actra/chat/controllers/chat_controller.dart';
import 'package:actra/chat/services/websocket_service.dart';
import 'package:actra/core/auth_session_service.dart';
import 'package:actra/core/env.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:get/get.dart';

/// Auth0 login via Authorization Code + PKCE ([flutter_appauth]).
///
/// Dashboard: Application type **Native**, Allowed Callback URLs must include
/// `{AUTH0_SCHEME}://login-callback` (e.g. `com.actra.app://login-callback`).
class Auth0Service extends GetxService {
  final FlutterAppAuth _appAuth = FlutterAppAuth();
  final isBusy = false.obs;

  void _showAuth0Failure(PlatformException e) {
    final combined = '${e.message ?? ''} ${e.details ?? ''}'.toLowerCase();
    if (combined.contains('access_denied') || combined.contains('unauthorized')) {
      Get.snackbar(
        'Auth0 blocked sign-in',
        'Add ${Env.auth0Scheme}://login-callback under Allowed Callback URLs; '
            'authorize this app for API ${Env.auth0Audience} (APIs tab). '
            'Or use a Native app client ID. See actra-backend README.',
        duration: const Duration(seconds: 10),
      );
      return;
    }
    Get.snackbar('Sign in failed', e.message ?? '$e');
  }

  String? _decodeSubFromIdToken(String? idToken) {
    if (idToken == null || idToken.isEmpty) return null;
    final parts = idToken.split('.');
    if (parts.length != 3) return null;
    try {
      final json = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final map = jsonDecode(json) as Map<String, dynamic>;
      return map['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Auth0 HTTP endpoints (iOS AppAuth requires [endSessionEndpoint]; OIDC discovery may omit it).
  AuthorizationServiceConfiguration _auth0ServiceConfiguration() {
    final base = 'https://${Env.auth0Domain}';
    return AuthorizationServiceConfiguration(
      authorizationEndpoint: '$base/authorize',
      tokenEndpoint: '$base/oauth/token',
      endSessionEndpoint: '$base/v2/logout',
    );
  }

  /// Opens the system browser / ASWebAuthenticationSession; returns true if tokens were stored.
  Future<bool> signIn() async {
    final clientId = Env.auth0ClientId.trim();
    if (clientId.isEmpty) {
      Get.snackbar(
        'Configuration',
        'Set AUTH0_CLIENT_ID when building (e.g. --dart-define=AUTH0_CLIENT_ID=...).',
      );
      return false;
    }

    final redirect = '${Env.auth0Scheme}://login-callback';
    final discovery =
        'https://${Env.auth0Domain}/.well-known/openid-configuration';

    isBusy.value = true;
    try {
      final includeAudience =
          Env.auth0RequestAudienceBool && Env.auth0Audience.trim().isNotEmpty;

      final extra = <String, String>{};
      if (includeAudience) {
        extra['audience'] = Env.auth0Audience.trim();
      }

      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientId,
          redirect,
          discoveryUrl: discovery,
          scopes: const ['openid', 'profile', 'email', 'offline_access'],
          // Forces credential screen; otherwise Auth0/browser SSO can skip login on "Get Started".
          promptValues: const ['login'],
          additionalParameters: extra,
        ),
      );

      if (result == null) {
        return false;
      }

      final access = result.accessToken;
      final refresh = result.refreshToken;
      if (access == null || access.isEmpty) {
        Get.snackbar(
          'Sign in',
          'No access token returned. Check Auth0 application settings.',
        );
        return false;
      }
      if (refresh == null || refresh.isEmpty) {
        Get.snackbar(
          'Sign in',
          'No refresh token. Enable offline_access and a refresh-token grant in Auth0.',
        );
        return false;
      }

      final sub = _decodeSubFromIdToken(result.idToken);
      if (sub == null || sub.isEmpty) {
        Get.snackbar('Sign in', 'Could not read user id from id_token.');
        return false;
      }

      await Get.find<AuthSessionService>().saveSession(
        accessToken: access,
        refreshToken: refresh,
        userId: sub,
        idToken: result.idToken,
      );
      return true;
    } on PlatformException catch (e) {
      debugPrint('Auth0 PlatformException: ${e.code} ${e.message} ${e.details}');
      _showAuth0Failure(e);
      return false;
    } catch (e) {
      debugPrint(e.toString());
      Get.snackbar('Sign in failed', '$e');
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  /// Clears local session, notifies backend, ends Auth0 SSO session when id_token is stored.
  Future<void> signOut() async {
    isBusy.value = true;
    try {
      final session = Get.find<AuthSessionService>();
      final idToken = await session.readIdToken();

      if (Get.isRegistered<WebSocketService>()) {
        final ws = Get.find<WebSocketService>();
        ws.sendSessionLogout();
        await ws.disconnect();
      }
      if (Get.isRegistered<ChatController>()) {
        Get.delete<ChatController>(force: true);
      }
      if (Get.isRegistered<WebSocketService>()) {
        Get.delete<WebSocketService>(force: true);
      }

      if (idToken != null &&
          idToken.isNotEmpty &&
          Env.auth0ClientId.trim().isNotEmpty) {
        try {
          await _appAuth.endSession(
            EndSessionRequest(
              idTokenHint: idToken,
              postLogoutRedirectUrl: '${Env.auth0Scheme}://logout-callback',
              serviceConfiguration: _auth0ServiceConfiguration(),
            ),
          );
        } catch (e, st) {
          debugPrint('Auth0 endSession: $e $st');
        }
      }

      await session.clearSession();
    } finally {
      isBusy.value = false;
    }
  }
}
