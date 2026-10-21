/// The Sentry options the app starts with: Session Replay sampling per
/// environment, masking on by default, and the existing beforeSend filter.
library;

import 'package:arena_ops/core/config/app_config.dart';
import 'package:arena_ops/core/monitoring/sentry_setup.dart';
import 'package:arena_ops/data/sync/sync_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

SentryFlutterOptions _configured(AppConfig config, {bool debugBuild = false}) {
  final options = SentryFlutterOptions();
  configureSentry(options, config, debugBuild: debugBuild);
  return options;
}

const _dsn = 'https://public@example.invalid/1';

void main() {
  test('development: every session and every error is replayed', () {
    final o = _configured(
      const AppConfig(backend: Backend.local, sentryDsn: _dsn),
    );
    expect(o.replay.sessionSampleRate, 1.0);
    expect(o.replay.onErrorSampleRate, 1.0);
    expect(o.tracesSampleRate, 1.0);
    expect(o.environment, 'development');
  });

  test('production: 10% of sessions, every error', () {
    final o = _configured(
      const AppConfig(
        backend: Backend.supabase,
        sentryDsn: _dsn,
        environment: 'production',
      ),
    );
    expect(o.replay.sessionSampleRate, 0.1);
    expect(o.replay.onErrorSampleRate, 1.0);
    expect(o.tracesSampleRate, 0.1);
  });

  test('text and images are masked, PII is not sent', () {
    final o = _configured(
      const AppConfig(backend: Backend.local, sentryDsn: _dsn),
    );
    expect(o.privacy.maskAllText, isTrue);
    expect(o.privacy.maskAllImages, isTrue);
    expect(o.sendDefaultPii, isFalse);
    expect(o.debug, isFalse, reason: 'SDK logging is opt-in (AO_SENTRY_DEBUG)');
  });

  test('replay can be switched off by configuration', () {
    final o = _configured(
      const AppConfig(
        backend: Backend.local,
        sentryDsn: _dsn,
        replayEnabled: false,
      ),
    );
    expect(o.replay.sessionSampleRate, 0);
    expect(o.replay.onErrorSampleRate, 0);
  });

  test('app hangs are reported from profile/release builds, not debug', () {
    const config = AppConfig(
      backend: Backend.supabase,
      sentryDsn: _dsn,
      environment: 'production',
    );
    expect(_configured(config).enableAppHangTracking, isTrue);
    expect(
      _configured(config, debugBuild: true).enableAppHangTracking,
      isFalse,
      reason: 'debug Dart (JIT, breakpoints) blocks the iOS main thread',
    );
  });

  test('no DSN: nothing is configured to send', () {
    final o = _configured(const AppConfig(backend: Backend.local));
    expect(o.dsn, '');
  });

  test('beforeSend still drops expected offline sync failures only', () async {
    final o = _configured(
      const AppConfig(backend: Backend.local, sentryDsn: _dsn),
    );
    final offline = SentryEvent(throwable: SyncOfflineException('no network'));
    final real = SentryEvent(throwable: StateError('unexpected'));
    expect(await o.beforeSend!(offline, Hint()), isNull);
    expect(await o.beforeSend!(real, Hint()), same(real));
  });
}
