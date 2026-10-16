/// The words staff see when a leave request or cancellation does not go
/// through, keyed by the server's codes (op_leave_request / op_leave_cancel).
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/data/remote/attendance_failures.dart';

abstract final class LeaveFailures {
  static const Failure cloudOnly = Failure(
    message: 'Leave works only when the app is connected to your arena online.',
    fix: 'Sign in to your arena to apply for leave.',
    code: 'leave_needs_cloud',
  );

  static Failure rejected(String? code, String? detail) => switch (code) {
        'reason_required' => const Failure(
            message: 'Say why you need the leave.',
            fix: 'Add a short reason.',
            code: 'reason_required'),
        'invalid_dates' => const Failure(
            message: 'Those dates do not work.',
            fix: 'Pick an end date on or after the start (at most 93 days).',
            code: 'invalid_dates'),
        'half_day_not_allowed' => const Failure(
            message: 'A half day can only be one day, and only if the arena allows half days.',
            fix: 'Pick a single day, or a full day.',
            code: 'half_day_not_allowed'),
        'planned_in_past' => const Failure(
            message: 'Planned leave cannot start in the past.',
            fix: 'Pick today or a later day, or choose Unplanned for a day already gone.',
            code: 'planned_in_past'),
        'too_far_back' => Failure(
            message: 'Unplanned leave can only go back so far'
                '${detail == null ? '' : ' ($detail)'}.',
            fix: 'Ask the owner to record older days.',
            code: code),
        'no_working_days' => const Failure(
            message: 'You are not scheduled to work on those days.',
            fix: 'Week-offs and holidays need no leave.',
            code: 'no_working_days'),
        'leave_overlap' => const Failure(
            message: 'You already have leave on some of those days.',
            fix: 'Cancel that request first, or pick other days.',
            code: 'leave_overlap'),
        'period_finalised' => const Failure(
            message: 'Salary for those days is already finalised.',
            fix: 'Ask the owner to settle it in the next salary.',
            code: 'period_finalised'),
        'invalid_state' => const Failure(
            message: 'This request can no longer be changed.',
            fix: 'Pull to refresh to see its status.',
            code: 'invalid_state'),
        'not_found' => const Failure(
            message: 'That request was not found.',
            fix: 'Pull to refresh.',
            code: 'not_found'),
        'duplicate' => const Failure(
            message: 'This request was already sent.',
            fix: 'Pull to refresh to see it.',
            code: 'duplicate'),
        'forbidden' => AttendanceFailures.accessOff,
        _ => Failure(
            message: "The leave request didn't go through"
                '${code == null ? '' : ' ($code)'}.',
            fix: 'Try again. If it keeps happening, tell the owner.',
            code: code ?? 'leave_failed'),
      };
}
