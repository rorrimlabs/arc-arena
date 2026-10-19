/// Build-time configuration, selected with `--flavor` and
/// `--dart-define-from-file`. Each flavor is bound to one environment, and
/// AO_ENVIRONMENT in its define file must say the same:
///
/// * `dev` → development (the default flavor, `pubspec.yaml`): the local
///   Supabase stack via the committed `dart_define.local.json`
///   (`dart_define.local-android.json` for an Android emulator). Without any
///   defines it runs local-only mode (Drift/SQLite, demo catalog and demo
///   PINs) so the app is usable with no server. Never a release build.
/// * `staging` → staging: the personal QA project, from a git-ignored
///   `dart_define.staging.json`.
/// * `prod` → production: the company's project, from a git-ignored
///   `dart_define.prod.json`. Never a debug build.
///
/// Hosted builds reach only the hosts listed for their environment
/// ([AppConfig.hostedSupabaseHosts]), so a production build can never point
/// at staging. [AppConfig.problemFor] refuses everything else before the app
/// starts, in every build mode.
///
/// Only the publishable key ever goes into the app. The secret / service-role
/// key and the database password never do.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

enum Backend { local, supabase }

/// How the app was compiled (`kDebugMode` / `kProfileMode` / `kReleaseMode`).
enum BuildMode { debug, profile, release }

@immutable
class AppConfig {
  const AppConfig({
    required this.backend,
    this.supabaseUrl,
    this.supabaseAnonKey,
    this.backendSetting,
    this.flavor,
    this.sentryDsn,
    this.environment = 'development',
    this.replayEnabled = true,
    this.replaySessionRateOverride,
    this.replayErrorRateOverride,
    this.sentryDebug = false,
    this.hostedHosts = hostedSupabaseHosts,
  });

  /// The environment each flavor must be built for.
  static const environmentForFlavor = {
    'dev': 'development',
    'staging': 'staging',
    'prod': 'production',
  };

  /// The hosted Supabase hosts each hosted environment may reach. Project URLs
  /// are public (every build carries one); listing them here is what stops a
  /// production build from pointing at staging. An empty set means that
  /// environment has no project yet, so its flavor refuses to start. The two
  /// sets never share a host.
  static const hostedSupabaseHosts = <String, Set<String>>{
    // arena-ops-staging, the personal QA project (Mumbai).
    'staging': <String>{'sqznpjqktvsabjxvpzjh.supabase.co'},
    // The company's production project: added once it exists.
    'production': <String>{},
  };

  static const _defineFiles = {
    'dev':
        'dart_define.local.json (dart_define.local-android.json on an Android '
        'emulator)',
    'staging': 'dart_define.staging.json',
    'prod': 'dart_define.prod.json',
  };

  final Backend backend;
  final String? supabaseUrl;
  final String? supabaseAnonKey;

  /// AO_BACKEND exactly as given (null or empty when the build did not set it).
  final String? backendSetting;

  /// The `--flavor` this build was made with (null or empty: none, which counts
  /// as `dev`).
  final String? flavor;

  /// Sentry DSN for crash reporting (null or empty disables Sentry safely).
  final String? sentryDsn;

  /// Runtime environment name: 'development', 'staging' or 'production'.
  final String environment;

