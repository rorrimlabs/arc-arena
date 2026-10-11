import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/router/app_shell.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/features/auth/presentation/login_screen.dart';
import 'package:arena_ops/features/floor/presentation/floor_screen.dart';
import 'package:arena_ops/features/money/presentation/money_screen.dart';
import 'package:arena_ops/features/more/presentation/more_screen.dart';
import 'package:arena_ops/features/reports/presentation/reports_screen.dart';
import 'package:arena_ops/features/today/presentation/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Five bottom tabs (design nav): Today · Floor · Money · Reports · More.
/// Which ones show depends on the signed-in user's role (owners see Money /
/// Reports / Today; staff see Floor + More). Customers ("Members") and the
/// Games library live under More.
final goRouterProvider = Provider<GoRouter>((ref) {
  // Re-run redirect whenever the signed-in user changes (sign in / out).
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: LoginScreen.path,
    refreshListenable: refresh,
    redirect: (context, state) {
      final user = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      final atLogin = loc == LoginScreen.path;

      if (user == null) return atLogin ? null : LoginScreen.path;
      if (atLogin) return defaultPathFor(user);

      // Block tabs the user can't access (e.g. staff → /money).
      for (final tab in AppTab.all) {
        if (tab.path == loc && !tab.visibleFor(user)) {
          return defaultPathFor(user);
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: LoginScreen.path,
        builder: (context, state) => const LoginScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: TodayScreen.path,
              builder: (context, state) => const TodayScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: FloorScreen.path,
              builder: (context, state) => const FloorScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: MoneyScreen.path,
              builder: (context, state) => const MoneyScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: ReportsScreen.path,
              builder: (context, state) => const ReportsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: MoreScreen.path,
              builder: (context, state) => const MoreScreen(),
            ),
          ]),
        ],
      ),
    ],
  );
});

/// Where a user lands after signing in: owners on Today, staff on the Floor.
String defaultPathFor(AppUser user) =>
    user.isOwner ? TodayScreen.path : FloorScreen.path;

/// Tab metadata, kept next to the router so the shell and routes agree. Each
/// tab's branch index matches its position in the shell above.
class AppTab {
  const AppTab(
    this.label,
    this.icon,
    this.selectedIcon,
    this.path,
    this.branchIndex, {
    this.requiresOwner = false,
    this.requires,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
  final int branchIndex;

  /// Owner-only (Today's glance includes takings).
  final bool requiresOwner;

  /// A single permission that gates the tab, if any.
  final Permission? requires;

  bool visibleFor(AppUser user) {
    if (requiresOwner && !user.isOwner) return false;
    if (requires != null && !user.can(requires!)) return false;
    return true;
  }

  static const List<AppTab> all = [
    AppTab('Today', Icons.monitor_heart_outlined, Icons.monitor_heart,
        TodayScreen.path, 0, requiresOwner: true),
    AppTab('Floor', Icons.grid_view_outlined, Icons.grid_view_rounded,
        FloorScreen.path, 1),
    AppTab('Money', Icons.payments_outlined, Icons.payments, MoneyScreen.path, 2,
        requires: Permission.money),
    AppTab('Reports', Icons.leaderboard_outlined, Icons.leaderboard,
        ReportsScreen.path, 3, requires: Permission.reports),
    AppTab('More', Icons.more_horiz, Icons.more_horiz, MoreScreen.path, 4),
  ];
}
