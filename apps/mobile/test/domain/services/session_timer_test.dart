import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/domain/services/session_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 10, 2, 12, 30); // arbitrary UTC instant
  final scheduledEnd = start.add(const Duration(hours: 1));

  SessionTimer timer({DateTime? ended}) => SessionTimer(
    startedAt: start,
    scheduledEndAt: scheduledEnd,
    actualEndedAt: ended,
  );

  test('elapsed and remaining are derived from the clock', () {
    final clock = FakeClock(start.add(const Duration(minutes: 20)));
    final t = timer();
    expect(t.elapsed(clock.now()), const Duration(minutes: 20));
    expect(t.remaining(clock.now()), const Duration(minutes: 40));
    expect(t.isOvertime(clock.now()), isFalse);
    expect(t.state(clock.now()), SessionVisualState.normal);
  });

  test('warning state near the scheduled end', () {
    final clock = FakeClock(scheduledEnd.subtract(const Duration(minutes: 3)));
    expect(timer().state(clock.now()), SessionVisualState.warning);
  });

  test('overtime past the scheduled end', () {
    final clock = FakeClock(scheduledEnd.add(const Duration(minutes: 12)));
    final t = timer();
    expect(t.isOvertime(clock.now()), isTrue);
    expect(t.overtime(clock.now()), const Duration(minutes: 12));
    expect(t.remaining(clock.now()), Duration.zero);
    expect(t.state(clock.now()), SessionVisualState.overtime);
  });

  test('advancing the clock advances the timer (no counter)', () {
    final clock = FakeClock(start);
    final t = timer();
    expect(t.elapsed(clock.now()), Duration.zero);
    clock.advance(const Duration(minutes: 45));
    expect(t.elapsed(clock.now()), const Duration(minutes: 45));
  });

  test('timer rebuilds identically after an app restart', () {
    // Same timestamps, a fresh SessionTimer, same now → same values.
    final now = scheduledEnd.add(const Duration(minutes: 7));
    final before = timer().overtime(now);
    final afterRestart = SessionTimer(
      startedAt: start,
      scheduledEndAt: scheduledEnd,
    ).overtime(now);
    expect(afterRestart, before);
    expect(afterRestart, const Duration(minutes: 7));
  });

  test('ended session freezes elapsed and is never overtime', () {
    final ended = start.add(const Duration(minutes: 50));
    final t = timer(ended: ended);
    final wayLater = scheduledEnd.add(const Duration(hours: 2));
    expect(t.elapsed(wayLater), const Duration(minutes: 50));
    expect(t.isOvertime(wayLater), isFalse);
  });

  test('server clock offset changes now', () {
    // Device is 10 minutes behind the server.
    final device = FakeClock(start.add(const Duration(minutes: 20)));
    final synced = OffsetClock(device, const Duration(minutes: 10));
    expect(timer().elapsed(synced.now()), const Duration(minutes: 30));

    const small = ClockOffset(Duration(minutes: 1));
    expect(small.isSignificant, isFalse); // within the 2-minute threshold
    const big = ClockOffset(Duration(minutes: 3));
    expect(big.isSignificant, isTrue);
    expect(big.warning, 'Tablet clock is wrong. Timers use server time.');
  });

  test('elapsed time never produces negative duration', () {
    // Current clock is slightly before start time (e.g. slight device jitter)
    final slightlyBefore = start.subtract(const Duration(seconds: 5));
    final t = timer();
    expect(t.elapsed(slightlyBefore), Duration.zero);
  });

  test('detectAnomaly identifies corrupted or inverted timestamps', () {
    final normal = timer();
    expect(normal.detectAnomaly(start), isNull);

    final invertedSchedule = SessionTimer(
      startedAt: start,
      scheduledEndAt: start.subtract(const Duration(minutes: 30)),
    );
    expect(
      invertedSchedule.detectAnomaly(start),
      contains('precedes startedAt'),
    );

    final invertedActualEnd = SessionTimer(
      startedAt: start,
      scheduledEndAt: scheduledEnd,
      actualEndedAt: start.subtract(const Duration(minutes: 10)),
    );
    expect(
      invertedActualEnd.detectAnomaly(start),
      contains('precedes startedAt'),
    );
  });
}
