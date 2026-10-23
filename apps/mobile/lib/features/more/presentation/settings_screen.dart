import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/router/app_nav.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/widgets/arena_list.dart';
import 'package:arena_ops/features/games/presentation/games_screen.dart';
import 'package:arena_ops/features/more/presentation/holidays_screen.dart';
import 'package:arena_ops/features/more/presentation/hours_screen.dart';
import 'package:arena_ops/features/more/presentation/pricing_screen.dart';
import 'package:arena_ops/features/more/presentation/staff_screen.dart';
import 'package:arena_ops/features/more/presentation/stations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Arena settings hub (design: "Pricing, hours, holidays, stations, games,
/// staff"). Every row opens a working editor over the stored configuration —
/// nothing the pricing or availability engine reads is hardcoded.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _push(BuildContext context, Widget page) {
    AppNav.to(context, page);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(venueCapabilitiesProvider);
    final noun = ref.watch(resourceNounProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x5,
          AppSpacing.lg,
          AppSpacing.x5,
          AppSpacing.xxl,
        ),
        children: [
          ArenaRowGroup(
            children: [
              if (caps.games)
                ArenaListRow(
                  icon: Icons.videogame_asset_outlined,
                  title: 'Games & controls',
                  subtitle: 'Library, platforms and controls',
                  onTap: () => _push(context, const GamesScreen()),
                ),
              ArenaListRow(
                icon: Icons.sell_outlined,
                title: 'Pricing & price bands',
                subtitle: 'Rates and holidays',
                onTap: () => _push(context, const PricingScreen()),
              ),
              ArenaListRow(
                icon: Icons.schedule_outlined,
                title: 'Opening hours',
                subtitle: 'Trading days and times',
                onTap: () => _push(context, const HoursScreen()),
              ),
              ArenaListRow(
                icon: Icons.event_busy_outlined,
                title: 'Holidays',
                subtitle: 'Special days and closures',
                onTap: () => _push(context, const HolidaysScreen()),
              ),
              ArenaListRow(
                icon: Icons.dashboard_customize_outlined,
                title: noun.many,
                subtitle: 'What customers rent, and its status',
                onTap: () => _push(context, const StationsScreen()),
              ),
              ArenaListRow(
                icon: Icons.badge_outlined,
                title: 'Staff & roles',
                subtitle: 'Who can do what',
                onTap: () => _push(context, const StaffScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