  /// The hosts each hosted environment may reach ([hostedSupabaseHosts]; a
  /// parameter only so tests can supply their own).
  final Map<String, Set<String>> hostedHosts;

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
  /// DEVELOPMENT stack. Only the dev flavor may use one; a staging or
  /// production build must never point at it (or at any non-TLS server).
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
    final role = _jwtClaims(key)?['role'];
    if (role == 'anon') return null;
    if (role == 'service_role') {
      return 'AO_SUPABASE_ANON_KEY is the SERVICE ROLE key. Only the '
          'publishable (anon) key may be built into the app.';
    }
    return 'AO_SUPABASE_ANON_KEY is not a Supabase publishable key '
        '(sb_publishable_…) or legacy anon key.';
  }

  /// The claims of a legacy JWT key, or null when [key] is not one.
  static Map<String, dynamic>? _jwtClaims(String key) {
    final parts = key.split('.');
    if (parts.length != 3) return null;
    try {
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return claims is Map<String, dynamic> ? claims : null;
    } on FormatException {
      return null;
    }
  }

  /// Why this configuration must not be used, or null when it is fine.
  String? problemFor({required BuildMode mode}) {
    final setting = backendSetting ?? '';
    if (setting.isNotEmpty && setting != 'local' && setting != 'supabase') {
      return 'Unknown AO_BACKEND "$setting". Use "supabase" '
          '(or "local" for a development build).';
    }
    final flavorName = (flavor?.isEmpty ?? true) ? 'dev' : flavor!;
    final expected = environmentForFlavor[flavorName];
    if (expected == null) {
      return 'Unknown flavor "$flavorName". Build with --flavor dev, staging '
          'or prod.';
    }
    if (environment != expected) {
      return 'The $flavorName flavor must be built for AO_ENVIRONMENT='
          '$expected (this build says "$environment"). Use its define file: '
          '${_defineFiles[flavorName]}.';
    }
    if (flavorName == 'dev') return _devProblem(mode);
    if (flavorName == 'prod' && mode == BuildMode.debug) {
      return 'The prod flavor never runs as a debug build. Develop with '
          '--flavor dev (the local stack) or test with --flavor staging.';
    }
    return _hostedProblem(expected, _defineFiles[flavorName]!);
  }

  String? _devProblem(BuildMode mode) {
    if (mode == BuildMode.release) {
      return 'This release build is the dev flavor. Local mode (on-device demo '
          'data and default PINs) and the local stack are for development '
          'only: build releases with --flavor staging or --flavor prod and '
          'their define file.';
    }
    if (!isSupabase) return null;
    if (!supabaseReady) return _missing;
    final key = keyProblem(supabaseAnonKey!);
    if (key != null) return key;
    if (!isDevelopmentBackend) {
      return 'The dev flavor uses the local Supabase stack only '
          '(${supabaseUrl ?? '?'} is a hosted server). Hosted projects are '
          'reached with --flavor staging or --flavor prod.';
    }
    return null;
  }

  String? _hostedProblem(String env, String defineFile) {
    if (!isSupabase) {
      return 'This $env build has no cloud configuration. Build it with '
          '--dart-define-from-file=$defineFile (AO_BACKEND=supabase, the '
          'project\'s https URL and its publishable key).';
    }
    if (!supabaseReady) return _missing;
    final key = keyProblem(supabaseAnonKey!);
    if (key != null) return key;
    if (isDevelopmentBackend) {
      return 'This $env build points at a development server '
          '(${supabaseUrl ?? '?'}). It must use the $env project\'s https URL.';
    }
    final allowed = hostedHosts[env] ?? const <String>{};
    if (allowed.isEmpty) {
      return 'No $env Supabase project is set up yet: this build cannot run '
          'until its host is added to AppConfig.hostedSupabaseHosts.';
    }
    final host = Uri.parse(supabaseUrl!).host.toLowerCase();
    if (!allowed.contains(host)) {
      return 'AO_SUPABASE_URL ($host) is not the $env project. Build with '
          '$defineFile.';
    }
    final ref = _jwtClaims(supabaseAnonKey!)?['ref'];
    if (ref is String && host != '$ref.supabase.co') {
      return 'AO_SUPABASE_ANON_KEY belongs to a different project than '
          'AO_SUPABASE_URL ($host).';
    }
    return null;
  }

  static const _missing =
      'Cloud mode is selected but AO_SUPABASE_URL / AO_SUPABASE_ANON_KEY are '
      'missing.';

  /// Read configuration from the compile-time environment.
  factory AppConfig.fromEnvironment() {
    // Set by `flutter run/build --flavor` (Flutter's `appFlavor` reads the
    // same value). A define file cannot set it: the flutter tool refuses.
    const flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');
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
      flavor: flavor.isEmpty ? null : flavor,
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
