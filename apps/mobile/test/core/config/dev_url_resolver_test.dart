import 'package:arena_ops/core/config/dev_url_resolver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveDevBackendUrl', () {
    test('returns original URL on non-Android platforms', () async {
      final resolved = await resolveDevBackendUrl(
        'http://127.0.0.1:54431',
        platform: TargetPlatform.iOS,
      );
      expect(resolved, 'http://127.0.0.1:54431');
    });

    test('returns original URL in release builds', () async {
      final resolved = await resolveDevBackendUrl(
        'http://127.0.0.1:54431',
        platform: TargetPlatform.android,
        releaseBuild: true,
      );
      expect(resolved, 'http://127.0.0.1:54431');
    });

    test('returns original URL for hosted/production endpoints', () async {
      final resolved = await resolveDevBackendUrl(
        'https://xyz.supabase.co',
        platform: TargetPlatform.android,
      );
      expect(resolved, 'https://xyz.supabase.co');
    });
  });
}
