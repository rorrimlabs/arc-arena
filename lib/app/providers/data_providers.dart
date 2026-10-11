/// Riverpod wiring for the data layer and the live-time ticker.
library;

import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/sync/cloud_binding.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_booking_repository.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_controller_allocation_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_group_session_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/repositories/booking_repository.dart';
import 'package:arena_ops/domain/entities/activity.dart';
import 'package:arena_ops/domain/entities/controller.dart';
import 'package:arena_ops/domain/entities/customer.dart';
import 'package:arena_ops/domain/entities/game.dart';
import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/entities/payment.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/pricing/pricing_snapshot.dart';
import 'package:arena_ops/domain/repositories/catalog_repository.dart';
import 'package:arena_ops/domain/repositories/customer_repository.dart';
import 'package:arena_ops/domain/repositories/group_session_repository.dart';
import 'package:arena_ops/domain/repositories/session_repository.dart';
import 'package:arena_ops/domain/services/pad_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The open database. Overridden in `main()` with a seeded instance (and in
/// tests with an in-memory one), so it must never be read without an override.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => LocalSessionRepository(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
    ref.watch(syncRecorderProvider),
  ),
);

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => LocalCustomerRepository(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
    ref.watch(syncRecorderProvider),
  ),
);

final groupSessionRepositoryProvider = Provider<GroupSessionRepository>(
  (ref) => LocalGroupSessionRepository(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
    ref.watch(syncRecorderProvider),
  ),
);

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => LocalCatalogRepository(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
    ref.watch(syncRecorderProvider),
  ),
);

final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => LocalBookingRepository(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
    ref.watch(syncRecorderProvider),
  ),
);

/// Owner dashboard view + pad inventory flows (move/borrow, RIFT mode lock).
/// Allocation itself happens through the session/group repositories.
final controllerAllocationRepositoryProvider =
    Provider<LocalControllerAllocationRepository>(
  (ref) => LocalControllerAllocationRepository(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
    ref.watch(syncRecorderProvider),
  ),
);

final upcomingBookingsProvider = StreamProvider.autoDispose<List<Booking>>(
  (ref) => ref.watch(bookingRepositoryProvider).watchUpcoming(),
);

/// Emits the current (clock-corrected) time every second to drive live timers.
/// This is display only — billing truth comes from the stored timestamps.
final nowProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  final clock = ref.watch(clockProvider);
  yield clock.now();
  yield* Stream.periodic(const Duration(seconds: 1), (_) => clock.now());
});

final activeSessionsProvider = StreamProvider.autoDispose<List<ActiveSession>>(
  (ref) => ref.watch(sessionRepositoryProvider).watchActive(),
);

/// Finished sessions still owing money — the floor's checkout queue (§3, §10).
final awaitingPaymentProvider = StreamProvider.autoDispose<List<Session>>(
  (ref) => ref.watch(sessionRepositoryProvider).watchAwaitingPayment(),
);

/// Open segments drive resource occupancy on the floor (spec §1, §24).
final openSegmentsProvider = StreamProvider.autoDispose<List<SessionSegment>>(
  (ref) => ref.watch(sessionRepositoryProvider).watchOpenSegments(),
);

/// Active group sessions (group feature §1), each with their assignments.
final activeGroupsProvider =
    StreamProvider.autoDispose<List<ActiveGroupSession>>(
  (ref) => ref.watch(groupSessionRepositoryProvider).watchActiveGroups(),
);

/// Open group assignments drive group occupancy on the floor (group §7).
final openGroupAssignmentsProvider =
    StreamProvider.autoDispose<List<GroupAssignment>>(
  (ref) => ref.watch(groupSessionRepositoryProvider).watchOpenAssignments(),
);

/// The controller inventory, live — marking a pad faulty must show on the
/// floor immediately.
final controllersProvider = StreamProvider.autoDispose<List<Controller>>(
  (ref) => ref.watch(catalogRepositoryProvider).watchControllers(),
);

/// Who holds which physical pad right now, live — drives the staff pad
/// pickers so a pad taken on another device/screen greys out immediately.
final openPadAllocationsProvider =
    StreamProvider.autoDispose<List<OpenPadAllocation>>(
  (ref) => ref.watch(controllerAllocationRepositoryProvider)
      .watchOpenPadAllocations(),
);

/// Usable controllers physically present at each station, keyed by resource id.
/// This is the *supply* side of allocation; what is already committed to open
/// sessions is subtracted separately.
final usableControllersByStationProvider =
    Provider.autoDispose<Map<String, int>>((ref) {
  final all = ref.watch(controllersProvider).value ?? const <Controller>[];
  final counts = <String, int>{};
  for (final c in all) {
    if (!c.status.isUsable) continue;
    counts[c.currentResourceId] = (counts[c.currentResourceId] ?? 0) + 1;
  }
  return counts;
});

/// Active games with their availability on a given resource (spec §5).
final gamesForResourceProvider =
    FutureProvider.autoDispose.family<List<GameOnResource>, String>(
  (ref, resourceId) =>
      ref.watch(catalogRepositoryProvider).gamesForResource(resourceId),
);

/// Resources with a game's availability on each (spec §19).
final resourcesForGameProvider =
    FutureProvider.autoDispose.family<List<ResourceForGame>, String>(
  (ref, gameId) => ref.watch(catalogRepositoryProvider).resourcesForGame(gameId),
);

final recentCustomersProvider = StreamProvider.autoDispose<List<Customer>>(
  (ref) => ref.watch(customerRepositoryProvider).watchRecent(),
);

final activitiesProvider = FutureProvider.autoDispose<List<Activity>>(
  (ref) => ref.watch(catalogRepositoryProvider).activities(),
);

final resourcesProvider = FutureProvider.autoDispose<List<Resource>>(
  (ref) => ref.watch(catalogRepositoryProvider).resources(),
);

final pricingSnapshotProvider = FutureProvider.autoDispose<PricingSnapshot>(
  (ref) => ref.watch(catalogRepositoryProvider).currentSnapshot(),
);

final activeGamesProvider = FutureProvider.autoDispose<List<Game>>(
  (ref) => ref.watch(catalogRepositoryProvider).games(activeOnly: true),
);

final allGamesProvider = FutureProvider.autoDispose<List<Game>>(
  (ref) => ref.watch(catalogRepositoryProvider).games(),
);

final gameCategoriesProvider = FutureProvider.autoDispose<List<GameCategory>>(
  (ref) => ref.watch(catalogRepositoryProvider).categories(),
);

/// Controls for a specific game.
final gameControlsProvider =
    FutureProvider.autoDispose.family<List<GameControl>, String>(
  (ref, gameId) => ref.watch(catalogRepositoryProvider).controlsFor(gameId),
);

/// Payment rows for one session (append-only history).
final paymentsForSessionProvider =
    StreamProvider.autoDispose.family<List<Payment>, String>(
  (ref, id) => ref.watch(sessionRepositoryProvider).watchPaymentsFor(id),
);

/// A customer by id (for showing names on cards).
final customerByIdProvider =
    FutureProvider.autoDispose.family<Customer?, String>(
  (ref, id) => ref.watch(customerRepositoryProvider).getById(id),
);

/// A game by id (for showing names on cards).
final gameByIdProvider = FutureProvider.autoDispose.family<Game?, String>(
  (ref, id) => ref.watch(catalogRepositoryProvider).gameById(id),
);
