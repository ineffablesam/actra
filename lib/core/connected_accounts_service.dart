import 'dart:convert';

import 'package:actra/core/auth0_my_account_linking.dart';
import 'package:actra/core/connected_accounts_permissions.dart';
import 'package:actra/core/env.dart';
import 'package:dio/dio.dart';
import 'package:actra/core/connected_accounts_external_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// [Connected Accounts for Token Vault](https://auth0.com/docs/secure/call-apis-on-users-behalf/token-vault/connected-accounts-for-token-vault):
/// `connect` → browser → `complete`. Requires a My Account API access token
/// ([Auth0MyAccountLinking]).
class ConnectedAccountsService extends GetxService {
  final Dio _dio = Dio();
  final _uuid = const Uuid();

  String get _connectRedirect =>
      '${Env.auth0Scheme}://connected-accounts-callback';

  /// Opens the browser to link Google; stores tokens in Auth0 Token Vault on success.
  Future<bool> connectGoogleConnection(
    String provider, {
    bool showSuccessSnack = true,
  }) async {
    debugPrint('[ConnectedAccounts] connectGoogleConnection start provider=$provider');
    return _runConnectFlow(
      connection: Env.auth0GoogleConnectionName,
      scopes: ConnectedAccountsPermissions.scopesForProvider(provider),
      snackTitle: 'Sign in with Google',
      snackBody: 'Safari will open — return here after you finish.',
      successMessage: 'Google account linked to Token Vault.',
      invalidConnectHint:
          'Invalid connect response. Check Auth0 Connected Accounts on the Google connection.',
      showSuccessSnack: showSuccessSnack,
    );
  }

  /// Link Slack (Sign in with Slack) for Token Vault — same flow as Google, different connection.
  ///
  /// Scopes must match what your Slack app and Auth0 Slack connection allow
  /// ([Auth0 Slack](https://auth0.com/ai/docs/integrations/slack)).
  Future<bool> connectSlackConnection({bool showSuccessSnack = true}) async {
    debugPrint(
      '[ConnectedAccounts] connectSlackConnection connection=${Env.auth0SlackConnectionName}',
    );
    return _runConnectFlow(
      connection: Env.auth0SlackConnectionName,
      scopes: ConnectedAccountsPermissions.scopesForProvider('slack'),
      snackTitle: 'Sign in with Slack',
      snackBody: 'Safari will open — return here after you finish.',
      successMessage: 'Slack workspace linked to Token Vault.',
      invalidConnectHint:
          'Invalid connect response. Check Auth0 Connected Accounts on the Slack connection.',
      showSuccessSnack: showSuccessSnack,
    );
  }

