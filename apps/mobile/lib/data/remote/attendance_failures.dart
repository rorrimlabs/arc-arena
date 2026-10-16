/// The words staff see when a clock-in or clock-out does not go through. One
/// place maps the server's stable codes (op_attendance_punch) and the network
/// states to a [Failure], so no screen invents its own copy.
library;

import 'package:arena_ops/core/result/result.dart';

abstract final class AttendanceFailures {
  static const Failure offline = Failure(
    message: "You're offline. Clocking in and out needs the internet, so the "
        'server records the time.',
    fix: 'Connect to Wi-Fi or mobile data and try again.',
    code: 'offline',
  );

  static const Failure signedOut = Failure(
    message: 'Your sign-in has ended.',
    fix: 'Sign in again, then clock in.',
    code: 'not_signed_in',
  );

  static const Failure accessOff = Failure(
    message: 'Your access to this arena is turned off.',
    fix: 'Ask the owner to turn it back on.',
    code: 'forbidden',
  );

  static const Failure cloudOnly = Failure(
    message: 'Attendance works only when the app is connected to your arena '
        'online.',
    fix: 'Sign in to your arena to clock in and out.',
    code: 'attendance_needs_cloud',
  );

  static const Failure loadFailed = Failure(
    message: "Your attendance couldn't be loaded.",
    fix: 'Check the connection and pull to refresh.',
    code: 'load_failed',
  );

  /// A refusal from the server (`attendance.punch` rejected with [code]).
  static Failure rejected(String? code, String? detail) => switch (code) {
        'already_clocked_in' => Failure(
            message: "You're already clocked in"
                '${detail == null ? '' : ' (${detail.replaceFirst('clocked in at ', 'since ')})'}.',
            fix: 'Clock out first, or pull to refresh.',
            code: code,
          ),
        'not_clocked_in' => const Failure(
            message: "You're not clocked in.",
            fix: 'Clock in first, or pull to refresh.',
            code: 'not_clocked_in',
          ),
        'outside_geofence' => Failure(
            message: "You're outside the arena area"
                '${detail == null ? '' : ' ($detail)'}.',
            fix: "Clock in when you're at the arena. If you are there, move "
                'to an open spot for a better GPS signal and try again.',
            code: code,
          ),
        'location_required' => Failure(
            message: 'This arena needs your location to clock in or out'
                '${detail == null ? '' : ': $detail'}.',
            fix: 'Turn on location for the app, wait for a good GPS signal '
                'and try again.',
            code: code,
          ),
        'mock_location' => const Failure(
            message: 'Your phone is using a fake (mock) location.',
            fix: 'Turn off the mock location app and try again.',
            code: 'mock_location',
          ),
        'not_found' => const Failure(
            message: "Your staff profile isn't in this arena.",
            fix: 'Ask the owner to check your access.',
            code: 'not_found',
          ),
        'duplicate' => const Failure(
            message: 'This punch was already recorded.',
            fix: 'Pull to refresh to see it.',
            code: 'duplicate',
          ),
        'invalid_payload' => Failure(
            message: 'The app sent an incomplete punch'
                '${detail == null ? '' : ' ($detail)'}.',
            fix: 'Update the app and try again.',
            code: code,
          ),
        'forbidden' => accessOff,
        _ => Failure(
            message: "The clock-in didn't go through"
                '${code == null ? '' : ' ($code)'}.',
            fix: 'Try again. If it keeps happening, tell the owner.',
            code: code ?? 'punch_failed',
          ),
      };

  /// The server asked for the op to be sent again (busy / lock timeout).
  static const Failure busy = Failure(
    message: 'The server was busy and did not record the punch.',
    fix: 'Try again.',
    code: 'retry',
  );
}
