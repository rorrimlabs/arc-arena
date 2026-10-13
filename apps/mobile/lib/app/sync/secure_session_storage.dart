/// Keeps the Supabase sign-in (refresh token) in the platform keystore
/// (iOS Keychain / Android Keystore-backed storage) instead of plain shared
/// preferences, so another app or a backup of app data cannot lift it.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The sign-in is kept per backend: a session from one Supabase project (say
/// hosted dev) is never replayed against another (the local stack), where its
/// refresh token can only fail with `refresh_token_not_found`.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required String backendUrl})
    : _key = keyFor(backendUrl);

  /// Before sign-ins were kept per backend; read by nothing now.
  static const _legacyKey = 'arena_ops.supabase.session';
  static const _storage = FlutterSecureStorage();

  final String _key;

  /// `arena_ops.supabase.session@<host:port>` of [backendUrl].
  static String keyFor(String backendUrl) =>
      '$_legacyKey@${Uri.parse(backendUrl).authority}';

  /// Drops a sign-in stored under the old shared key: which backend it belongs
  /// to is unknown, so the person signs in once more instead of replaying it.
  @override
  Future<void> initialize() => _storage.delete(key: _legacyKey);

  @override
  Future<bool> hasAccessToken() async =>
      (await _storage.read(key: _key)) != null;

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}
