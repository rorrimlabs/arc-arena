import 'package:flutter/widgets.dart';

/// Marks a screen where Session Replay must not record while [child] is on
/// screen. Sentry (and so Session Replay) is removed for now: the zones are
/// still counted, but there is no recording to pause.
///
/// Masking hides text and images, but a replay still shows WHERE someone
/// tapped: on the staff PIN keypad (a fixed in-app layout) those taps would give
/// the PIN away. So authentication and credential screens — PIN login, cloud
/// sign-in, password change, PIN editor — pause recording entirely and resume
/// it when they close. Nested zones are counted, so the replay resumes only
/// when the last one closes.
///
/// When a replay SDK comes back, pause it on 0 → 1 and resume it on 1 → 0.
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
    ReplayPause._active++;
  }

  @override
  void dispose() {
    ReplayPause._active--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
