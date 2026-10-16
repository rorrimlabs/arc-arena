/// Pricing rules arrive from the server's change feed (`pricing_rules` rows
/// and their tombstones) and become part of the next session's snapshot;
/// activity rows no longer carry the retired pricing flag.
library;

import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/sync/sync_applier.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late LocalCatalogRepository catalog;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    catalog = LocalCatalogRepository(db);
  });
  tearDown(() async => db.close());

  Future<void> pull(List<Map<String, dynamic>> changes) =>
      db.transaction(() => SyncApplier(db).applyChanges(changes));

  /// A `pricing_rules` row as `sync_pull` sends it (`to_jsonb(row)`).
  Map<String, dynamic> ruleRow(String id,
          {String name = 'Weekday afternoons', int priority = 1, bool active = true}) =>
      {
        't': 'pricing_rules',
        'r': {
          'id': id, 'arena_id': 'arena', 'name': name, 'priority': priority, 'active': active,
          'days': [2, 3, 4, 5], 'start_min': 840, 'end_min': 1020, 'holiday_mode': 'skip',
          'valid_from': '2026-10-01', 'valid_until': null, 'activity_codes': ['PS5', 'POOL'],
          'adjust_kind': 'percent', 'adjust_value': -20,
          'created_at': '2026-10-14T08:00:00+00:00', 'updated_at': '2026-10-14T08:00:00+00:00',
          'sync_xid': '812',
        },
      };

  test('active rules from the feed are frozen into the next snapshot, in order', () async {
    await pull([
      ruleRow('b', name: 'Evenings', priority: 2),
      ruleRow('a'),
      ruleRow('off', active: false),
    ]);
    final snap = await catalog.currentSnapshot();
    expect(snap.rules.map((r) => r.id), ['a', 'b']);
    final a = snap.rules.first;
    expect(a.holidayMode, RuleHolidayMode.skip);
    expect(a.activityCodes, ['PS5', 'POOL']);
    expect(a.validFrom?.iso, '2026-10-01');
    expect((snap.toJson()['rules'] as List).first, {
      'id': 'a', 'name': 'Weekday afternoons', 'priority': 1, 'days': [2, 3, 4, 5],
      'start_min': 840, 'end_min': 1020, 'holiday_mode': 'skip', 'valid_from': '2026-10-01',
      'valid_until': null, 'activity_codes': ['PS5', 'POOL'], 'adjust_kind': 'percent',
      'adjust_value': -20,
    });
  });

  test('an edited rule is replaced and a deleted one goes', () async {
    await pull([ruleRow('a'), ruleRow('b')]);
    final edited = ruleRow('a');
    (edited['r'] as Map<String, dynamic>)['adjust_value'] = -30;
    await pull([
      edited,
      {
        't': '_tombstone',
        'r': {'table': 'pricing_rules', 'row': (ruleRow('b')['r'] as Map<String, dynamic>)},
      },
    ]);
    final snap = await catalog.currentSnapshot();
    expect(snap.rules.single.id, 'a');
    expect(snap.rules.single.adjustValue, -30);
  });

  test('no rules → the snapshot has no rules key', () async {
    expect((await catalog.currentSnapshot()).toJson().containsKey('rules'), isFalse);
  });

  test('an activity row without the retired pricing flag applies', () async {
    await pull([
      {
        't': 'activities',
        'r': {
          'id': 'act1', 'arena_id': 'arena', 'code': 'PS5', 'name': 'PlayStation 5',
          'uses_controllers': true, 'uses_games': true, 'duration_model': 'hourly',
          'sort_order': 1, 'active': true, 'sync_xid': '9',
        },
      },
    ]);
    final acts = await catalog.activities();
    expect(acts.single.code, 'PS5');
    // An update of the same row keeps working.
    await pull([
      {
        't': 'activities',
        'r': {
          'id': 'act1', 'arena_id': 'arena', 'code': 'PS5', 'name': 'PS5',
          'uses_controllers': true, 'uses_games': true, 'duration_model': 'hourly',
          'sort_order': 1, 'active': true, 'sync_xid': '10',
        },
      },
    ]);
    expect((await catalog.activities()).single.name, 'PS5');
    expect((await catalog.currentSnapshot()).activities.keys, ['PS5']);
  });
}
