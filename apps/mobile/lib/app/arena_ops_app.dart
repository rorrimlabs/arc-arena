import 'package:arena_ops/app/router/app_router.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ArenaOpsApp extends ConsumerWidget {
  const ArenaOpsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'ARQ',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // The 404 Arena design is dark-first (black counter-top); light is kept
      // available for a future in-app toggle.
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
