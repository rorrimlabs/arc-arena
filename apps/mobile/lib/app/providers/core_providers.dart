/// App-wide singletons exposed to the widget tree via Riverpod.
library;

import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/config/app_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compile-time configuration (backend selection, Supabase creds).
final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment());

/// The operational clock. Overridden with a [FakeClock] in tests, and later
/// wrapped with a server offset once backend time sync is wired.
final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// Measured device-vs-server clock offset (spec §8). Zero in local mode (no
/// server to sync against); set from server time once Supabase is wired, which
/// surfaces the "Tablet clock is wrong" banner when it exceeds the threshold.
final clockOffsetProvider = Provider<ClockOffset>((ref) => const ClockOffset.none());
