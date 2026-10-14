import 'package:arena_ops/app/providers/notification_providers.dart';
import 'package:arena_ops/app/router/app_router.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/widgets/session_alarm_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ArenaOpsApp extends ConsumerStatefulWidget {
  const ArenaOpsApp({super.key});

  @override
  ConsumerState<ArenaOpsApp> createState() => _ArenaOpsAppState();
}

class _ArenaOpsAppState extends ConsumerState<ArenaOpsApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestNotificationPermission();
    });
  }

  Future<void> _requestNotificationPermission() async {
    try {
      await ref.read(notificationServiceProvider).requestPermission();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Keep session alarm controller active to monitor timers in foreground.
    ref.watch(sessionAlarmControllerProvider);
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'arena_ops',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // The 404 Arena design is dark-first (black counter-top); light is kept
      // available for a future in-app toggle.
      themeMode: ThemeMode.dark,
      routerConfig: router,
      builder: (context, child) {
        return Stack(
          children: [
            ?child,
            const SessionAlarmOverlay(),
          ],
        );
      },
    );
  }
}
