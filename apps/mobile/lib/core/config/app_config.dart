/// Build-time configuration, selected with `--dart-define-from-file`.
///
/// * Development: `tool/dev_run.sh` writes `dart_define.dev.json` (git-ignored)
///   from the local stack's `supabase status` and runs with it. Without any
///   defines a DEBUG build runs local-only mode (Drift/SQLite, demo catalog and
///   demo PINs) so the app is usable with no server.
/// * Release: always cloud mode, from a `dart_define.prod.json` kept outside git
///   with the hosted project's https URL and its publishable (or legacy anon)
///   key. A release build refuses to start in local mode, with a missing or
///   unknown AO_BACKEND, a development server, a non-https URL or a privileged
///   key ([AppConfig.problemFor]).
///
/// Only the publishable key ever goes into the app. The secret / service-role
/// key and the database password never do.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

enum Backend { local, supabase }

@immutable
class AppConfig {
  const AppConfig({
    required this.backend,
    this.supabaseUrl,
    this.supabaseAnonKey,
    this.backendSetting,
    this.sentryDsn,
    this.environment = 'development',
    this.replayEnabled = true,
    this.replaySessionRateOverride,
    this.replayErrorRateOverride,
    this.sentryDebug = false,
  });

  final Backend backend;
  final String? supabaseUrl;
  final String? supabaseAnonKey;

  /// AO_BACKEND exactly as given (null or empty when the build did not set it).
  final String? backendSetting;

  /// Sentry DSN for crash reporting (null or empty disables Sentry safely).
  final String? sentryDsn;

  /// Runtime environment name, e.g. 'development' or 'production'.
  final String environment;

  /// True when a Sentry DSN is configured.
  bool get isSentryEnabled => sentryDsn != null && sentryDsn!.trim().isNotEmpty;

  bool get isProduction => environment == 'production';

  /// AO_SENTRY_DEBUG=true prints the Sentry SDK's own log (envelopes sent,
  /// replay segments) — for verifying a development build. Off by default.
  final bool sentryDebug;

  /// Sentry Session Replay switch (AO_SENTRY_REPLAY; `off`, `false`, `0` or
  /// `no` turn it off). Off means both sample rates are 0: nothing is recorded.
  final bool replayEnabled;

  /// AO_SENTRY_REPLAY_SESSION_RATE / AO_SENTRY_REPLAY_ERROR_RATE when given as
  /// a number from 0 to 1 (anything else is ignored and the default applies).
  final double? replaySessionRateOverride;
  final double? replayErrorRateOverride;

  /// Share of sessions recorded in full. Default: 1.0 outside production (so a
  /// replay can be verified in development / testing), 0.1 in production.
  double get replaySessionSampleRate => !replayEnabled
      ? 0
      : replaySessionRateOverride ?? (isProduction ? 0.1 : 1.0);

  /// Share of errors that send the replay buffered before them (default 1.0).
  double get replayOnErrorSampleRate =>
      !replayEnabled ? 0 : replayErrorRateOverride ?? 1.0;

  /// A sample rate from the build, or null when absent or not within 0..1.
  static double? sampleRate(String raw) {
    final v = double.tryParse(raw.trim());
    return v != null && v >= 0 && v <= 1 ? v : null;
  }

  bool get isSupabase => backend == Backend.supabase;

  /// True only when Supabase is selected *and* credentials are present.
  bool get supabaseReady =>
      isSupabase &&
      (supabaseUrl?.isNotEmpty ?? false) &&
      (supabaseAnonKey?.isNotEmpty ?? false);

  /// A plain-http, loopback, emulator or local-network-name backend is a
  /// DEVELOPMENT stack. A release build must never ship pointing at it (or at
  /// any non-TLS server).
  bool get isDevelopmentBackend {
    final uri = Uri.tryParse(supabaseUrl ?? '');
    if (uri == null || uri.host.isEmpty) return true;
    final host = uri.host.toLowerCase();
    return uri.scheme != 'https' ||
        const {
          'localhost',
          '127.0.0.1',
          '0.0.0.0',
          '10.0.2.2',
          '::1',
        }.contains(host) ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.test');
  }

