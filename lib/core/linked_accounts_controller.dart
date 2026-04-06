import 'dart:async';

import 'package:actra/core/auth_session_service.dart';
import 'package:actra/core/connected_accounts_service.dart';
import 'package:actra/core/env.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

/// Server-side linked integration ids (Redis) + refresh from HTTP API.
class LinkedAccountsController extends GetxController {
  final Dio _dio = Dio();

  final linkedProviders = <String>[].obs;

  @override
  void onInit() {
    super.onInit();
    unawaited(reloadFromBackend());
  }

  /// Fetches linked provider ids from the Actra HTTP API (`GET /users/me/connected-accounts`).
  Future<void> reloadFromBackend() async {
    final base = Env.memoryApiBaseUrl.trim();
    if (base.isEmpty) {
      debugPrint('[LinkedAccounts] memoryApiBaseUrl empty; skip refresh');
      return;
    }
    if (!Get.isRegistered<AuthSessionService>()) return;
    final session = Get.find<AuthSessionService>();
    final uid = session.userId.value;
    final at = session.accessToken.value;
    if (uid == null || uid.isEmpty || at == null || at.isEmpty) {
      linkedProviders.clear();
      return;
    }
    final uri = base.endsWith('/') ? '${base}users/me/connected-accounts' : '$base/users/me/connected-accounts';
    try {
      final headers = <String, String>{
        'Authorization': 'Bearer $at',
      };
      if (Env.backendTrustUserIdHeaderBool) {
        headers['X-User-Id'] = uid;
      }
      final resp = await _dio.get<Map<String, dynamic>>(
        uri,
        options: Options(headers: headers),
      );
      final list = resp.data?['providers'];
      if (list is List) {
        linkedProviders.assignAll(list.map((e) => e.toString()).toList());
      } else {
        linkedProviders.clear();
      }
    } on DioException catch (e) {
      debugPrint('[LinkedAccounts] reload failed ${e.response?.statusCode} ${e.message}');
    }
  }

  /// Unlinks Auth0 Token Vault + clears backend state for this integration.
  Future<void> disconnect(String provider) async {
    if (Get.isRegistered<ConnectedAccountsService>()) {
      if (provider == 'google_gmail' || provider == 'google_calendar') {
        await Get.find<ConnectedAccountsService>().unlinkAuth0VaultForProvider('google_gmail');
      } else {
        await Get.find<ConnectedAccountsService>().unlinkAuth0VaultForProvider(provider);
      }
    }

    final base = Env.memoryApiBaseUrl.trim();
    if (base.isEmpty) {
      await reloadFromBackend();
      return;
    }
    if (!Get.isRegistered<AuthSessionService>()) return;
    final session = Get.find<AuthSessionService>();
    final uid = session.userId.value;
    final at = session.accessToken.value;
    if (uid == null || uid.isEmpty || at == null || at.isEmpty) return;

    final path =
        base.endsWith('/')
            ? '${base}users/me/connected-accounts/$provider'
            : '$base/users/me/connected-accounts/$provider';
    final headers = <String, String>{'Authorization': 'Bearer $at'};
    if (Env.backendTrustUserIdHeaderBool) {
      headers['X-User-Id'] = uid;
    }
    try {
      await _dio.delete<void>(path, options: Options(headers: headers));
    } on DioException catch (e) {
      debugPrint('[LinkedAccounts] disconnect failed ${e.response?.statusCode}');
      Get.snackbar('Disconnect failed', e.response?.data?.toString() ?? e.message ?? '');
      return;
    }
    await reloadFromBackend();
  }
}
