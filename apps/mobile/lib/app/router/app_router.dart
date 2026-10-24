import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/providers/profile_providers.dart';
import 'package:arena_ops/app/router/app_shell.dart';
import 'package:arena_ops/app/sync/cloud_binding.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/features/auth/presentation/login_screen.dart';
import 'package:arena_ops/features/bills/presentation/my_bills_screen.dart';
import 'package:arena_ops/features/bookings/presentation/bookings_screen.dart';
import 'package:arena_ops/features/floor/presentation/floor_screen.dart';
import 'package:arena_ops/features/money/presentation/money_screen.dart';
import 'package:arena_ops/features/profile/presentation/terms_screen.dart';
import 'package:arena_ops/features/more/presentation/more_screen.dart';
import 'package:arena_ops/features/reports/presentation/reports_screen.dart';
import 'package:arena_ops/features/today/presentation/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:arena_ops/features/bookings/presentation/booking_screen.dart';
import 'package:arena_ops/features/controllers/presentation/controller_board_screen.dart';
import 'package:arena_ops/features/customers/presentation/customer_profile_screen.dart';
import 'package:arena_ops/features/customers/presentation/customers_screen.dart';
import 'package:arena_ops/features/floor/presentation/station_detail_screen.dart';
import 'package:arena_ops/features/games/presentation/games_screen.dart';
import 'package:arena_ops/features/group_sessions/presentation/group_detail_screen.dart';
import 'package:arena_ops/features/group_sessions/presentation/group_session_screen.dart';
import 'package:arena_ops/features/more/presentation/help_screen.dart';
import 'package:arena_ops/features/more/presentation/holidays_screen.dart';
import 'package:arena_ops/features/more/presentation/hours_screen.dart';
import 'package:arena_ops/features/more/presentation/pricing_screen.dart';
import 'package:arena_ops/features/more/presentation/settings_screen.dart';
import 'package:arena_ops/features/more/presentation/staff_screen.dart';
import 'package:arena_ops/features/more/presentation/stations_screen.dart';
import 'package:arena_ops/features/new_session/presentation/new_session_screen.dart';
import 'package:arena_ops/features/notifications/presentation/notification_settings_screen.dart';
import 'package:arena_ops/features/notifications/presentation/notifications_screen.dart';
import 'package:arena_ops/features/reports/presentation/session_log_screen.dart';
import 'package:arena_ops/features/sync/presentation/sync_screen.dart';

/// The root navigator key for full-screen dialogs and secondary pages that sit
/// above the tab shell (hiding the bottom navigation bar).
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'rootNav');

