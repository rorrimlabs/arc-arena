import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/providers/notification_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/duration_format.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/arena_header.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/notifications/notification_settings.dart';
import 'package:arena_ops/domain/notifications/reminder_policy.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/bookings/presentation/booking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifications & Alerts Hub (spec §23, timer ring alerts).
///
/// Combines:
/// 1. Device notification permissions & hardware capabilities.
/// 2. Session timer ring alerts preferences (sound, vibration, 5m warning, 1m warning, duration).
/// 3. In-app audible test trigger.
/// 4. Upcoming booking reminders scheduled on this device.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  static const String path = '/notifications';

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool? _permissionGranted;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    try {
      final granted =
          await ref.read(notificationServiceProvider).requestPermission();
      if (mounted) {
        setState(() => _permissionGranted = granted);
      }
    } catch (_) {}
  }

  Future<void> _updateSettings(NotificationSettings newSettings) async {
    await ref.read(notificationSettingsRepositoryProvider).saveSettings(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final now = ref.watch(nowProvider).value ?? ref.watch(clockProvider).now();
    final lead = ReminderPolicy.defaults.leadMinutes;

    final settings = ref.watch(notificationSettingsProvider).value ??
        const NotificationSettings();

    final all = ref.watch(upcomingBookingsProvider).value ?? const <Booking>[];
    final upcoming = all
        .where((b) =>
            b.status == BookingStatus.booked &&
            b.scheduledStart.toUtc().isAfter(now))
        .toList()
      ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));

    final games = {
      for (final g in ref.watch(allGamesProvider).value ?? []) g.id: g.name,
    };
    final resources = {
      for (final r in ref.watch(resourcesProvider).value ?? []) r.id: r.name,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications & Alerts')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x5,
          AppSpacing.sm,
          AppSpacing.x5,
          AppSpacing.xxl,
        ),
        children: [
          // ── 1. OS Permission Status Banner ──
          _PermissionCard(
            granted: _permissionGranted,
            onRequest: _checkPermission,
            arena: arena,
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── 2. Session Timer Ring Alert Settings ──
          const ArenaSectionLabel(label: 'Session Timer Ring Alerts'),
          Container(
            decoration: BoxDecoration(
              color: arena.surface,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: arena.border),
            ),
            child: Column(
              children: [
                _SettingToggleTile(
                  icon: Icons.volume_up_rounded,
                  title: 'Audible Ring & Loud Alarm',
                  subtitle:
                      'Play continuous alarm ringtone on device speaker when session ends or reaches a warning.',
                  value: settings.soundEnabled,
                  arena: arena,
                  onChanged: (val) =>
                      _updateSettings(settings.copyWith(soundEnabled: val)),
                ),
                Divider(height: 1, color: arena.border),
                _SettingToggleTile(
                  icon: Icons.vibration_rounded,
                  title: 'Device Vibration & Haptics',
                  subtitle:
                      'Vibrate physical device in repeating pulses while the alarm is ringing.',
                  value: settings.vibrationEnabled,
                  arena: arena,
                  onChanged: (val) =>
                      _updateSettings(settings.copyWith(vibrationEnabled: val)),
                ),
                Divider(height: 1, color: arena.border),
                _SettingToggleTile(
                  icon: Icons.alarm_on_rounded,
                  title: 'Session Expired Alarm (00:00)',
                  subtitle:
                      'Immediately trigger loud alarm and freeze billing when session reaches 0m remaining.',
                  value: settings.alertAtEnd,
                  arena: arena,
                  onChanged: (val) =>
                      _updateSettings(settings.copyWith(alertAtEnd: val)),
                ),
                Divider(height: 1, color: arena.border),
                _SettingToggleTile(
                  icon: Icons.notifications_active_outlined,
                  title: '5-Minute Early Warning',
                  subtitle:
                      'Give a reminder alert 5 minutes before scheduled end ("Ending soon (5m)").',
                  value: settings.alert5Min,
                  arena: arena,
                  onChanged: (val) =>
                      _updateSettings(settings.copyWith(alert5Min: val)),
                ),
                Divider(height: 1, color: arena.border),
                _SettingToggleTile(
                  icon: Icons.access_time_rounded,
                  title: '1-Minute Final Warning',
                  subtitle:
                      'Give a final reminder alert 1 minute before scheduled end ("Ending soon (1m)").',
                  value: settings.alert1Min,
                  arena: arena,
                  onChanged: (val) =>
                      _updateSettings(settings.copyWith(alert1Min: val)),
                ),
                Divider(height: 1, color: arena.border),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Alarm Ring Duration',
                            style: ArenaType.label.copyWith(
                              color: arena.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: arena.primarySoft,
                              borderRadius: BorderRadius.circular(AppRadii.sm),
                            ),
                            child: Text(
                              '${settings.alarmDurationSeconds}s loop',
                              style: AppTextStyles.mono(ArenaType.caption)
                                  .copyWith(
                                color: arena.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'How long the audible alarm loops continuously before auto-silencing if staff does not acknowledge.',
                        style: ArenaType.caption.copyWith(color: arena.textMuted),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [10, 15, 30, 60].map((sec) {
                          final selected = settings.alarmDurationSeconds == sec;
                          return Padding(
                            padding: const EdgeInsets.only(right: AppSpacing.sm),
                            child: ChoiceChip(
                              label: Text('${sec}s'),
                              selected: selected,
                              selectedColor: arena.primary,
                              labelStyle: ArenaType.caption.copyWith(
                                color: selected ? Colors.black : arena.text,
                                fontWeight:
                                    selected ? FontWeight.bold : FontWeight.normal,
                              ),
                              onSelected: (_) => _updateSettings(
                                settings.copyWith(alarmDurationSeconds: sec),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: arena.border),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Builder(
                    builder: (context) {
                      final activeAlarm =
                          ref.watch(sessionAlarmControllerProvider);
                      final isRinging =
                          activeAlarm != null && !activeAlarm.isSilenced;

                      if (isRinging) {
                        return SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: arena.warning,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.volume_off_rounded, size: 20),
                            label: const Text(
                              'Silence Test Alarm Now',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () {
                              ref
                                  .read(sessionAlarmControllerProvider.notifier)
                                  .silence();
                            },
                          ),
                        );
                      }

                      return SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: arena.primary),
                          ),
                          icon: Icon(Icons.ring_volume_rounded,
                              size: 20, color: arena.primary),
                          label: Text(
                            'Test Loud Alarm & Alert',
                            style: TextStyle(
                              color: arena.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () {
                            ref
                                .read(sessionAlarmControllerProvider.notifier)
                                .testAlarm();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Alarm ringing on physical speaker. Tap Silence or Dismiss on top banner.',
                                ),
                                duration: Duration(seconds: 4),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── 3. Upcoming Booking Reminders ──
          const ArenaSectionLabel(label: 'Upcoming Booking Reminders'),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              color: arena.surface,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: arena.border),
            ),
            child: Row(
              children: [
                Icon(Icons.notifications_active_outlined,
                    color: arena.primary, size: 20),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Booking reminders fire on this device $lead minutes before '
                    'each booking — even offline.',
                    style: ArenaType.caption.copyWith(color: arena.textMuted),
                  ),
                ),
              ],
            ),
          ),
          if (upcoming.isEmpty)
            _EmptyReminders(onNew: () => _openBookings(context))
          else
            for (final b in upcoming)
              _ReminderTile(
                booking: b,
                lead: lead,
                now: now,
                gameName: b.gameId == null ? null : games[b.gameId],
                resourceName:
                    b.resourceId == null ? null : resources[b.resourceId],
              ),
        ],
      ),
    );
  }

  void _openBookings(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const BookingScreen()));
  }
}

