import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/domain/notifications/reminder_plan.dart';

/// [plan] as the OS must schedule it. Session and booking times are on the
/// app's clock, which follows server time once this device's clock is off by
/// more than the warning threshold ([OffsetClock]); the OS fires notifications
/// on the device's own clock, so a phone 10 minutes slow would otherwise ring
/// the "time up" alert 10 minutes late.
ReminderPlan onDeviceClock(ReminderPlan plan, Clock clock) => switch (clock) {
      OffsetClock(:final offset) when offset != Duration.zero =>
        plan.at(plan.fireAtUtc.subtract(offset)),
      _ => plan,
    };
