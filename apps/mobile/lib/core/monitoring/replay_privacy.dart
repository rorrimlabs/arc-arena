import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Stops Sentry Session Replay from recording while [child] is on screen.
///
/// Masking hides text and images, but a replay still shows WHERE someone
/// tapped: on the staff PIN keypad (a fixed in-app layout) those taps would give
/// the PIN away. So authentication and credential screens — PIN login, cloud
/// sign-in, password change, PIN editor — pause recording entirely and resume
/// it when they close. Nested zones are counted, so the replay resumes only
/// when the last one closes.
///
/// A no-op where Session Replay is off or unsupported (no DSN, replay disabled
/// by configuration, sampled out, tests, desktop): [SentryFlutter.replay] then
/// has nothing to control.
class ReplayPause extends StatefulWidget {
  const ReplayPause({required this.child, super.key});

  final Widget child;

  /// Zones currently on screen (pause on 0 → 1, resume on 1 → 0).
  @visibleForTesting
  static int get activeZones => _active;
  static int _active = 0;

  @override
  State<ReplayPause> createState() => _ReplayPauseState();
}

class _ReplayPauseState extends State<ReplayPause> {
  @override
  void initState() {
    super.initState();
    if (ReplayPause._active++ == 0) _control(SentryFlutter.replay.pause);
  }

  @override
  void dispose() {
    if (--ReplayPause._active == 0) _control(SentryFlutter.replay.resume);
    super.dispose();
  }

  void _control(Future<void> Function() action) {
    unawaited(
      action().catchError((Object _) {
        // Replay control must never affect the screen it protects.
      }),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
