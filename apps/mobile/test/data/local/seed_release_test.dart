/// The demo seed (default PINs) can never run in a release build: release
/// builds are cloud-only (AppConfig), and the seed itself refuses as well.
library;

import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/seed_data.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the demo seed refuses a release build and writes nothing', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await expectLater(
      LocalSeed.applyIfEmpty(db, releaseBuild: true),
      throwsA(isA<StateError>()),
    );
    expect(await db.select(db.users).get(), isEmpty, reason: 'no demo users');
    expect(await db.select(db.activities).get(), isEmpty);
  });

  test('a development build still gets the demo catalog and users', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await LocalSeed.applyIfEmpty(db, releaseBuild: false);
    expect(await db.select(db.users).get(), hasLength(2));
  });
}
