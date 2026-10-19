/// Release builds can never fall back to local demo mode, ship a privileged
/// key, or point at a development / non-TLS server; debug builds keep local
/// mode for development.
library;

import 'dart:convert';

import 'package:arena_ops/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

String _jwt(String role) {
  String part(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'role': role, 'iss': 'supabase'})}.sig';
}

const _publishable = 'sb_publishable_TESTONLY_not_a_real_key';
const _hosted = 'https://abcdefghijklmnop.supabase.co';

AppConfig _cloud(
  String url,
  String key, {
  String environment = 'production',
}) => AppConfig(
  backend: Backend.supabase,
  supabaseUrl: url,
  supabaseAnonKey: key,
  backendSetting: 'supabase',
  environment: environment,
);

void main() {
  group('local mode', () {
    test('a debug build without defines runs local mode (development)', () {
      const c = AppConfig(backend: Backend.local);
      expect(c.problemFor(releaseBuild: false), isNull);
    });

    test('a release build without defines refuses to start', () {
      const c = AppConfig(backend: Backend.local, backendSetting: '');
      expect(
        c.problemFor(releaseBuild: true),
        contains('no cloud configuration'),
      );
    });

    test(
      'a release build refuses local mode even when asked for explicitly',
      () {
        const c = AppConfig(backend: Backend.local, backendSetting: 'local');
        expect(c.problemFor(releaseBuild: true), contains('development only'));
      },
    );

    test('an unknown AO_BACKEND is refused instead of meaning local', () {
      const c = AppConfig(backend: Backend.local, backendSetting: 'supbase');
      expect(c.problemFor(releaseBuild: false), contains('Unknown AO_BACKEND'));
      expect(c.problemFor(releaseBuild: true), contains('Unknown AO_BACKEND'));
    });
  });

  group('cloud mode', () {
    test('a hosted https project with a publishable key is accepted', () {
      expect(
        _cloud(_hosted, _publishable).problemFor(releaseBuild: true),
        isNull,
      );
      expect(
        _cloud(_hosted, _jwt('anon')).problemFor(releaseBuild: true),
        isNull,
        reason: 'legacy anon JWT',
      );
    });

    test('a release build not marked production is refused', () {
      final c = _cloud(_hosted, _publishable, environment: 'development');
      expect(c.problemFor(releaseBuild: true), contains('AO_ENVIRONMENT'));
      expect(c.problemFor(releaseBuild: false), isNull);
    });

    test('missing URL or key is refused in any build', () {
      const c = AppConfig(
        backend: Backend.supabase,
        backendSetting: 'supabase',
      );
      expect(c.problemFor(releaseBuild: false), contains('missing'));
    });

    test('a secret or service-role key is refused, without echoing it', () {
      const secret = 'sb_secret_SHOULD_NEVER_SHIP_123';
      final p1 = _cloud(_hosted, secret).problemFor(releaseBuild: false)!;
      expect(p1, contains('SECRET'));
      expect(p1, isNot(contains(secret)));
      final service = _jwt('service_role');
      final p2 = _cloud(_hosted, service).problemFor(releaseBuild: false)!;
      expect(p2, contains('SERVICE ROLE'));
      expect(p2, isNot(contains(service)));
      expect(
        _cloud(_hosted, 'whatever').problemFor(releaseBuild: false),
        contains('not a Supabase publishable key'),
      );
    });

    test('release builds refuse development and non-TLS servers', () {
      for (final url in [
        'http://127.0.0.1:54431',
        'http://abcdefghijklmnop.supabase.co',
        'https://localhost:54431',
        'https://10.0.2.2:54431',
        'https://[::1]:54431',
        'https://0.0.0.0',
        'https://supabase.local',
        'https://api.arena.test',
        'https://dev.localhost',
        'not a url',
      ]) {
        expect(
          _cloud(url, _publishable).problemFor(releaseBuild: true),
          isNotNull,
          reason: url,
        );
      }
    });

    test('debug builds may use the local stack', () {
      expect(
        _cloud(
          'http://127.0.0.1:54431',
          _publishable,
        ).problemFor(releaseBuild: false),
        isNull,
      );
    });
  });

  group('sentry and environment config', () {
    test('defaults to development environment and null sentryDsn', () {
      const c = AppConfig(backend: Backend.local);
      expect(c.environment, 'development');
      expect(c.sentryDsn, isNull);
      expect(c.isSentryEnabled, isFalse);
    });

    test('enables sentry when non-empty DSN is provided', () {
      const c = AppConfig(
        backend: Backend.supabase,
        sentryDsn: 'https://key@sentry.io/123',
        environment: 'production',
      );
      expect(c.environment, 'production');
      expect(c.sentryDsn, 'https://key@sentry.io/123');
      expect(c.isSentryEnabled, isTrue);
    });

    test('safely disables sentry when DSN is empty or whitespace', () {
      const c = AppConfig(backend: Backend.local, sentryDsn: '   ');
      expect(c.isSentryEnabled, isFalse);
    });

    test(
      'missing sentry DSN is never considered a problem in release build',
      () {
        final c = _cloud(_hosted, _publishable);
        expect(c.sentryDsn, isNull);
        expect(c.problemFor(releaseBuild: true), isNull);
      },
    );
  });

  group('session replay', () {
    test('records every session outside production, 10% in production', () {
      expect(
        const AppConfig(backend: Backend.local).replaySessionSampleRate,
        1.0,
      );
      expect(
        const AppConfig(
          backend: Backend.local,
          environment: 'staging',
        ).replaySessionSampleRate,
        1.0,
      );
      expect(
        const AppConfig(
          backend: Backend.supabase,
          environment: 'production',
        ).replaySessionSampleRate,
        0.1,
      );
    });

    test('replays every error by default', () {
      expect(
        const AppConfig(
          backend: Backend.supabase,
          environment: 'production',
        ).replayOnErrorSampleRate,
        1.0,
      );
    });

    test('rates can be set per build', () {
      const c = AppConfig(
        backend: Backend.supabase,
        environment: 'production',
        replaySessionRateOverride: 0.05,
        replayErrorRateOverride: 0.5,
      );
      expect(c.replaySessionSampleRate, 0.05);
      expect(c.replayOnErrorSampleRate, 0.5);
    });

    test('switched off, nothing is recorded', () {
      const c = AppConfig(
        backend: Backend.local,
        replayEnabled: false,
        replaySessionRateOverride: 1,
      );
      expect(c.replaySessionSampleRate, 0);
      expect(c.replayOnErrorSampleRate, 0);
    });

    test('only numbers from 0 to 1 are accepted as rates', () {
      expect(AppConfig.sampleRate('0.1'), 0.1);
      expect(AppConfig.sampleRate(' 1 '), 1.0);
      expect(AppConfig.sampleRate('0'), 0.0);
      expect(AppConfig.sampleRate(''), isNull);
      expect(AppConfig.sampleRate('1.5'), isNull);
      expect(AppConfig.sampleRate('-0.1'), isNull);
      expect(AppConfig.sampleRate('ten'), isNull);
    });
  });
}
