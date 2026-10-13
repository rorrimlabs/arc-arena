import 'dart:convert';

import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/auth/pin_credential.dart';
import 'package:arena_ops/domain/pricing/billing_policy.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;

/// Seeds the DEVELOPMENT local-only database on first run: a demo catalog
/// (activities, resources, rates, policy, games, controls) and two demo users
/// with well-known PINs. Never used in cloud mode (cloud data comes only from
/// sync_pull), and refused in release builds: a release never starts in local
/// mode (AppConfig.problemFor), and this is the second lock, so demo PINs can
/// never be usable in a production release. Operational tables start empty.
class LocalSeed {
  const LocalSeed._();

  static Future<void> applyIfEmpty(
    AppDatabase db, {
    bool releaseBuild = kReleaseMode,
  }) async {
    final existing = await db.select(db.activities).get();
    if (existing.isNotEmpty) return;
    await apply(db, releaseBuild: releaseBuild);
  }

  static Future<void> apply(
    AppDatabase db, {
    bool releaseBuild = kReleaseMode,
  }) async {
    if (releaseBuild) {
      throw StateError(
        'The demo seed (default PINs) never runs in a release '
        'build; release builds are cloud-only.',
      );
    }
    // Seed rows are catalog facts, not operational ones; a wall-clock stamp is
    // only needed so `updatedAt` is non-null.
    final now = DateTime.now().toUtc();
    await db.transaction(() async {
      // One owner + one staff (development demo users). Default PINs:
      // owner 1111 · staff 2222 (development only). Hashed on the way in, exactly
      // like a PIN typed in Settings, so no plaintext PIN is ever written.
      final ownerPin = PinCredential.create('1111');
      final staffPin = PinCredential.create('2222');
      await db.batch((b) {
        b.insertAll(db.users, [
          UsersCompanion.insert(
            id: 'u1',
            name: 'Prashanth',
            perms: Permission.codesOf(Permission.all),
            sortOrder: const Value(1),
            pinSalt: Value(ownerPin.salt),
            pinHash: Value(ownerPin.hash),
            pinIterations: Value(ownerPin.iterations),
          ),
          UsersCompanion.insert(
            id: 'u2',
            name: 'Alan Benny',
            perms: Permission.codesOf({
              Permission.start,
              Permission.bill,
              Permission.discount,
              Permission.members,
            }),
            sortOrder: const Value(2),
            pinSalt: Value(staffPin.salt),
            pinHash: Value(staffPin.hash),
            pinIterations: Value(staffPin.iterations),
          ),
        ]);
      });

      // Activities -----------------------------------------------------------
      await db.batch((b) {
        b.insertAll(db.activities, [
          ActivitiesCompanion.insert(
            id: 'ps5',
            code: 'PS5',
            name: 'PlayStation 5',
            usesControllers: true,
            usesGames: true,
            durationModel: 'hourly',
            happyHourEligible: true,
            sortOrder: const Value(1),
          ),
          ActivitiesCompanion.insert(
            id: 'vr',
            code: 'VR',
            name: 'VR (PSVR2)',
            usesControllers: false,
            usesGames: true,
            durationModel: 'unit',
            happyHourEligible: false,
            sortOrder: const Value(2),
          ),
          ActivitiesCompanion.insert(
            id: 'pool',
            code: 'POOL',
            name: 'Pool',
            usesControllers: false,
            usesGames: false,
            durationModel: 'hourly',
            happyHourEligible: true,
            sortOrder: const Value(3),
          ),
          ActivitiesCompanion.insert(
            id: 'lounge',
            code: 'LOUNGE',
            name: 'Private Lounge',
            usesControllers: false,
            usesGames: false,
            durationModel: 'flat_hourly',
            happyHourEligible: false,
            sortOrder: const Value(4),
          ),
        ]);

        // Resources ------------------------------------------------------------
        b.insertAll(db.resources, [
          ResourcesCompanion.insert(
            id: 'hex',
            name: 'HEX',
            kind: 'station',
            sortOrder: const Value(1),
          ),
          ResourcesCompanion.insert(
            id: 'void',
            name: 'VOID',
            kind: 'station',
            sortOrder: const Value(2),
          ),
          ResourcesCompanion.insert(
            id: 'ghost',
            name: 'GHOST',
            kind: 'station',
            sortOrder: const Value(3),
          ),
          ResourcesCompanion.insert(
            id: 'rift',
            name: 'RIFT',
            kind: 'station',
            sortOrder: const Value(4),
          ),
          ResourcesCompanion.insert(
            id: 'pool1',
            name: 'Pool Table 1',
            kind: 'table',
            sortOrder: const Value(5),
          ),
          ResourcesCompanion.insert(
            id: 'lounge1',
            name: 'Private Lounge',
            kind: 'room',
            sortOrder: const Value(6),
          ),
        ]);

        // Controllers — two per PS5 station, eight in all. `label` is what is
        // written on the pad, because that is what staff are told to carry.
        b.insertAll(db.controllers, [
          for (final station in const ['hex', 'void', 'ghost', 'rift'])
            for (final n in const [1, 2])
              ControllersCompanion.insert(
                id: 'ctl_${station}_$n',
                label: '${station.toUpperCase()}-$n',
                homeResourceId: station,
                currentResourceId: station,
                updatedAt: now,
              ),
        ]);

        // Resource ↔ activity. RIFT hosts both PS5 and VR.
        b.insertAll(db.resourceActivities, [
          ResourceActivitiesCompanion.insert(
            resourceId: 'hex',
            activityCode: 'PS5',
          ),
          ResourceActivitiesCompanion.insert(
            resourceId: 'void',
            activityCode: 'PS5',
          ),
          ResourceActivitiesCompanion.insert(
            resourceId: 'ghost',
            activityCode: 'PS5',
          ),
          ResourceActivitiesCompanion.insert(
            resourceId: 'rift',
            activityCode: 'PS5',
          ),
          ResourceActivitiesCompanion.insert(
            resourceId: 'rift',
            activityCode: 'VR',
          ),
          ResourceActivitiesCompanion.insert(
            resourceId: 'pool1',
            activityCode: 'POOL',
          ),
          ResourceActivitiesCompanion.insert(
            resourceId: 'lounge1',
            activityCode: 'LOUNGE',
          ),
        ]);

        // Rates (paise) --------------------------------------------------------
        b.insertAll(db.rates, _rates());

        // Billing policy -------------------------------------------------------
        b.insert(
          db.billingPolicies,
          BillingPoliciesCompanion.insert(id: 'default', json: _policyJson()),
        );

        // Game categories ------------------------------------------------------
        const cats = [
          ['cat_football', 'Football', 1],
          ['cat_fighting', 'Fighting', 2],
          ['cat_wrestling', 'Wrestling', 3],
          ['cat_racing', 'Racing', 4],
          ['cat_action', 'Action', 5],
          ['cat_shooter', 'Shooter', 6],
          ['cat_sports', 'Sports', 7],
          ['cat_vr', 'VR', 8],
          ['cat_other', 'Other', 9],
        ];
        b.insertAll(db.gameCategories, [
          for (final c in cats)
            GameCategoriesCompanion.insert(
              id: c[0] as String,
              name: c[1] as String,
              sortOrder: Value(c[2] as int),
            ),
        ]);

        // Games ----------------------------------------------------------------
        b.insertAll(db.games, _games());

        // Game ↔ resource compatibility (spec §4) ------------------------------
        b.insertAll(db.gameResources, _compat());

        // Controls for EA FC ---------------------------------------------------
        b.insertAll(db.gameControls, _eafcControls());
      });
    });
  }

