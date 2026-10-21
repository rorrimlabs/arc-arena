/// Keeps the Supabase sign-in (refresh token) in the platform keystore
/// (iOS Keychain / Android Keystore-backed storage) instead of plain shared
/// preferences, so another app or a backup of app data cannot lift it.
library;

import 'package:flutter/foundation.dart';
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
  Future<void> initialize() => _guard(() => _storage.delete(key: _legacyKey));

  @override
  Future<bool> hasAccessToken() async => (await accessToken()) != null;

  /// The stored sign-in, or null. A keystore that cannot be read must not stop
  /// the app at start: the person is asked to sign in. The entry is NOT
  /// deleted — the error may be passing (iOS refuses Keychain reads while the
  /// device is locked) — and the next sign-in overwrites it anyway.
  @override
  Future<String?> accessToken() async {
    try {
      return await _storage.read(key: _key);
    } on Object catch (e) {
      debugPrint('stored sign-in unreadable (${e.runtimeType}); asking to sign in');
      return null;
    }
  }

  /// Not kept if the keystore refuses it: the sign-in still works until the
  /// app closes, and the next start asks for it again.
  @override
  Future<void> persistSession(String persistSessionString) =>
      _guard(() => _storage.write(key: _key, value: persistSessionString));

  @override
  Future<void> removePersistedSession() =>
      _guard(() => _storage.delete(key: _key));

  static Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (e) {
      debugPrint('keystore: ${e.runtimeType}');
    }
  }
}
