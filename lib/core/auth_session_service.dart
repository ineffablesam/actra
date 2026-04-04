import 'package:actra/chat/services/websocket_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

/// Persists Auth0 tokens after login; sends [session_auth] to the backend (with access + refresh).
class AuthSessionService extends GetxService {
  static const _kRefresh = 'actra_auth0_refresh_token';
  static const _kSub = 'actra_auth0_user_sub';
  static const _kAccess = 'actra_auth0_access_token';
  static const _kIdToken = 'actra_auth0_id_token';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  final RxnString userId = RxnString();
  final RxnString accessToken = RxnString();

  /// Load tokens from secure storage (call from [main] before [runApp]).
  Future<void> hydrateFromStorage() async {
    final refresh = await _storage.read(key: _kRefresh);
    final sub = await _storage.read(key: _kSub);
    final access = await _storage.read(key: _kAccess);
    if (sub != null && sub.isNotEmpty) {
      userId.value = sub;
    }
    if (access != null && access.isNotEmpty) {
      accessToken.value = access;
    }
    if (refresh != null && refresh.isNotEmpty) {
      // refresh kept in storage only; not exposed in observables
    }
  }

  /// True when secure storage has tokens needed for backend session + refresh exchange.
  Future<bool> hasCompleteSession() async {
    final refresh = await _storage.read(key: _kRefresh);
    final sub = await _storage.read(key: _kSub);
    final access = await _storage.read(key: _kAccess);
    return refresh != null &&
        refresh.isNotEmpty &&
        sub != null &&
        sub.isNotEmpty &&
        access != null &&
        access.isNotEmpty;
  }

  /// Call after a successful Auth0 token response.
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
    String? idToken,
  }) async {
    await _storage.write(key: _kAccess, value: accessToken);
    await _storage.write(key: _kRefresh, value: refreshToken);
    await _storage.write(key: _kSub, value: userId);
    if (idToken != null && idToken.isNotEmpty) {
      await _storage.write(key: _kIdToken, value: idToken);
    }
    this.userId.value = userId;
    this.accessToken.value = accessToken;
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kSub);
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kIdToken);
    userId.value = null;
    accessToken.value = null;
  }

  Future<String?> readRefreshToken() => _storage.read(key: _kRefresh);

  Future<String?> readIdToken() => _storage.read(key: _kIdToken);

  /// Sends [session_auth] so the backend can verify JWT and exchange refresh for Google APIs.
  Future<void> pushSessionAuthIfAvailable(WebSocketService ws) async {
    final refresh = await readRefreshToken();
    final sub = userId.value ?? await _storage.read(key: _kSub);
    final access = accessToken.value ?? await _storage.read(key: _kAccess);
    if (refresh == null ||
        refresh.isEmpty ||
        sub == null ||
        sub.isEmpty ||
        access == null ||
        access.isEmpty) {
      return;
    }
    ws.sendSessionAuth(
      userId: sub,
      refreshToken: refresh,
      accessToken: access,
    );
  }
}
