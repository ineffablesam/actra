import 'package:actra/chat/services/websocket_service.dart';
import 'package:actra/core/env.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

/// Persists Auth0 refresh token + subject after login; used to send [session_auth] to the backend.
class AuthSessionService extends GetxService {
  static const _kRefresh = 'actra_auth0_refresh_token';
  static const _kSub = 'actra_auth0_user_sub';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Call after a successful `flutter_appauth` token response.
  Future<void> saveSession({
    required String refreshToken,
    required String userId,
  }) async {
    await _storage.write(key: _kRefresh, value: refreshToken);
    await _storage.write(key: _kSub, value: userId);
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kSub);
  }

  /// Sends [session_auth] so the backend can exchange for Google APIs. Never logs the token.
  Future<void> pushSessionAuthIfAvailable(WebSocketService ws) async {
    final fromDefine = Env.devAuth0RefreshToken.trim();
    if (fromDefine.isNotEmpty) {
      ws.sendSessionAuth(
        userId: Env.devUserId,
        refreshToken: fromDefine,
      );
      return;
    }

    final refresh = await _storage.read(key: _kRefresh);
    final sub = await _storage.read(key: _kSub);
    if (refresh != null &&
        refresh.isNotEmpty &&
        sub != null &&
        sub.isNotEmpty) {
      ws.sendSessionAuth(userId: sub, refreshToken: refresh);
    }
  }
}
