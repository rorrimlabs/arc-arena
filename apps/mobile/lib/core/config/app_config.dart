/// Build-time configuration, selected with `--dart-define`.
///
/// Default backend is **local** (Drift/SQLite) so the app is runnable on-device
/// with no server. Cloud mode reads its settings from a dart-define file:
///
/// * development: `tool/dev_run.sh` writes `dart_define.dev.json` (git-ignored)
///   from the local stack's `supabase status` and runs with it;
/// * production: a `dart_define.prod.json` kept outside git, with the hosted
///   project's https URL and its anon (public) key.
///
/// Only the anon key ever goes into the app. The service-role key and the
/// database password never do.
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

  /// A plain-http or loopback backend is the local DEVELOPMENT stack. A release
  /// build must never ship pointing at it (or at any non-TLS server).
  bool get isDevelopmentBackend {
    final uri = Uri.tryParse(supabaseUrl ?? '');
    if (uri == null) return true;
    return uri.scheme != 'https' ||
        const {'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host);
  }

  /// Why this configuration must not be used, or null when it is fine.
  String? problemFor({required bool releaseBuild}) {
    if (!isSupabase) return null;
    if (!supabaseReady) {
      return 'Cloud mode is selected but AO_SUPABASE_URL / '
          'AO_SUPABASE_ANON_KEY are missing.';
    }
    if (releaseBuild && isDevelopmentBackend) {
      return 'This release build points at a development server '
          '(${supabaseUrl ?? '?'}). Build it with the production configuration.';
    }
    return null;
  }

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