  static List<RatesCompanion> _rates() {
    RatesCompanion ps5(int c, String band, int paise) => RatesCompanion.insert(
      id: 'ps5_${c}_$band',
      activityCode: 'PS5',
      band: band,
      controllerCount: Value(c),
      unitMinutes: 60,
      pricePaise: paise,
    );
    return [
      ps5(1, 'standard', 15000),
      ps5(1, 'happy', 12000),
      ps5(2, 'standard', 28000),
      ps5(2, 'happy', 22000),
      ps5(3, 'standard', 39000),
      ps5(3, 'happy', 31000),
      ps5(4, 'standard', 48000),
      ps5(4, 'happy', 38000),
      RatesCompanion.insert(
        id: 'vr_std',
        activityCode: 'VR',
        band: 'standard',
        unitMinutes: 30,
        pricePaise: 20000,
      ),
      RatesCompanion.insert(
        id: 'pool_std',
        activityCode: 'POOL',
        band: 'standard',
        unitMinutes: 60,
        pricePaise: 27500,
      ),
      RatesCompanion.insert(
        id: 'pool_happy',
        activityCode: 'POOL',
        band: 'happy',
        unitMinutes: 60,
        pricePaise: 22000,
      ),
      RatesCompanion.insert(
        id: 'lounge_std',
        activityCode: 'LOUNGE',
        band: 'standard',
        unitMinutes: 60,
        pricePaise: 200000,
      ),
    ];
  }

  // Encoded through the domain object so the defaults stay in one place.
  static String _policyJson() => jsonEncode(BillingPolicy.defaults.toJson());