/// Seven bottom tabs: Today · Floor · Bookings · Money · Reports · Bills · More.
/// Which ones show depends on the signed-in user's role (owners see Money /
/// Reports / Today; staff see Floor + Bookings + More, plus Bills with
/// bill_edit when signed in online). Customers ("Members") and the Games
/// library live under More.
final goRouterProvider = Provider<GoRouter>((ref) {
  // Re-run redirect whenever the signed-in user changes (sign in / out).
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  // …and whenever the staff terms gate opens or closes.
  ref.listen(termsGateProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: LoginScreen.path,
    refreshListenable: refresh,
    redirect: (context, state) {
      final user = ref.read(authControllerProvider);
      final cloud = ref.read(cloudBindingProvider) != null;
      final loc = state.matchedLocation;
      final atLogin = loc == LoginScreen.path;

      if (user == null) return atLogin ? null : LoginScreen.path;

      // Staff terms not accepted, or not known yet: nothing but the terms
      // screen (it shows the check, the failure with Retry, or the terms).
      final atTerms = loc == TermsScreen.path;
      if (ref.read(termsGateProvider) is! TermsGateOpen) {
        return atTerms ? null : TermsScreen.path;
      }
      if (atLogin || atTerms) return defaultPathFor(user);

      // Block tabs the user can't access (e.g. staff → /money).
      for (final tab in AppTab.all) {
        if (tab.path == loc && !tab.visibleFor(user, cloud: cloud)) {
          return defaultPathFor(user);
        }
      }

      // Block secondary routes the user can't access.
      if (loc.startsWith('/settings') && !user.can(Permission.settings)) {
        return defaultPathFor(user);
      }
      if (loc.startsWith('/customers') && !user.can(Permission.members)) {
        return defaultPathFor(user);
      }

      return null;
    },
    routes: [
      GoRoute(
        path: LoginScreen.path,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: TermsScreen.path,
        builder: (context, state) => const TermsScreen(),
      ),
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: rootNavigatorKey,
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
              path: BookingsScreen.path,
              builder: (context, state) => const BookingsScreen(),
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
          StatefulShellBranch(routes: [
            GoRoute(
              path: MyBillsScreen.path,
              builder: (context, state) => const MyBillsScreen(),
            ),
          ]),
        ],
      ),
      // Full-screen secondary routes (covering the AppShell and bottom navigation):
      GoRoute(
        path: SessionLogScreen.path,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SessionLogScreen(),
      ),
      GoRoute(
        path: CustomersScreen.path,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const CustomersScreen(),
      ),
      GoRoute(
        path: '/customers/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => CustomerProfileScreen(
          customerId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: PricingScreen.path,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const PricingScreen(),
      ),
      GoRoute(
        path: HoursScreen.path,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const HoursScreen(),
      ),
      GoRoute(
        path: HolidaysScreen.path,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const HolidaysScreen(),
      ),
      GoRoute(
        path: StationsScreen.path,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const StationsScreen(),
      ),
      GoRoute(
        path: StaffScreen.path,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const StaffScreen(),
      ),
      GoRoute(
        path: GamesScreen.path,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const GamesScreen(),
      ),
      GoRoute(
        path: HelpScreen.path,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const HelpScreen(),
      ),
      GoRoute(
        path: NotificationsScreen.path,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/notifications/settings',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: '/sync',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SyncScreen(),
      ),
      GoRoute(
        path: '/controllers',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ControllerBoardScreen(),
      ),
      GoRoute(
        path: '/bookings/new',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const BookingScreen(),
      ),
      GoRoute(
        path: '/sessions/new',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const NewSessionScreen(),
      ),
      GoRoute(
        path: '/groups/new',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const GroupSessionScreen(),
      ),
      GoRoute(
        path: '/sessions/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => StationDetailScreen(
          sessionId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/groups/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => GroupDetailScreen(
          groupId: state.pathParameters['id']!,
        ),
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
    this.requiresAny,
    this.staffOnline = false,
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

  /// Any one of these permissions opens the tab, if set.
  final List<Permission>? requiresAny;

  /// Online-only staff tab (Bills): hidden in local mode, and for owner-level
  /// users, whose bar is full (they reach it from More).
  final bool staffOnline;

  bool visibleFor(AppUser user, {bool cloud = true}) {
    if (requiresOwner && !user.isOwner) return false;
    if (requires != null && !user.can(requires!)) return false;
    if (requiresAny != null && !requiresAny!.any(user.can)) return false;
    if (staffOnline && (!cloud || user.isOwner)) return false;
    return true;
  }

  static const List<AppTab> all = [
    AppTab('Today', Icons.monitor_heart_outlined, Icons.monitor_heart,
        TodayScreen.path, 0, requiresOwner: true),
    AppTab('Floor', Icons.grid_view_outlined, Icons.grid_view_rounded,
        FloorScreen.path, 1),
    AppTab('Bookings', Icons.event_available_outlined, Icons.event_available,
        BookingsScreen.path, 2),
    AppTab('Money', Icons.payments_outlined, Icons.payments, MoneyScreen.path, 3,
        requires: Permission.money),
    AppTab('Reports', Icons.leaderboard_outlined, Icons.leaderboard,
        ReportsScreen.path, 4, requires: Permission.reports),
    AppTab('Bills', Icons.receipt_long_outlined, Icons.receipt_long,
        MyBillsScreen.path, 6,
        requiresAny: [Permission.billEdit, Permission.billRecord],
        staffOnline: true),
    AppTab('More', Icons.more_horiz, Icons.more_horiz, MoreScreen.path, 5),
  ];
}
