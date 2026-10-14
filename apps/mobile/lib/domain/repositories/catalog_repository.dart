import 'package:arena_ops/core/time/business_calendar.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/entities/activity.dart';
import 'package:arena_ops/domain/entities/controller.dart';
import 'package:arena_ops/domain/entities/game.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/pricing/billing_policy.dart';
import 'package:arena_ops/domain/pricing/pricing_snapshot.dart';
import 'package:arena_ops/domain/pricing/rate.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/domain/value/floor_options.dart';

/// A game paired with its availability on a particular resource (spec §4–§5),
/// and the note explaining it ("disc scratched"), if any.
typedef GameOnResource = ({Game game, GameAvailability status, String? notes});

/// A resource paired with a game's availability on it (spec §19–§20).
typedef ResourceForGame = ({Resource resource, GameAvailability status});

/// A configured public holiday. [closed] means the centre does not trade that
/// day; otherwise it trades (pricing rules can include or skip the date).
typedef Holiday = ({IstDate day, String name, bool closed});

/// Read/write the catalog: activities, resources, rates, games, controls,
/// game↔resource compatibility, and the current pricing snapshot.
abstract interface class CatalogRepository {
  Future<List<Activity>> activities();
  Future<List<Resource>> resources();
  Future<List<GameCategory>> categories();

  Future<List<Game>> games({bool activeOnly});
  Future<Game?> gameById(String id);
  Future<List<GameControl>> controlsFor(String gameId);

  // Compatibility (spec §4).
  Future<List<GameResource>> compatibility();
  Future<GameAvailability> availabilityOf(String gameId, String resourceId);

  /// Active games with their status on [resourceId] (spec §5 View Games).
  Future<List<GameOnResource>> gamesForResource(String resourceId);

  /// Resources with the game's availability on each (spec §19 game-first).
  Future<List<ResourceForGame>> resourcesForGame(String gameId);

  Future<void> setCompatibility(
    String gameId,
    String resourceId,
    GameAvailability status, {
    String? notes,
  });

  /// Builds the immutable pricing environment captured at session start.
  Future<PricingSnapshot> currentSnapshot();

  // Game library editing (spec §3, §22–§23).
  Future<Game> upsertGame(Game game);
  Future<void> setGameActive(String id, {required bool active});
  Future<void> replaceControls(String gameId, List<GameControl> controls);

  // --- owner configuration (brief §2, §8) -----------------------------------
  // Everything the pricing/availability engine reads is editable here, so no
  // rate, schedule or station list is hardcoded in the app.

  /// Create or update a station/table/room and the activities it can host.
  Future<Resource> upsertResource(Resource resource);

  // --- controller inventory (brief: physical controllers) -------------------
  // Allocation never stores "how many are free" — it is derived from these
  // rows minus the controller counts of whatever is open on each station.

  /// Every controller, in label order.
  Future<List<Controller>> controllers();

  /// Live inventory, so the floor reflects a pad being marked faulty at once.
  Stream<List<Controller>> watchControllers();

  Future<Controller> upsertController(Controller controller);

  /// Mark a pad usable / faulty / missing / retired, with an optional note.
  Future<void> setControllerStatus(
    String id,
    ControllerStatus status, {
    String? notes,
  });

  /// Take a resource in or out of service. Refused while it is occupied.
  Future<void> setResourceStatus(String id, ResourceStatus status);

  /// Persisted rate card rows.
  Future<List<Rate>> rates();

  /// Create or update one rate row (activity + band + controller count).
  Future<void> upsertRate(Rate rate);
  Future<void> deleteRate({
    required String activityCode,
    required Band band,
    required int? controllerCount,
  });

  Future<BillingPolicy> policy();
  Future<void> savePolicy(BillingPolicy policy);

  Future<BusinessHours> businessHours();
  Future<void> saveBusinessHours(BusinessHours hours);

  /// What the floor offers staff (payment methods, start durations, warning); set on the
  /// admin dashboard, read-only here. [FloorOptions.defaults] until the arena sets them.
  Future<FloorOptions> floorOptions();

  Future<List<Holiday>> holidays();
  Future<void> upsertHoliday(Holiday holiday);
  Future<void> deleteHoliday(IstDate day);
}