  /// Why the client key must not ship, or null for a publishable key
  /// (`sb_publishable_…`) or a legacy JWT whose role is `anon`. Never echoes
  /// the key.
  static String? keyProblem(String key) {
    if (key.startsWith('sb_publishable_')) return null;
    if (key.startsWith('sb_secret_')) {
      return 'AO_SUPABASE_ANON_KEY is a SECRET key. Only the publishable key '
          'may be built into the app.';
    }
    final parts = key.split('.');
    if (parts.length == 3) {
      try {
        final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        final role = claims is Map ? claims['role'] : null;
        if (role == 'anon') return null;
        if (role == 'service_role') {
          return 'AO_SUPABASE_ANON_KEY is the SERVICE ROLE key. Only the '
              'publishable (anon) key may be built into the app.';
        }
      } on FormatException {
        // Not a JWT: falls through.
      }
    }
    return 'AO_SUPABASE_ANON_KEY is not a Supabase publishable key '
        '(sb_publishable_…) or legacy anon key.';
  }

  /// Why this configuration must not be used, or null when it is fine.
  String? problemFor({required bool releaseBuild}) {
    final setting = backendSetting ?? '';
    if (setting.isNotEmpty && setting != 'local' && setting != 'supabase') {
      return 'Unknown AO_BACKEND "$setting". Use "supabase" '
          '(or "local" for a development build).';
    }
    if (!isSupabase) {
      if (releaseBuild) {
        return 'This release build has no cloud configuration. Local mode '
            '(on-device demo data and default PINs) is for development only: '
            'build the release with --dart-define-from-file='
            'dart_define.prod.json (AO_BACKEND=supabase, the hosted https URL '
            'and its publishable key).';
      }
      return null;
    }
    if (!supabaseReady) {
      return 'Cloud mode is selected but AO_SUPABASE_URL / '
          'AO_SUPABASE_ANON_KEY are missing.';
    }
    final key = keyProblem(supabaseAnonKey!);
    if (key != null) return key;
    if (releaseBuild && isDevelopmentBackend) {
      return 'This release build points at a development server '
          '(${supabaseUrl ?? '?'}). Build it with the production configuration '
          '(an https URL of the hosted project).';
    }
    return null;
  }

  /// Read configuration from the compile-time environment.
  factory AppConfig.fromEnvironment() {
    const raw = String.fromEnvironment('AO_BACKEND');
    const url = String.fromEnvironment('AO_SUPABASE_URL');
    const key = String.fromEnvironment('AO_SUPABASE_ANON_KEY');
    const sentryDsn = String.fromEnvironment('AO_SENTRY_DSN');
    const environment = String.fromEnvironment(
      'AO_ENVIRONMENT',
      defaultValue: 'development',
    );
    const replay = String.fromEnvironment('AO_SENTRY_REPLAY');
    const replaySessionRate = String.fromEnvironment(
      'AO_SENTRY_REPLAY_SESSION_RATE',
    );
    const replayErrorRate = String.fromEnvironment(
      'AO_SENTRY_REPLAY_ERROR_RATE',
    );
    const sentryDebug = String.fromEnvironment('AO_SENTRY_DEBUG');
    return AppConfig(
      backend: raw == 'supabase' ? Backend.supabase : Backend.local,
      supabaseUrl: url.isEmpty ? null : url,
      supabaseAnonKey: key.isEmpty ? null : key,
      backendSetting: raw,
      sentryDsn: sentryDsn.isEmpty ? null : sentryDsn,
      environment: environment.isEmpty ? 'development' : environment,
      replayEnabled: !const {
        'off',
        'false',
        '0',
        'no',
      }.contains(replay.trim().toLowerCase()),
      replaySessionRateOverride: sampleRate(replaySessionRate),
      replayErrorRateOverride: sampleRate(replayErrorRate),
      sentryDebug: sentryDebug.trim().toLowerCase() == 'true',
    );
  }
}