class _SettingToggleTile extends StatelessWidget {
  const _SettingToggleTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.arena,
    this.icon,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final ArenaColors arena;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value ? arena.primarySoft : arena.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  border: Border.all(
                    color: value
                        ? arena.primary.withValues(alpha: 0.3)
                        : arena.border,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: value ? arena.primary : arena.textMuted,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: ArenaType.label.copyWith(
                      color: arena.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: ArenaType.caption.copyWith(color: arena.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Switch(
              value: value,
              activeColor: arena.primary,
              activeTrackColor: arena.primary.withValues(alpha: 0.35),
              inactiveThumbColor: const Color(0xFF94A3B8),
              inactiveTrackColor: const Color(0xFF1E293B),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.granted,
    required this.onRequest,
    required this.arena,
  });

  final bool? granted;
  final VoidCallback onRequest;
  final ArenaColors arena;

  @override
  Widget build(BuildContext context) {
    final bool isGranted = granted == true;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: isGranted ? arena.primary.withValues(alpha: 0.5) : arena.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isGranted ? arena.primarySoft : arena.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Icon(
                  isGranted
                      ? Icons.notifications_active_rounded
                      : Icons.notification_important_rounded,
                  color: isGranted ? arena.primary : arena.warning,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isGranted
                                ? 'Notifications & Alarms Active'
                                : 'Notification Permission Needed',
                            style: ArenaType.label.copyWith(
                              color: arena.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isGranted
                                ? const Color(0xFF14532D)
                                : const Color(0xFF78350F),
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                            border: Border.all(
                              color: isGranted
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFF59E0B),
                            ),
                          ),
                          child: Text(
                            isGranted ? 'ALLOWED' : 'ACTION NEEDED',
                            style: AppTextStyles.mono(ArenaType.micro).copyWith(
                              color: isGranted
                                  ? const Color(0xFF86EFAC)
                                  : const Color(0xFFFDE68A),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isGranted
                          ? 'Physical alarm stream, repeating audio loop, and timer notifications are active.'
                          : 'To hear alarms when the app is in background or phone is locked, allow notifications.',
                      style: ArenaType.caption.copyWith(color: arena.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!isGranted) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: arena.warning,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: onRequest,
                icon: const Icon(Icons.settings, size: 18),
                label: const Text(
                  'Grant Notification Permission',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: arena.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 15, color: arena.textMuted),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'iQOO / Android Tip: If alerts are silenced while the screen is locked, ensure "Battery Saver" for Arena Ops is set to "No restrictions" in Android App Info.',
                    style: ArenaType.micro.copyWith(color: arena.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({
    required this.booking,
    required this.lead,
    required this.now,
    this.gameName,
    this.resourceName,
  });

  final Booking booking;
  final int lead;
  final DateTime now;
  final String? gameName;
  final String? resourceName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final customerName =
        ref.watch(customerByIdProvider(booking.customerId ?? '')).value?.name ??
            'Guest';
    final fireAt = booking.scheduledStart.subtract(Duration(minutes: lead));
    final leadPending = fireAt.isAfter(now);
    final detail = [
      if (gameName != null && gameName!.isNotEmpty) gameName!,
      resourceName ?? 'Any system',
      'at ${IstTime.format12(booking.scheduledStart)}',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: arena.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: arena.primarySoft,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(Icons.alarm_outlined, color: arena.primary, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ArenaType.label.copyWith(color: arena.text)),
                const SizedBox(height: 2),
                Text(detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ArenaType.caption.copyWith(color: arena.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(leadPending ? 'Reminds' : 'Starting',
                  style: ArenaType.micro.copyWith(color: arena.textSubtle)),
              Text(
                leadPending
                    ? IstTime.format12(fireAt)
                    : IstTime.format12(booking.scheduledStart),
                style: AppTextStyles.mono(ArenaType.label)
                    .copyWith(color: arena.text),
              ),
              Text(
                  leadPending
                      ? '${formatMinutesLabel(Duration(minutes: lead))} before'
                      : 'soon',
                  style: ArenaType.micro.copyWith(color: arena.textSubtle)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyReminders extends StatelessWidget {
  const _EmptyReminders({required this.onNew});
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: arena.border),
      ),
      child: Column(
        children: [
          Icon(Icons.notifications_none_rounded,
              color: arena.textSubtle, size: 32),
          const SizedBox(height: AppSpacing.md),
          Text('No upcoming reminders',
              style: ArenaType.h3.copyWith(color: arena.text, fontSize: 16)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Add a booking and you\'ll be reminded before it starts.',
            textAlign: TextAlign.center,
            style: ArenaType.caption.copyWith(color: arena.textMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: onNew,
            icon: const Icon(Icons.add),
            label: const Text('New booking'),
          ),
        ],
      ),
    );
  }
}
