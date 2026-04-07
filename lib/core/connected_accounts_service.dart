import 'dart:convert';

import 'package:actra/core/auth0_my_account_linking.dart';
import 'package:actra/core/connected_accounts_external_auth.dart';
import 'package:actra/core/connected_accounts_permissions.dart';
import 'package:actra/core/env.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// [Connected Accounts for Token Vault](https://auth0.com/docs/secure/call-apis-on-users-behalf/token-vault/connected-accounts-for-token-vault):
/// `connect` → browser → `complete`. Requires a My Account API access token
/// ([Auth0MyAccountLinking]).
class ConnectedAccountsService extends GetxService {
  final Dio _dio = Dio();
  final _uuid = const Uuid();

  static bool _warnedMyAccountList404 = false;

  String get _connectRedirect =>
      '${Env.auth0Scheme}://connected-accounts-callback';

  /// Opens the browser to link Google; stores tokens in Auth0 Token Vault on success.
  Future<bool> connectGoogleConnection(
    String provider, {
    bool showSuccessSnack = true,
  }) async {
    debugPrint(
      '[ConnectedAccounts] connectGoogleConnection start provider=$provider',
    );
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
  /// Link GitHub for Token Vault ([Auth0 GitHub integration](https://auth0.com/ai/docs/integrations/github)).
  /// Auth0 requires a non-empty `scopes` array; see [ConnectedAccountsPermissions.scopesForProvider]('github').
  Future<bool> connectGitHubConnection({bool showSuccessSnack = true}) async {
    debugPrint(
      '[ConnectedAccounts] connectGitHubConnection connection=${Env.auth0GithubConnectionName}',
    );
    return _runConnectFlow(
      connection: Env.auth0GithubConnectionName,
      scopes: ConnectedAccountsPermissions.scopesForProvider('github'),
      snackTitle: 'Sign in with GitHub',
      snackBody: 'Safari will open — return here after you finish.',
      successMessage: 'GitHub account linked to Token Vault.',
      invalidConnectHint:
          'Invalid connect response. Check Auth0 Connected Accounts on the GitHub connection.',
      showSuccessSnack: showSuccessSnack,
    );
  }

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
    final myAccountAt = await Get.find<Auth0MyAccountLinking>()
        .obtainAccessTokenForConnectedAccounts();
    if (myAccountAt == null) {
      debugPrint('[ConnectedAccounts] abort: My Account token unavailable');
      return false;
    }

    final state = _uuid.v4();
    final connectUrl =
        'https://${Env.auth0Domain}/me/v1/connected-accounts/connect';
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
      debugPrint(
        '[ConnectedAccounts] opening browser auth url=${startUri.toString()}',
      );
      // Get.snackbar(
      //   snackTitle,
      //   snackBody,
      //   snackPosition: SnackPosition.BOTTOM,
      //   duration: const Duration(seconds: 4),
      // );

      String? callback;
      try {
        callback = await openExternalBrowserAndAwaitConnectedAccountsCallback(
          startUri.toString(),
        );
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
      if ((connectCode == null || connectCode.isEmpty) &&
          cb.fragment.isNotEmpty) {
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

  String _connectionNameForProvider(String provider) {
    if (provider == 'slack') return Env.auth0SlackConnectionName;
    if (provider == 'github') return Env.auth0GithubConnectionName;
    if (provider == 'google_gmail' || provider == 'google_calendar') {
      return Env.auth0GoogleConnectionName;
    }
    return '';
  }

  /// Lists connected accounts from Auth0 My Account API (Token Vault).
  Future<List<Map<String, dynamic>>> listAuth0ConnectedAccounts() async {
    final myAccountAt = await Get.find<Auth0MyAccountLinking>()
        .obtainAccessTokenForConnectedAccounts();
    if (myAccountAt == null) return [];
    return (await _fetchConnectedAccountsWithAccessToken(myAccountAt)).items;
  }

  /// [listEndpoint404] is true when Auth0 returns 404 for `GET /me/v1/connected-accounts`
  /// (My Account API inactive or not authorized for this app — not “no links”).
  Future<({List<Map<String, dynamic>> items, bool listEndpoint404})>
  _fetchConnectedAccountsWithAccessToken(String accessToken) async {
    final url = 'https://${Env.auth0Domain}/me/v1/connected-accounts';
    try {
      final resp = await _dio.get<dynamic>(
        url,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final data = resp.data;
      if (data is List) {
        return (
          items: data.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          listEndpoint404: false,
        );
      }
      if (data is Map) {
        final inner =
            data['data'] ?? data['connected_accounts'] ?? data['accounts'];
        if (inner is List) {
          return (
            items: inner
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
            listEndpoint404: false,
          );
        }
      }
      return (items: <Map<String, dynamic>>[], listEndpoint404: false);
    } on DioException catch (e) {
      debugPrint(
        '[ConnectedAccounts] list connected accounts failed: ${e.response?.statusCode} ${e.response?.data}',
      );
      _maybeSnackbarMyAccountListNotAvailable(e);
      final is404 = e.response?.statusCode == 404;
      return (items: <Map<String, dynamic>>[], listEndpoint404: is404);
    }
  }

  void _maybeSnackbarMyAccountListNotAvailable(DioException e) {
    if (e.response?.statusCode != 404) return;
    if (_warnedMyAccountList404) return;
    _warnedMyAccountList404 = true;
    Get.snackbar(
      'My Account API unavailable (404)',
      'Enable **Auth0 My Account API** under Applications → APIs (Early Access), '
          'authorize this Native app under Application Access (User access) with '
          'read/create/delete:me:connected_accounts. If the route stays 404, the tenant '
          'may not have My Account API enabled.',
      duration: const Duration(seconds: 18),
    );
  }

  /// Removes the Auth0 Token Vault link for this provider’s connection (Google or Slack).
  Future<bool> unlinkAuth0VaultForProvider(String provider) async {
    final connection = _connectionNameForProvider(provider);
    if (connection.isEmpty) return false;
    final myAccountAt = await Get.find<Auth0MyAccountLinking>()
        .obtainAccessTokenForConnectedAccounts();
    if (myAccountAt == null) return false;
    final fetch = await _fetchConnectedAccountsWithAccessToken(myAccountAt);
    final accounts = fetch.items;
    String? accountId;
    for (final row in accounts) {
      final conn =
          row['connection'] as String? ?? row['connection_id'] as String? ?? '';
      if (conn == connection) {
        accountId = row['id'] as String?;
        break;
      }
    }
    if (accountId == null || accountId.isEmpty) {
      if (fetch.listEndpoint404) {
        debugPrint(
          '[ConnectedAccounts] unlink skipped: GET /me/v1/connected-accounts returned 404 '
          '(enable Auth0 My Account API and Application Access with read:me:connected_accounts; '
          'not “missing” $connection).',
        );
      } else {
        debugPrint(
          '[ConnectedAccounts] no Auth0 connected account for connection=$connection',
        );
      }
      return false;
    }
    final url =
        'https://${Env.auth0Domain}/me/v1/connected-accounts/$accountId';
    try {
      await _dio.delete<void>(
        url,
        options: Options(headers: {'Authorization': 'Bearer $myAccountAt'}),
      );
      debugPrint(
        '[ConnectedAccounts] unlinked Auth0 connected account id=$accountId',
      );
      return true;
    } on DioException catch (e) {
      debugPrint(
        '[ConnectedAccounts] DELETE connected account failed: ${e.response?.statusCode} ${e.response?.data}',
      );
      return false;
    }
  }

  /// Auth0 [A0E-404-0001](https://auth0.com/docs/api/management/errors): connection slug wrong or app not linked.
  void _snackbarForAuth0ConnectError(
    DioException e, {
    required String connectionId,
  }) {
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
