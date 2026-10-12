import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/router/app_router.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Hosts the bottom nav and the active branch's navigator. The destinations are
/// filtered to what the signed-in user can access (staff don't see Money /
/// Reports / Today).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final user = ref.watch(authControllerProvider);
    final tabs = user == null
        ? AppTab.all
        : [for (final t in AppTab.all) if (t.visibleFor(user)) t];

    final currentBranch = navigationShell.currentIndex;
    var selected = tabs.indexWhere((t) => t.branchIndex == currentBranch);
    if (selected < 0) selected = 0;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: arena.border)),
        ),
        child: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: (index) {
            final branch = tabs[index].branchIndex;
            navigationShell.goBranch(
              branch,
              // Tapping the current tab pops to its root.
              initialLocation: branch == currentBranch,
            );
          },
          destinations: [
            for (final tab in tabs)
              NavigationDestination(
                icon: Icon(tab.icon),
                selectedIcon: Icon(tab.selectedIcon),
                label: tab.label,
              ),
          ],
        ),
      ),
    );
  }
}