  Future<bool> _runConnectFlow({
    required String connection,
    required List<String> scopes,
    required String snackTitle,
    required String snackBody,
    required String successMessage,
    required String invalidConnectHint,
    bool showSuccessSnack = true,
  }) async {
    final myAccountAt =
        await Get.find<Auth0MyAccountLinking>().obtainAccessTokenForConnectedAccounts();
    if (myAccountAt == null) {
      debugPrint('[ConnectedAccounts] abort: My Account token unavailable');
      return false;
    }

    final state = _uuid.v4();
    final connectUrl = 'https://${Env.auth0Domain}/me/v1/connected-accounts/connect';
    debugPrint(
      '[ConnectedAccounts] POST connect connection=$connection redirect=$_connectRedirect',
    );
    try {
      final connectResp = await _dio.post<Map<String, dynamic>>(
        connectUrl,
        data: jsonEncode({
          'connection': connection,
          'redirect_uri': _connectRedirect,
          'state': state,
          'scopes': scopes,
        }),
        options: Options(
          headers: {
            'Authorization': 'Bearer $myAccountAt',
            'Content-Type': 'application/json',
          },
        ),
      );

      final data = connectResp.data;
      if (data == null) {
        debugPrint('[ConnectedAccounts] connect: empty JSON body');
        Get.snackbar('Connect failed', 'Empty response from Auth0.');
        return false;
      }

      final connectUri = data['connect_uri'] as String? ?? '';
      final params = data['connect_params'];
      String? ticket;
      if (params is Map<String, dynamic>) {
        ticket = params['ticket'] as String?;
      }
      final authSession = data['auth_session'] as String? ?? '';

      if (connectUri.isEmpty || ticket == null || ticket.isEmpty) {
        debugPrint(
          '[ConnectedAccounts] connect: bad connect_uri/ticket '
          'connectUriEmpty=${connectUri.isEmpty} ticketEmpty=${ticket == null || ticket.isEmpty}',
        );
        Get.snackbar('Connect failed', invalidConnectHint);
        return false;
      }

      final baseConnect = Uri.parse(connectUri);
      final q = Map<String, String>.from(baseConnect.queryParameters);
      q['ticket'] = ticket;
      final startUri = baseConnect.replace(queryParameters: q);
      debugPrint('[ConnectedAccounts] opening browser auth url=${startUri.toString()}');
      Get.snackbar(
        snackTitle,
        snackBody,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
      );

      String? callback;
      try {
        callback =
            await openExternalBrowserAndAwaitConnectedAccountsCallback(startUri.toString());
      } catch (e, st) {
        debugPrint('[ConnectedAccounts] external browser auth failed: $e\n$st');
        return false;
      }
      if (callback == null || callback.isEmpty) {
        debugPrint('[ConnectedAccounts] user cancelled or empty callback');
        return false;
      }

      debugPrint('[ConnectedAccounts] callback received: $callback');
      final cb = Uri.parse(callback);
      String? connectCode = cb.queryParameters['connect_code'];
      if ((connectCode == null || connectCode.isEmpty) && cb.fragment.isNotEmpty) {
        connectCode = Uri.splitQueryString(cb.fragment)['connect_code'];
      }

      if (connectCode == null || connectCode.isEmpty) {
        debugPrint(
          '[ConnectedAccounts] no connect_code in callback query=${cb.queryParameters} fragment=${cb.fragment}',
        );
        Get.snackbar(
          'Connect failed',
          'No connect_code in callback. Allowed Callback URLs must include $_connectRedirect',
        );
        return false;
      }

      final completeUrl =
          'https://${Env.auth0Domain}/me/v1/connected-accounts/complete';
      debugPrint('[ConnectedAccounts] POST complete');
      await _dio.post<Map<String, dynamic>>(
        completeUrl,
        data: jsonEncode({
          'auth_session': authSession,
          'connect_code': connectCode,
          'redirect_uri': _connectRedirect,
        }),
        options: Options(
          headers: {
            'Authorization': 'Bearer $myAccountAt',
            'Content-Type': 'application/json',
          },
        ),
      );

      debugPrint('[ConnectedAccounts] connect flow succeeded');
      if (showSuccessSnack) {
        Get.snackbar('Connected', successMessage);
      }
      return true;
    } on DioException catch (e) {
      debugPrint(
        '[ConnectedAccounts] DioException path=${e.requestOptions.uri} '
        'status=${e.response?.statusCode} data=${e.response?.data}',
      );
      _snackbarForAuth0ConnectError(e, connectionId: connection);
      return false;
    } catch (e, st) {
      debugPrint('[ConnectedAccounts] unexpected error: $e\n$st');
      return false;
    }
  }

  /// Auth0 [A0E-404-0001](https://auth0.com/docs/api/management/errors): connection slug wrong or app not linked.
  void _snackbarForAuth0ConnectError(DioException e, {required String connectionId}) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    String? detail;
    if (data is Map) {
      final d = data['detail'];
      if (d is String) detail = d;
    }
    if (status == 404) {
      Get.snackbar(
        'Auth0: connection not found (404)',
        'Connection "$connectionId" is missing or not enabled for this client. '
        'Copy the exact name from Authentication → Social → [connection] into AUTH0_*_CONNECTION_NAME. '
        'Enable your Native app on that connection\'s Applications tab. '
        'Authorize User access for My Account API (Connected Accounts scopes).',
        duration: const Duration(seconds: 16),
      );
      return;
    }
    if (status == 400 || status == 403) {
      Get.snackbar(
        'Connect failed (${status ?? '?'})',
        detail ?? '$data',
        duration: const Duration(seconds: 10),
      );
    }
  }
}
