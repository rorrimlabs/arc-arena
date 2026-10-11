import 'dart:convert';

import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/time/business_calendar.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/mappers.dart';
import 'package:arena_ops/domain/entities/activity.dart';
import 'package:arena_ops/domain/entities/controller.dart';
import 'package:arena_ops/domain/entities/game.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/pricing/billing_policy.dart';
import 'package:arena_ops/domain/pricing/pricing_snapshot.dart';
import 'package:arena_ops/domain/pricing/rate.dart';
import 'package:arena_ops/domain/repositories/catalog_repository.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:drift/drift.dart';

class LocalCatalogRepository implements CatalogRepository {
  LocalCatalogRepository(this._db, [this._clock = const SystemClock()]);

  final AppDatabase _db;
  final Clock _clock;

  @override
  Future<List<Activity>> activities() async {
    final rows = await (_db.select(_db.activities)
          ..where((t) => t.active.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    return rows.map(activityFromRow).toList();
  }

  @override
  Future<List<Resource>> resources() async {
    final rows = await (_db.select(_db.resources)
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    final links = await _db.select(_db.resourceActivities).get();
    final byResource = <String, List<String>>{};
    for (final l in links) {
      byResource.putIfAbsent(l.resourceId, () => []).add(l.activityCode);
    }
    return rows
        .map((r) => resourceFromRow(r, byResource[r.id] ?? const []))
        .toList();
  }

  @override
  Future<List<GameCategory>> categories() async {
    final rows = await (_db.select(_db.gameCategories)
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    return rows.map(categoryFromRow).toList();
  }

  @override
  Future<List<Game>> games({bool activeOnly = false}) async {
    final q = _db.select(_db.games);
    if (activeOnly) q.where((t) => t.active.equals(true));
    q.orderBy([
      // Recent games first (spec §22), then alphabetical.
      (t) => OrderingTerm(expression: t.lastPlayedAt, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.name),
    ]);
    final rows = await q.get();
    final cats = {for (final c in await categories()) c.id: c.name};
    return rows
        .map((r) => gameFromRow(r, categoryName: cats[r.categoryId]))
        .toList();
  }

  @override
  Future<Game?> gameById(String id) async {
    final row = await (_db.select(_db.games)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    final cats = {for (final c in await categories()) c.id: c.name};
    return gameFromRow(row, categoryName: cats[row.categoryId]);
  }

  @override
  Future<List<GameControl>> controlsFor(String gameId) async {
    final rows = await (_db.select(_db.gameControls)
          ..where((t) => t.gameId.equals(gameId))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    return rows.map(controlFromRow).toList();
  }

  @override
  Future<PricingSnapshot> currentSnapshot() async {
    final rateRows = await _db.select(_db.rates).get();
    final rates = rateRows
        .map((r) => Rate(
              activityCode: r.activityCode,
              band: Band.fromCode(r.band),
              controllerCount: r.controllerCount,
              unitMinutes: r.unitMinutes,
              price: Paise(r.pricePaise),
            ))
        .toList();

    final activityRows = await _db.select(_db.activities).get();
    final specs = activityRows
        .map((a) => ActivitySpec(
              code: a.code,
              durationModel: DurationModel.fromCode(a.durationModel),
              happyEligible: a.happyHourEligible,
            ))
        .toList();

    final policyRow = await (_db.select(_db.billingPolicies)
          ..where((t) => t.id.equals('default')))
        .getSingleOrNull();
    final policy = policyRow == null
        ? BillingPolicy.defaults
        : BillingPolicy.fromJson(
            jsonDecode(policyRow.json) as Map<String, dynamic>);

    final holidayRows = await _db.select(_db.holidays).get();
    final holidays = holidayRows.map((h) => IstDate.parse(h.day)).toSet();
    final closedDays = holidayRows
        .where((h) => h.closed)
        .map((h) => IstDate.parse(h.day))
        .toSet();

    return PricingSnapshot(
      rateCardName: 'Current',
      rates: rates,
      activities: specs,
      policy: policy,
      hours: await businessHours(),
      holidays: holidays,
      closedDays: closedDays,
    );
  }

  // --- compatibility (spec §4) ----------------------------------------------

  @override
  Future<List<GameResource>> compatibility() async =>
      (await _db.select(_db.gameResources).get())
          .map(gameResourceFromRow)
          .toList();

  @override
  Future<GameAvailability> availabilityOf(String gameId, String resourceId) async {
    final row = await (_db.select(_db.gameResources)
          ..where((t) => t.gameId.equals(gameId) & t.resourceId.equals(resourceId)))
        .getSingleOrNull();
    // Absence means "not installed" — a game is never globally available.
    return row == null
        ? GameAvailability.notInstalled
        : GameAvailability.fromCode(row.status);
  }

  @override
  Future<List<GameOnResource>> gamesForResource(String resourceId) async {
    final games = await this.games(activeOnly: true);
    final compat = await compatibility();
    final statusByGame = <String, GameAvailability>{
      for (final c in compat)
        if (c.resourceId == resourceId) c.gameId: c.status,
    };
    return [
      for (final g in games)
        (game: g, status: statusByGame[g.id] ?? GameAvailability.notInstalled),
    ];
  }

  @override
  Future<List<ResourceForGame>> resourcesForGame(String gameId) async {
    final resources = await this.resources();
    final compat = await compatibility();
    final statusByResource = <String, GameAvailability>{
      for (final c in compat)
        if (c.gameId == gameId) c.resourceId: c.status,
    };
    return [
      for (final r in resources)
        (resource: r, status: statusByResource[r.id] ?? GameAvailability.notInstalled),
    ];
  }

  @override
  Future<void> setCompatibility(
    String gameId,
    String resourceId,
    GameAvailability status, {
    String? notes,
  }) async {
    await _db.into(_db.gameResources).insertOnConflictUpdate(
          GameResourcesCompanion.insert(
            gameId: gameId,
            resourceId: resourceId,
            status: status.code,
            notes: Value(notes),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  @override
  Future<Game> upsertGame(Game game) async {
    await _db.into(_db.games).insertOnConflictUpdate(GamesCompanion(
          id: Value(game.id),
          name: Value(game.name),
          aliases: Value(game.aliases),
          categoryId: Value(game.categoryId),
          platforms: Value(game.platforms),
          playerMode: Value(game.playerMode.code),
          maxLocalPlayers: Value(game.maxLocalPlayers),
          active: Value(game.active),
          lastPlayedAt: Value(game.lastPlayedAt),
        ));
    return (await gameById(game.id))!;
  }

  @override
  Future<void> setGameActive(String id, {required bool active}) async {
    await (_db.update(_db.games)..where((t) => t.id.equals(id)))
        .write(GamesCompanion(active: Value(active)));
  }

  @override
  Future<void> replaceControls(String gameId, List<GameControl> controls) async {
    await _db.transaction(() async {
      await (_db.delete(_db.gameControls)..where((t) => t.gameId.equals(gameId)))
          .go();
      await _db.batch((b) {
        b.insertAll(_db.gameControls, [
          for (final c in controls)
            GameControlsCompanion.insert(
              id: c.id,
              gameId: gameId,
              section: c.section,
              action: c.action,
              buttons: c.buttons,
              explanation: Value(c.explanation),
              notes: Value(c.notes),
              imageUrl: Value(c.imageUrl),
              sortOrder: Value(c.sortOrder),
            ),
        ]);
      });
    });
  }

  // --- owner configuration (brief §2, §8) -----------------------------------

  static const _hoursKey = 'business_hours';

  @override
  Future<Resource> upsertResource(Resource resource) async {
    await _db.transaction(() async {
      await _db.into(_db.resources).insertOnConflictUpdate(ResourcesCompanion(
            id: Value(resource.id),
            name: Value(resource.name),
            kind: Value(resource.kind.code),
            status: Value(resource.status.code),
            sortOrder: Value(resource.sortOrder),
          ));
      // Replace the activity links so removing one actually removes it.
      await (_db.delete(_db.resourceActivities)
            ..where((t) => t.resourceId.equals(resource.id)))
          .go();
      await _db.batch((b) {
        b.insertAll(_db.resourceActivities, [
          for (final code in resource.activityCodes)
            ResourceActivitiesCompanion.insert(
              resourceId: resource.id,
              activityCode: code,
            ),
        ]);
      });
    });
    final all = await resources();
    return all.firstWhere((r) => r.id == resource.id);
  }

  @override
  Future<void> setResourceStatus(String id, ResourceStatus status) async {
    await (_db.update(_db.resources)..where((t) => t.id.equals(id)))
        .write(ResourcesCompanion(status: Value(status.code)));
  }

  @override
  Future<List<Rate>> rates() async {
    final rows = await _db.select(_db.rates).get();
    return rows
        .map((r) => Rate(
              activityCode: r.activityCode,
              band: Band.fromCode(r.band),
              controllerCount: r.controllerCount,
              unitMinutes: r.unitMinutes,
              price: Paise(r.pricePaise),
            ))
        .toList();
  }

  /// Stable id so editing a rate updates the row instead of adding a second
  /// one for the same (activity, band, controllers) key.
  String _rateId(String activityCode, Band band, int? controllerCount) =>
      '${activityCode.toLowerCase()}_${band.code}'
      '${controllerCount == null ? '' : '_$controllerCount'}';

  @override
  Future<void> upsertRate(Rate rate) async {
    // A rate is identified by (activity, band, controllers), not by its row
    // id — the seeded rows carry their own ids. Replacing by the natural key
    // is what keeps one price per combination instead of silently adding a
    // second row that the pricer would never reach.
    await _db.transaction(() async {
      await deleteRate(
        activityCode: rate.activityCode,
        band: rate.band,
        controllerCount: rate.controllerCount,
      );
      await _db.into(_db.rates).insert(RatesCompanion.insert(
            id: _rateId(rate.activityCode, rate.band, rate.controllerCount),
            activityCode: rate.activityCode,
            band: rate.band.code,
            controllerCount: Value(rate.controllerCount),
            unitMinutes: rate.unitMinutes,
            pricePaise: rate.price.value,
          ));
    });
  }

  @override
  Future<void> deleteRate({
    required String activityCode,
    required Band band,
    required int? controllerCount,
  }) async {
    await (_db.delete(_db.rates)
          ..where((t) =>
              t.activityCode.equals(activityCode) &
              t.band.equals(band.code) &
              (controllerCount == null
                  ? t.controllerCount.isNull()
                  : t.controllerCount.equals(controllerCount))))
        .go();
  }

  @override
  Future<BillingPolicy> policy() async {
    final row = await (_db.select(_db.billingPolicies)
          ..where((t) => t.id.equals('default')))
        .getSingleOrNull();
    return row == null
        ? BillingPolicy.defaults
        : BillingPolicy.fromJson(jsonDecode(row.json) as Map<String, dynamic>);
  }

  @override
  Future<void> savePolicy(BillingPolicy policy) async {
    await _db.into(_db.billingPolicies).insertOnConflictUpdate(
          BillingPoliciesCompanion.insert(
            id: 'default',
            json: jsonEncode(policy.toJson()),
          ),
        );
  }

  @override
  Future<BusinessHours> businessHours() async {
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(_hoursKey)))
        .getSingleOrNull();
    if (row == null) return BusinessHours.current();
    return BusinessHours.fromJson(jsonDecode(row.json) as Map<String, dynamic>);
  }

  @override
  Future<void> saveBusinessHours(BusinessHours hours) async {
    await _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: _hoursKey,
            json: jsonEncode(hours.toJson()),
          ),
        );
  }

  @override
  Future<List<Holiday>> holidays() async {
    final rows = await (_db.select(_db.holidays)
          ..orderBy([(t) => OrderingTerm(expression: t.day)]))
        .get();
    return [
      for (final r in rows)
        (day: IstDate.parse(r.day), name: r.name, closed: r.closed),
    ];
  }

  @override
  Future<void> upsertHoliday(Holiday holiday) async {
    await _db.into(_db.holidays).insertOnConflictUpdate(HolidaysCompanion.insert(
          day: holiday.day.iso,
          name: holiday.name,
          closed: Value(holiday.closed),
        ));
  }

  @override
  Future<void> deleteHoliday(IstDate day) async {
    await (_db.delete(_db.holidays)..where((t) => t.day.equals(day.iso))).go();
  }

  // --- controller inventory --------------------------------------------------

  SimpleSelectStatement<$ControllersTable, ControllerRow> _controllerQuery() =>
      _db.select(_db.controllers)
        ..orderBy([(t) => OrderingTerm(expression: t.label)]);

  @override
  Future<List<Controller>> controllers() async =>
      (await _controllerQuery().get()).map(controllerFromRow).toList();

  @override
  Stream<List<Controller>> watchControllers() =>
      _controllerQuery().watch().map((r) => r.map(controllerFromRow).toList());

  @override
  Future<Controller> upsertController(Controller controller) async {
    await _db.into(_db.controllers).insertOnConflictUpdate(ControllersCompanion(
          id: Value(controller.id),
          label: Value(controller.label),
          homeResourceId: Value(controller.homeResourceId),
          currentResourceId: Value(controller.currentResourceId),
          status: Value(controller.status.code),
          notes: Value(controller.notes),
          loanReturnTo: Value(controller.loanReturnTo),
          loanSessionRef: Value(controller.loanSessionRef),
          updatedAt: Value(_clock.now()),
        ));
    return (await controllers()).firstWhere((c) => c.id == controller.id);
  }

  @override
  Future<void> setControllerStatus(
    String id,
    ControllerStatus status, {
    String? notes,
  }) async {
    await (_db.update(_db.controllers)..where((t) => t.id.equals(id)))
        .write(ControllersCompanion(
      status: Value(status.code),
      notes: Value(notes),
      updatedAt: Value(_clock.now()),
    ));
  }
}