  static List<GamesCompanion> _games() {
    GamesCompanion g(
      String id,
      String name,
      String cat,
      List<String> platforms,
      String playerMode,
      int maxLocalPlayers, {
      List<String> aliases = const [],
    }) => GamesCompanion.insert(
      id: id,
      name: name,
      aliases: aliases,
      categoryId: Value(cat),
      platforms: platforms,
      playerMode: Value(playerMode),
      maxLocalPlayers: Value(maxLocalPlayers),
    );
    return [
      g(
        'g_eafc',
        'EA SPORTS FC 25',
        'cat_football',
        ['PS5'],
        'both',
        4,
        aliases: ['EA FC', 'FIFA'],
      ),
      g(
        'g_efootball',
        'eFootball',
        'cat_football',
        ['PS5'],
        'both',
        2,
        aliases: ['PES'],
      ),
      g('g_tekken8', 'Tekken 8', 'cat_fighting', ['PS5'], 'local', 2),
      g(
        'g_mk1',
        'Mortal Kombat 1',
        'cat_fighting',
        ['PS5'],
        'local',
        2,
        aliases: ['MK1'],
      ),
      g(
        'g_sf6',
        'Street Fighter 6',
        'cat_fighting',
        ['PS5'],
        'local',
        2,
        aliases: ['SF6'],
      ),
      g('g_wwe', 'WWE 2K24', 'cat_wrestling', ['PS5'], 'local', 4),
      g(
        'g_gt7',
        'Gran Turismo 7',
        'cat_racing',
        ['PS5', 'PSVR2'],
        'both',
        2,
        aliases: ['GT7'],
      ),
      g('g_f1', 'F1 24', 'cat_racing', ['PS5'], 'both', 2),
      g(
        'g_gow',
        'God of War Ragnarok',
        'cat_action',
        ['PS5'],
        'single',
        1,
        aliases: ['GOW'],
      ),
      g(
        'g_spiderman',
        "Marvel's Spider-Man 2",
        'cat_action',
        ['PS5'],
        'single',
        1,
        aliases: ['Spiderman 2'],
      ),
      g(
        'g_gtav',
        'GTA V',
        'cat_action',
        ['PS5'],
        'single',
        1,
        aliases: ['Grand Theft Auto V'],
      ),
      g(
        'g_cod',
        'Call of Duty: MW III',
        'cat_shooter',
        ['PS5'],
        'both',
        2,
        aliases: ['COD'],
      ),
      g('g_fortnite', 'Fortnite', 'cat_shooter', ['PS5'], 'online', 1),
      g('g_nba', 'NBA 2K24', 'cat_sports', ['PS5'], 'local', 4),
      g('g_beatsaber', 'Beat Saber', 'cat_vr', ['PSVR2'], 'single', 1),
      g('g_swordsman', 'Swordsman VR', 'cat_vr', ['PSVR2'], 'single', 1),
    ];
  }

  // Compatibility (spec §4). PS5 games default playable on the four PS5 stations;
  // VR games only on RIFT. A few overrides match the spec's worked examples.
  static List<GameResourcesCompanion> _compat() {
    const ps5Stations = ['hex', 'void', 'ghost', 'rift'];
    const ps5Games = [
      'g_eafc',
      'g_efootball',
      'g_tekken8',
      'g_mk1',
      'g_sf6',
      'g_wwe',
      'g_gt7',
      'g_f1',
      'g_gow',
      'g_spiderman',
      'g_gtav',
      'g_cod',
      'g_fortnite',
      'g_nba',
    ];
    const vrGames = ['g_beatsaber', 'g_swordsman'];

    // gameId -> { resourceId -> status } overrides (default elsewhere = playable).
    const overrides = <String, Map<String, String>>{
      'g_eafc': {'ghost': 'not_playable'}, // §4
      'g_tekken8': {'rift': 'not_playable'}, // §4
      'g_gtav': {'hex': 'not_playable'}, // §5 View Games example
    };

    final rows = <GameResourcesCompanion>[];
    for (final game in ps5Games) {
      for (final res in ps5Stations) {
        final status = overrides[game]?[res] ?? 'playable';
        rows.add(
          GameResourcesCompanion.insert(
            gameId: game,
            resourceId: res,
            status: status,
          ),
        );
      }
    }
    for (final game in vrGames) {
      rows.add(
        GameResourcesCompanion.insert(
          gameId: game,
          resourceId: 'rift',
          status: 'playable',
        ),
      );
    }
    return rows;
  }

  static List<GameControlsCompanion> _eafcControls() {
    GameControlsCompanion c(
      int i,
      String section,
      String action,
      List<String> buttons, {
      String? explanation,
    }) => GameControlsCompanion.insert(
      id: 'ctrl_eafc_$i',
      gameId: 'g_eafc',
      section: section,
      action: action,
      buttons: buttons,
      explanation: Value(explanation),
      sortOrder: Value(i),
    );
    return [
      c(1, 'Attacking', 'Shoot', [
        'CIRCLE',
      ], explanation: 'Hold longer for more power'),
      c(2, 'Attacking', 'Short Pass', ['CROSS']),
      c(3, 'Attacking', 'Through Ball', ['TRIANGLE']),
      c(4, 'Attacking', 'Lob / Cross', ['SQUARE']),
      c(5, 'Attacking', 'Sprint', ['R2'], explanation: 'Hold while moving'),
      c(6, 'Defending', 'Tackle', ['CIRCLE']),
      c(7, 'Defending', 'Jockey', ['L2']),
      c(8, 'Defending', 'Switch Player', ['L1']),
    ];
  }
}
