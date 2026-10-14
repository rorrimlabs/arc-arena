import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/sync/cloud_binding.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/widgets/arena_header.dart';
import 'package:arena_ops/core/widgets/arena_list.dart';
import 'package:arena_ops/core/widgets/arena_placeholder_page.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/features/auth/presentation/change_password_dialog.dart';
import 'package:arena_ops/features/controllers/presentation/controller_board_screen.dart';
import 'package:arena_ops/features/customers/presentation/customers_screen.dart';
import 'package:arena_ops/features/more/presentation/help_screen.dart';
import 'package:arena_ops/features/more/presentation/settings_screen.dart';
import 'package:arena_ops/features/reports/presentation/session_log_screen.dart';
import 'package:arena_ops/features/sync/presentation/sync_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The "More" tab — shift, arena settings, floor tools and account. Owner-only
/// entries (Settings, Members) are hidden from staff who lack the permission.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  static const String path = '/more';

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  /// An honest dead end: the design has this area, this build does not. Says
  /// so plainly rather than describing a feature that is not there.
  void _notBuilt(BuildContext context, String title, String what, IconData icon) {
    _push(context, ArenaPlaceholderPage(
      title: title,
      subtitle: '$what is not part of this build yet, so nothing is recorded '
          'here. Everything else on the floor works without it.',
      icon: icon,
    ));
  }

  /// Before closing this arena's database with [pending] changes unsent:
  /// nothing is lost — they stay in this person's database on this device and
  /// go [when] — but they reach no one until then.
  Future<bool> _okToLeave(
    BuildContext context,
    int pending, {
    required String when,
    required String stay,
    required String leave,
  }) async {
    if (pending == 0) return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Changes not sent yet'),
        content: Text('$pending change(s) have not reached the server. They '
            'stay on this device and are sent $when.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: Text(stay)),
          TextButton(
              onPressed: () => Navigator.pop(c, true), child: Text(leave)),
        ],
      ),
    );
    return go == true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final user = ref.watch(authControllerProvider);
    final canSettings = user?.can(Permission.settings) ?? false;
    final canMembers = user?.can(Permission.members) ?? false;
    final cloud = ref.watch(cloudBindingProvider);
    final pending = ref.watch(syncStatusProvider).value?.pending ?? 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            const ArenaScreenHeader(title: 'More'),
            if (user != null) _AccountCard(name: user.name, role: user.roleLabel),
            _Group('Shift', [
              ArenaListRow(
                icon: Icons.schedule_rounded,
                title: 'Shift',
                subtitle: 'Open and close the day',
                onTap: () => _notBuilt(context, 'Shift',
                    'Shift open/close and cash-drawer reconciliation',
                    Icons.schedule_rounded),
              ),
              ArenaListRow(
                icon: Icons.warning_amber_rounded,
                title: 'Issues',
                subtitle: 'Report and resolve downtime',
                onTap: () => _notBuilt(context, 'Issues',
                    'The issue and downtime log',
                    Icons.warning_amber_rounded),
              ),
            ]),
            if (canSettings)
              _Group('Arena', [
                ArenaListRow(
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                  subtitle: 'Pricing, hours, holidays, stations, games, staff',
                  onTap: () => _push(context, const SettingsScreen()),
                ),
              ]),
            _Group('Floor tools', [
              if (canMembers)
                ArenaListRow(
                  icon: Icons.person_outline_rounded,
                  title: 'Members',
                  subtitle: 'Profiles, visits and spend',
                  onTap: () => _push(context, const CustomersScreen()),
                ),
              ArenaListRow(
                icon: Icons.dashboard_customize_outlined,
                title: 'Controller board',
                subtitle: 'Live station & controller status',
                onTap: () => _push(context, const ControllerBoardScreen()),
              ),
              ArenaListRow(
                icon: Icons.receipt_long_outlined,
                title: 'Session log',
                subtitle: 'Every session, searchable',
                onTap: () => _push(context, const SessionLogScreen()),
              ),
            ]),
            _Group('You', [
              if (cloud != null)
                ArenaListRow(
                  icon: Icons.sync_rounded,
                  title: 'Sync',
                  subtitle: '${cloud.arenaName} · what is waiting or refused',
                  onTap: () => _push(context, const SyncScreen()),
                ),
              if (cloud?.switchArena case final switchArena?)
                ArenaListRow(
                  icon: Icons.swap_horiz_rounded,
                  title: 'Switch arena',
                  subtitle: 'Leave ${cloud!.arenaName} for another arena',
                  onTap: () async {
                    if (await _okToLeave(context, pending,
                        when: 'the next time you open ${cloud.arenaName} here',
                        stay: 'Stay here',
                        leave: 'Switch')) {
                      await switchArena();
                    }
                  },
                ),
              if (cloud != null)
                ArenaListRow(
                  icon: Icons.password_rounded,
                  title: 'Change password',
                  subtitle: 'Your own sign-in for ${cloud.email}',
                  onTap: () async {
                    final changed = await showDialog<bool>(
                      context: context,
                      builder: (_) => ChangePasswordDialog(
                          changePassword: cloud.changePassword),
                    );
                    if (changed == true && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password changed.')));
                    }
                  },
                ),
              ArenaListRow(
                icon: Icons.help_outline_rounded,
                title: 'Help',
                subtitle: 'How the floor works',
                onTap: () => _push(context, const HelpScreen()),
              ),
              ArenaListRow(
                icon: Icons.logout_rounded,
                title: 'Sign out',
                subtitle: cloud == null
                    ? 'Lock this device'
                    : 'Sign out of ${cloud.email}',
                onTap: () async {
                  if (cloud != null &&
                      !await _okToLeave(context, pending,
                          when: 'the next time you sign in here',
                          stay: 'Stay signed in',
                          leave: 'Sign out')) {
                    return;
                  }
                  if (cloud != null) {
                    cloud.signOut();
                  } else {
                    ref.read(authControllerProvider.notifier).signOut();
                  }
                },
              ),
            ]),
            const SizedBox(height: AppSpacing.xxl),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(color: arena.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text('404 ARENA · OPS',
                      style: ArenaType.overline.copyWith(color: arena.textSubtle)),
                  const SizedBox(height: 2),
                  Text(
                      cloud == null
                          ? 'Version 1.0.0 · Local-first'
                          : 'Version 1.0.0 · Cloud · ${cloud.arenaName}',
                      style: ArenaType.caption.copyWith(color: arena.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.name, required this.role});
  final String name;
  final String role;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.x5, 0, AppSpacing.x5, AppSpacing.xl),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: arena.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: arena.border),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: arena.primarySoft,
              child: Text(name.characters.first.toUpperCase(),
                  style: ArenaType.h3.copyWith(color: arena.primaryText)),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: ArenaType.h3.copyWith(color: arena.text, fontSize: 17)),
                  Text('$role · on shift',
                      style: ArenaType.caption.copyWith(color: arena.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.rows);
  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ArenaSectionLabel(label: title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
          child: ArenaRowGroup(children: rows),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}
