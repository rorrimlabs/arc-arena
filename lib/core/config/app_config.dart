/// Build-time configuration, selected with `--dart-define`.
///
/// Default backend is **local** (Drift/SQLite) so the app is runnable on-device
/// with no server. Switch to Supabase with:
///
/// ```
/// flutter run \
///   --dart-define=AO_BACKEND=supabase \
///   --dart-define=AO_SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=AO_SUPABASE_ANON_KEY=eyJ...
/// ```
library;

import 'package:meta/meta.dart';

enum Backend { local, supabase }

@immutable
class AppConfig {
  const AppConfig({
    required this.backend,
    this.supabaseUrl,
    this.supabaseAnonKey,
  });

  final Backend backend;
  final String? supabaseUrl;
  final String? supabaseAnonKey;

  bool get isSupabase => backend == Backend.supabase;

  /// True only when Supabase is selected *and* credentials are present.
  bool get supabaseReady =>
      isSupabase &&
      (supabaseUrl?.isNotEmpty ?? false) &&
      (supabaseAnonKey?.isNotEmpty ?? false);

  /// Read configuration from the compile-time environment.
  factory AppConfig.fromEnvironment() {
    const raw = String.fromEnvironment('AO_BACKEND', defaultValue: 'local');
    const url = String.fromEnvironment('AO_SUPABASE_URL');
    const key = String.fromEnvironment('AO_SUPABASE_ANON_KEY');
    return AppConfig(
      backend: raw == 'supabase' ? Backend.supabase : Backend.local,
      supabaseUrl: url.isEmpty ? null : url,
      supabaseAnonKey: key.isEmpty ? null : key,
    );
  }
}
