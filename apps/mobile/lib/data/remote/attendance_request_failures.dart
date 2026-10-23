/// The words staff see when a missed-punch request does not go through, keyed
/// by the server's codes (op_attendance_request).
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/data/remote/attendance_failures.dart';

abstract final class AttendanceRequestFailures {
  static Failure rejected(String? code, String? detail) => switch (code) {
    'reason_required' => const Failure(
      message: 'Say what happened.',
      fix: 'Add a short reason.',
      code: 'reason_required',
    ),
    'reason_too_long' => const Failure(
      message: 'The reason is too long.',
      fix: 'Keep it under 500 characters.',
      code: 'reason_too_long',
    ),
    'invalid_times' => const Failure(
      message: 'Those times do not work.',
      fix: 'Clock-out after clock-in, not in the future, at most 24 hours.',
      code: 'invalid_times',
    ),
    'overlap' => const Failure(
      message: 'You already have time recorded then.',
      fix: 'Pick other times, or fix that entry\'s clock-out instead.',
      code: 'overlap',
    ),
    'not_active' => const Failure(
      message: 'That entry was already corrected.',
      fix: 'Pull to refresh.',
      code: 'not_active',
    ),
    'period_finalised' => const Failure(
      message: 'Salary for that day is already finalised.',
      fix: 'Ask the owner to settle it in the next salary.',
      code: 'period_finalised',
    ),
    'not_found' => const Failure(
      message: 'That entry was not found.',
      fix: 'Pull to refresh.',
      code: 'not_found',
    ),
    'duplicate' => const Failure(
      message: 'This request was already sent.',
      fix: 'Pull to refresh to see it.',
      code: 'duplicate',
    ),
    'forbidden' => AttendanceFailures.accessOff,
    _ => Failure(
      message:
          "The request didn't go through"
          '${code == null ? '' : ' ($code)'}.',
      fix: 'Try again. If it keeps happening, tell the owner.',
      code: code ?? 'request_failed',
    ),
  };
}
