import 'package:arena_ops/domain/value/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'booking.freezed.dart';

/// A future reservation (spec §18, §23). Kept separate from the actual session:
/// a booking records what was *planned*; the segments record what *happened*.
/// [resourceId] null means "any compatible system" (spec §20A).
@freezed
abstract class Booking with _$Booking {
  const Booking._();

  const factory Booking({
    required String id,
    String? customerId,
    required String activityCode,
    String? gameId,
    String? resourceId,
    required DateTime scheduledStart,
    required DateTime scheduledEnd,
    int? playersRequired,
    int? controllerRequirement,
    required BookingStatus status,
    /// Party name for a walk-in reservation with no customer record yet.
    String? partyName,
    String? phone,
    String? notes,
    @Default(ReminderStatus.scheduled) ReminderStatus reminderStatus,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Booking;

  bool get isAnySystem => resourceId == null;
  bool get isOpen => status == BookingStatus.booked;

  Duration get plannedDuration => scheduledEnd.difference(scheduledStart);
}
