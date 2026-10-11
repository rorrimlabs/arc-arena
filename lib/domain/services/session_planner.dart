/// Pure session-rule computations shared by the start and extend flows.
///
/// This layer does no persistence; it combines [PricingService] and
/// [AvailabilityService] to produce the numbers the UI and the repositories
/// need (price preview, extension old/new end + added cost — spec §13, §17).
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/utc_interval.dart';
import 'package:arena_ops/domain/pricing/pricing_quote.dart';
import 'package:arena_ops/domain/pricing/pricing_snapshot.dart';
import 'package:arena_ops/domain/pricing/pricing_service.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/domain/services/availability_service.dart';
import 'package:meta/meta.dart';

/// The result of planning a new session: the window plus the price preview.
@immutable
class StartPlan {
  const StartPlan({
    required this.startedAt,
    required this.scheduledEndAt,
    required this.openEnded,
    required this.quote,
  });

  final DateTime startedAt;
  final DateTime scheduledEndAt;

  /// True when the staff chose "open-ended"; [scheduledEndAt] is then closing
  /// time and [quote] is an up-to-close estimate.
  final bool openEnded;

  /// Price preview for the scheduled window.
  final PricingQuote quote;
}

/// The result of planning an extension (spec §13).
@immutable
class ExtensionPlan {
  const ExtensionPlan({
    required this.oldEnd,
    required this.newEnd,
    required this.addedMinutes,
    required this.addedCost,
    required this.newQuote,
  });

  final DateTime oldEnd;
  final DateTime newEnd;
  final int addedMinutes;

  /// Extra cost of the added time (new scheduled quote − old scheduled quote).
  final Paise addedCost;

  /// The full quote for the extended scheduled window.
  final PricingQuote newQuote;
}

class SessionPlanner {
  const SessionPlanner({
    this.pricing = const PricingService(),
    this.availability = const AvailabilityService(),
  });

  final PricingService pricing;
  final AvailabilityService availability;

  /// Plans a new session. [durationMinutes] null means open-ended (scheduled to
  /// closing time). Checks availability and builds the price preview.
  Result<StartPlan> planStart({
    required PricingSnapshot snapshot,
    required String activityCode,
    required int? controllerCount,
    required String resourceId,
    required String resourceName,
    required DateTime startedAt,
    required int? durationMinutes,
    required Iterable<Occupancy> occupancies,
    required DateTime closeAt,
  }) {
    final openEnded = durationMinutes == null;
    final scheduledEndAt =
        openEnded ? closeAt : startedAt.add(Duration(minutes: durationMinutes));

    if (!scheduledEndAt.isAfter(startedAt)) {
      return const Err(Failure(
        message: 'Choose a duration.',
        fix: 'The session must be longer than zero minutes.',
        code: 'invalid_duration',
      ));
    }

    final avail = availability.canStart(
      resourceId: resourceId,
      resourceName: resourceName,
      window: UtcInterval(startedAt, scheduledEndAt),
      occupancies: occupancies,
      closeAt: closeAt,
      allowPastClose: snapshot.policy.allowExtendPastClose,
    );
    if (avail.isErr) return Err(avail.failureOrNull!);

    final quoted = pricing.quote(
      snapshot: snapshot,
      activityCode: activityCode,
      controllerCount: controllerCount,
      start: startedAt,
      end: scheduledEndAt,
    );
    return quoted.fold(
      (q) => Ok(StartPlan(
        startedAt: startedAt,
        scheduledEndAt: scheduledEndAt,
        openEnded: openEnded,
        quote: q,
      )),
      (f) => Err(f),
    );
  }

  /// Plans an extension of an active session (spec §13).
  Result<ExtensionPlan> planExtension({
    required PricingSnapshot snapshot,
    required String activityCode,
    required int? controllerCount,
    required String resourceId,
    required DateTime startedAt,
    required DateTime currentEnd,
    required int addedMinutes,
    required Iterable<Occupancy> occupancies,
    required DateTime closeAt,
  }) {
    final canExtend = availability.canExtend(
      resourceId: resourceId,
      currentEnd: currentEnd,
      addedMinutes: addedMinutes,
      occupancies: occupancies,
      closeAt: closeAt,
      allowPastClose: snapshot.policy.allowExtendPastClose,
    );
    if (canExtend.isErr) return Err(canExtend.failureOrNull!);
    final newEnd = canExtend.valueOrNull!;

    Result<PricingQuote> priceTo(DateTime end) => pricing.quote(
          snapshot: snapshot,
          activityCode: activityCode,
          controllerCount: controllerCount,
          start: startedAt,
          end: end,
        );

    final oldQuote = priceTo(currentEnd);
    if (oldQuote.isErr) return Err(oldQuote.failureOrNull!);
    final newQuote = priceTo(newEnd);
    if (newQuote.isErr) return Err(newQuote.failureOrNull!);

    final added = newQuote.valueOrNull!.amount - oldQuote.valueOrNull!.amount;
    return Ok(ExtensionPlan(
      oldEnd: currentEnd,
      newEnd: newEnd,
      addedMinutes: addedMinutes,
      addedCost: added,
      newQuote: newQuote.valueOrNull!,
    ));
  }
}
