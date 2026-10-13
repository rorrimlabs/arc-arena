import 'package:arena_ops/core/config/app_config.dart';
import 'package:arena_ops/data/sync/sync_transport.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// The Sentry options for this build (called from `SentryFlutter.init` in
/// main). Kept here so the configuration is unit-tested.
///
/// An empty DSN leaves Sentry — and so Session Replay — inactive.
void configureSentry(SentryFlutterOptions options, AppConfig config) {
  options.dsn = config.sentryDsn ?? '';
  options.environment = config.environment;
  // Tracing sample rate: conservative in production (10%), full in dev (100%).
  options.tracesSampleRate = config.isProduction ? 0.1 : 1.0;
  options.sendDefaultPii = false;
  options.debug = config.sentryDebug;

  // Session Replay (Android / iOS). Rates come from AppConfig: 1.0 of sessions
  // outside production, 0.1 in production, 1.0 of errors; AO_SENTRY_REPLAY=off
  // or a rate of 0 turns it off. In this SDK (10.x) masking lives in
  // options.privacy (it used to be options.replay.mask*): every Text /
  // RichText / EditableText and every non-asset image is masked. Do not unmask
  // staff or customer screens without a privacy review. Auth and credential
  // screens pause recording altogether (ReplayPause).
  options.replay.sessionSampleRate = config.replaySessionSampleRate;
  options.replay.onErrorSampleRate = config.replayOnErrorSampleRate;
  options.privacy.maskAllText = true;
  options.privacy.maskAllImages = true;

  // Narrowly filter expected offline sync failures so only unexpected errors report.
  options.beforeSend = (event, hint) {
    final throwable = event.throwable;
    if (throwable is SyncOfflineException) {
      return null;
    }
    return event;
  };
}
