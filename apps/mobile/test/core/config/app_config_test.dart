/// Each flavor runs only in its own environment: dev never ships and reaches
/// only the local stack, prod never runs in debug, and staging / prod reach
/// only the hosts pinned for them — so a production build can never point at
/// staging. No build ships a privileged key or a non-TLS server.
library;

import 'dart:convert';

import 'package:arena_ops/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

String _jwt(String role, {String? ref}) {
  String part(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.'
      '${part({'role': role, 'iss': 'supabase', 'ref': ?ref})}.sig';
}

const _publishable = 'sb_publishable_TESTONLY_not_a_real_key';
const _stagingHost = 'stagingtestref.supabase.co';
const _prodHost = 'prodtestref.supabase.co';
const _staging = 'https://$_stagingHost';
const _prod = 'https://$_prodHost';
const _hosts = {
  'staging': {_stagingHost},
  'production': {_prodHost},
};

AppConfig _cloud(
  String url,
  String key, {
  String flavor = 'prod',
  String environment = 'production',
  Map<String, Set<String>> hosts = _hosts,
}) => AppConfig(
  backend: Backend.supabase,
  supabaseUrl: url,
  supabaseAnonKey: key,
  backendSetting: 'supabase',
  flavor: flavor,
  environment: environment,
  hostedHosts: hosts,
);

AppConfig _staged(String url, String key) =>
    _cloud(url, key, flavor: 'staging', environment: 'staging');

AppConfig _dev(String url) =>
    _cloud(url, _publishable, flavor: 'dev', environment: 'development');

void main() {
  group('local mode (dev flavor)', () {
    test('a debug or profile build without defines runs local mode', () {
      for (final flavor in [null, 'dev']) {
        final c = AppConfig(backend: Backend.local, flavor: flavor);
        expect(c.problemFor(mode: BuildMode.debug), isNull, reason: flavor);
        expect(c.problemFor(mode: BuildMode.profile), isNull, reason: flavor);
      }
    });

    test('a release build without defines refuses to start', () {
      const c = AppConfig(backend: Backend.local, backendSetting: '');
      expect(c.problemFor(mode: BuildMode.release), contains('dev flavor'));
    });

    test(
      'a release build refuses local mode even when asked for explicitly',
      () {
        const c = AppConfig(backend: Backend.local, backendSetting: 'local');
        expect(
          c.problemFor(mode: BuildMode.release),
          contains('development only'),
        );
      },
    );

    test('an unknown AO_BACKEND is refused instead of meaning local', () {
      const c = AppConfig(backend: Backend.local, backendSetting: 'supbase');
      for (final mode in BuildMode.values) {
        expect(c.problemFor(mode: mode), contains('Unknown AO_BACKEND'));
      }
    });
  });

  group('flavors and environments', () {
    test('AO_ENVIRONMENT must match the flavor', () {
      expect(
        _cloud(
          _staging,
          _publishable,
          flavor: 'staging',
        ).problemFor(mode: BuildMode.release),
        contains('AO_ENVIRONMENT=staging'),
      );
      expect(
        _cloud(
          _prod,
          _publishable,
          environment: 'staging',
        ).problemFor(mode: BuildMode.release),
        contains('AO_ENVIRONMENT=production'),
      );
      expect(
        const AppConfig(
          backend: Backend.local,
          flavor: 'dev',
          environment: 'production',
        ).problemFor(mode: BuildMode.debug),
        contains('AO_ENVIRONMENT=development'),
      );
      expect(
        const AppConfig(
          backend: Backend.local,
          flavor: 'staging',
        ).problemFor(mode: BuildMode.debug),
        contains('AO_ENVIRONMENT=staging'),
        reason: 'a staging build without its define file',
      );
    });

    test('an unknown flavor is refused', () {
      const c = AppConfig(backend: Backend.local, flavor: 'qa');
      expect(c.problemFor(mode: BuildMode.debug), contains('Unknown flavor'));
    });

    test('the prod flavor never runs as a debug build; staging may', () {
      expect(
        _cloud(_prod, _publishable).problemFor(mode: BuildMode.debug),
        contains('never runs as a debug build'),
      );
      expect(
        _cloud(_prod, _publishable).problemFor(mode: BuildMode.profile),
        isNull,
      );
      expect(
        _staged(_staging, _publishable).problemFor(mode: BuildMode.debug),
        isNull,
      );
    });

    test('the dev flavor reaches only development hosts', () {
      for (final url in [_staging, _prod]) {
        expect(
          _dev(url).problemFor(mode: BuildMode.debug),
          contains('local Supabase stack only'),
          reason: url,
        );
      }
    });

    test('dev debug and profile builds may use the local stack', () {
      for (final url in [
        'http://127.0.0.1:54431',
        'http://10.0.2.2:54431',
        'http://mac.local:54431',
      ]) {
        expect(_dev(url).problemFor(mode: BuildMode.debug), isNull);
        expect(_dev(url).problemFor(mode: BuildMode.profile), isNull);
      }
      expect(
        _dev('http://127.0.0.1:54431').problemFor(mode: BuildMode.release),
        contains('dev flavor'),
      );
    });
  });

  group('hosted builds (staging, prod)', () {
    test('the pinned project with a publishable or its own anon key', () {
      for (final mode in [BuildMode.profile, BuildMode.release]) {
        expect(_cloud(_prod, _publishable).problemFor(mode: mode), isNull);
        expect(
          _cloud(
            _prod,
            _jwt('anon', ref: 'prodtestref'),
          ).problemFor(mode: mode),
          isNull,
          reason: 'legacy anon JWT of the same project',
        );
        expect(_staged(_staging, _publishable).problemFor(mode: mode), isNull);
      }
    });

    test('production never reaches staging, nor staging production', () {
      expect(
        _cloud(_staging, _publishable).problemFor(mode: BuildMode.release),
        contains('not the production project'),
      );
      expect(
        _staged(_prod, _publishable).problemFor(mode: BuildMode.release),
        contains('not the staging project'),
      );
    });

    test('an environment with no pinned project refuses to start', () {
      const none = {'staging': <String>{}, 'production': <String>{}};
      expect(
        _cloud(
          _prod,
          _publishable,
          hosts: none,
        ).problemFor(mode: BuildMode.release),
        contains('No production Supabase project'),
      );
    });

    test('the pinned staging and production hosts never overlap', () {
      final pins = AppConfig.hostedSupabaseHosts;
      expect(pins['staging']!.intersection(pins['production']!), isEmpty);
    });

    test('a legacy anon key of another project is refused', () {
      expect(
        _cloud(
          _prod,
          _jwt('anon', ref: 'stagingtestref'),
        ).problemFor(mode: BuildMode.release),
        contains('different project'),
      );
    });

    test('a hosted flavor without cloud configuration is refused', () {
      const c = AppConfig(
        backend: Backend.local,
        flavor: 'prod',
        environment: 'production',
      );
      expect(
        c.problemFor(mode: BuildMode.release),
        contains('no cloud configuration'),
      );
    });

    test('missing URL or key is refused in any build', () {
      const c = AppConfig(
        backend: Backend.supabase,
        backendSetting: 'supabase',
      );
      expect(c.problemFor(mode: BuildMode.debug), contains('missing'));
    });

    test('a secret or service-role key is refused, without echoing it', () {
      const secret = 'sb_secret_SHOULD_NEVER_SHIP_123';
      final p1 = _staged(_staging, secret).problemFor(mode: BuildMode.debug)!;
      expect(p1, contains('SECRET'));
      expect(p1, isNot(contains(secret)));
      final service = _jwt('service_role');
      final p2 = _staged(_staging, service).problemFor(mode: BuildMode.debug)!;
      expect(p2, contains('SERVICE ROLE'));
      expect(p2, isNot(contains(service)));
      expect(
        _staged(_staging, 'whatever').problemFor(mode: BuildMode.debug),
        contains('not a Supabase publishable key'),
      );
      expect(
        _dev('http://127.0.0.1:54431').problemFor(mode: BuildMode.debug),
        isNull,
      );
      expect(
        _cloud(
          'http://127.0.0.1:54431',
          secret,
          flavor: 'dev',
          environment: 'development',
        ).problemFor(mode: BuildMode.debug),
        contains('SECRET'),
        reason: 'the dev flavor checks the key too',
      );
    });

    test('hosted builds refuse development and non-TLS servers', () {
      for (final url in [
        'http://127.0.0.1:54431',
        'http://prodtestref.supabase.co',
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
          _cloud(url, _publishable).problemFor(mode: BuildMode.release),
          isNotNull,
          reason: url,
        );
        expect(
          _staged(url, _publishable).problemFor(mode: BuildMode.debug),
          isNotNull,
          reason: url,
        );
      }
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
        final c = _cloud(_prod, _publishable);
        expect(c.sentryDsn, isNull);
        expect(c.problemFor(mode: BuildMode.release), isNull);
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
