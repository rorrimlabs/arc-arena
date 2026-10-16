import 'package:arena_ops/app/providers/notification_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/widgets/app_toast.dart';
import 'package:arena_ops/core/widgets/arena_header.dart';
import 'package:arena_ops/core/widgets/arena_list.dart';
import 'package:arena_ops/domain/notifications/notification_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// This phone's alerts (spec §23): whether the phone lets the app ring at all,
/// and which session timer alerts ring here and how. Kept on this device and
/// open to everyone — each phone on the floor decides for itself. A change
/// applies at once, to the alerts of sessions already running too.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  /// What this screen last saved. Nothing else changes this phone's settings,
  /// so from the first change on it stands for the stored value — and two
  /// quick taps each build on the one before, not on a stale read.
  NotificationSettings? _local;

  /// "Allow notifications" was tapped and the phone still says no: it will not
  /// ask again, so offer its settings.
  bool _askedOnce = false;

  bool get _iPhone => defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _save(NotificationSettings next) async {
    final before = _local ?? ref.read(notificationSettingsProvider).value;
    setState(() => _local = next);
    final r = await ref.read(notificationSettingsActionsProvider).save(next);
    if (!mounted) return;
    if (r.isErr) {
      setState(() => _local = before);
      showFailure(context, r.failureOrNull!);
      return;
    }
    // Turning alerts on may have asked the phone for permission.
    if (next.enabled != before?.enabled) {
      ref.invalidate(notificationAccessProvider);
    }
  }

  Future<void> _allow() async {
    await ref.read(notificationSettingsActionsProvider).allowNotifications();
    if (!mounted) return;
    setState(() => _askedOnce = true);
    ref.invalidate(notificationAccessProvider);
  }

  Future<void> _openPhoneSettings() async {
    final opened = await ref
        .read(notificationSettingsActionsProvider)
        .openPhoneSettings();
    if (!opened && mounted) {
      showToast(context, _whereToAllow, kind: ToastKind.info);
    }
  }

  Future<void> _allowExactAlarms() async {
    await ref.read(notificationSettingsActionsProvider).allowExactAlarms();
    if (mounted) ref.invalidate(notificationAccessProvider);
  }

  Future<void> _sendTest(bool blocked) async {
    await ref.read(notificationSettingsActionsProvider).sendTestAlert();
    if (!mounted) return;
    showToast(context, blocked
              ? "The phone blocks notifications, so the test alert won't show. "
                    'Allow them first.'
              : 'Test alert in 5 seconds. Lock the phone to hear it.');
  }

  String get _whereToAllow => _iPhone
      ? 'Or open Settings → Arena Ops → Notifications and switch on Allow '
            'Notifications.'
      : "Or open the phone's Settings → Apps → arena_ops → Notifications and "
            'switch them on.';

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final s = _local ?? ref.watch(notificationSettingsProvider).value;
    final access = ref.watch(notificationAccessProvider).value;
    final policy = ref.watch(bookingRemindersProvider).policy;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(
                top: AppSpacing.sm,
                bottom: AppSpacing.xxl,
              ),
              children: [
                _Padded(
                  _AccessCard(
                    allowed: access?.allowed,
                    askedOnce: _askedOnce,
                    whereToAllow: _whereToAllow,
                    onAllow: _allow,
                    onOpenSettings: _openPhoneSettings,
                  ),
                ),
                if (access?.exactAlarms == false)
                  _Padded(_ExactAlarmsCard(onAllow: _allowExactAlarms)),
                const SizedBox(height: AppSpacing.xl),
                _Group('Timer alerts', [
                  _SwitchRow(
                    icon: Icons.alarm_rounded,
                    title: 'Timer alerts',
                    subtitle: "Ring this phone as a session's time runs out",
                    value: s.enabled,
                    onChanged: (v) => _save(s.copyWith(enabled: v)),
                  ),
                  _SwitchRow(
                    icon: Icons.timer_outlined,
                    title: '5 minutes before',
                    subtitle: 'Time to offer more time',
                    value: s.alert5Min,
                    enabled: s.enabled,
                    onChanged: (v) => _save(s.copyWith(alert5Min: v)),
                  ),
                  _SwitchRow(
                    icon: Icons.hourglass_bottom_rounded,
                    title: '1 minute before',
                    subtitle: 'The last call',
                    value: s.alert1Min,
                    enabled: s.enabled,
                    onChanged: (v) => _save(s.copyWith(alert1Min: v)),
                  ),
                  _SwitchRow(
                    icon: Icons.alarm_on_rounded,
                    title: 'When time is up',
                    subtitle: 'Rings as an alarm',
                    value: s.alertAtEnd,
                    enabled: s.enabled,
                    onChanged: (v) => _save(s.copyWith(alertAtEnd: v)),
                  ),
                ]),
                _Group(
                  'How they ring',
                  [
                    _SwitchRow(
                      icon: Icons.volume_up_outlined,
                      title: 'Sound',
                      subtitle: 'Off: alerts show without a sound',
                      value: s.soundEnabled,
                      enabled: s.enabled,
                      onChanged: (v) => _save(s.copyWith(soundEnabled: v)),
                    ),
                    _SwitchRow(
                      icon: Icons.vibration_rounded,
                      title: 'Vibrate',
                      subtitle: 'Buzz with each alert',
                      value: s.vibrationEnabled,
                      enabled: s.enabled,
                      onChanged: (v) => _save(s.copyWith(vibrationEnabled: v)),
                    ),
                    if (!_iPhone)
                      _SwitchRow(
                        icon: Icons.repeat_rounded,
                        title: 'Keep ringing until opened',
                        subtitle: 'Time up sounds until someone opens it',
                        value: s.ringUntilSeen,
                        enabled: s.enabled && s.alertAtEnd,
                        onChanged: (v) => _save(s.copyWith(ringUntilSeen: v)),
                      ),
                  ],
                  note: _iPhone
                      ? 'On an iPhone the time-up sound plays once.'
                      : null,
                ),
                _Padded(
                  OutlinedButton.icon(
                    onPressed: () => _sendTest(access?.allowed == false),
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Send a test alert'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _Padded(
                  Text(
                    'Rings like "time up", with the settings above, 5 seconds '
                    'after you tap. Lock the phone to hear it.',
                    style: ArenaType.caption.copyWith(color: arena.textMuted),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                _Padded(
                  Text(
                    'Booking reminders ring ${policy.leadMinutes} min before '
                    'each booking${policy.alsoAtStart ? ', and again as it starts' : ''}.',
                    style: ArenaType.caption.copyWith(color: arena.textMuted),
                  ),
                ),
              ],
            ),
    );
  }
}

/// One line for the More row: what this phone will ring.
String timerAlertsSummary(NotificationSettings s, {bool? allowed}) {
  if (allowed == false) return 'Blocked by the phone';
  final which = [
    if (s.alert5Min) '5 min',
    if (s.alert1Min) '1 min',
    if (s.alertAtEnd) 'time up',
  ];
  if (!s.enabled || which.isEmpty) return 'Timer alerts off';
  return 'Timer alerts on · ${which.join(', ')}';
}

/// Whether the phone lets the app notify at all, and how to fix it if not.
class _AccessCard extends StatelessWidget {
  const _AccessCard({
    required this.allowed,
    required this.askedOnce,
    required this.whereToAllow,
    required this.onAllow,
    required this.onOpenSettings,
  });

  /// Null while unknown (still asking, or the platform does not say).
  final bool? allowed;
  final bool askedOnce;
  final String whereToAllow;
  final VoidCallback onAllow;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final (icon, color, title, detail) = switch (allowed) {
      true => (
        Icons.notifications_active_outlined,
        arena.success,
        'Notifications are on for this phone',
        'Alerts ring here even with the app closed or the phone locked.',
      ),
      false => (
        Icons.notifications_off_outlined,
        arena.danger,
        'Blocked by the phone',
        "This phone won't show or ring any alert from the app until "
            'notifications are allowed.',
      ),
      null => (
        Icons.notifications_none_rounded,
        arena.primary,
        'Notifications on this phone',
        "The phone didn't say whether it allows them. Send a test alert "
            'to check.',
      ),
    };
    return _Card(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: ArenaType.label.copyWith(color: arena.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: ArenaType.caption.copyWith(color: arena.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (allowed == false) ...[
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: onAllow,
            child: const Text('Allow notifications'),
          ),
          if (askedOnce) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: onOpenSettings,
              child: const Text('Open phone settings'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              whereToAllow,
              style: ArenaType.caption.copyWith(color: arena.textMuted),
            ),
          ],
        ],
      ],
    );
  }
}

/// Android 12+: without "Alarms & reminders" the phone may delay alerts.
class _ExactAlarmsCard extends StatelessWidget {
  const _ExactAlarmsCard({required this.onAllow});
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: _Card(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule_rounded, color: arena.warning, size: 22),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alerts may come late',
                      style: ArenaType.label.copyWith(color: arena.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'The phone may hold an alert back a few minutes until '
                      '"Alarms & reminders" is allowed for this app.',
                      style: ArenaType.caption.copyWith(color: arena.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: onAllow,
            child: const Text('Allow alarms on time'),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: arena.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// A row with a switch; the whole row toggles it. Dimmed and inert while
/// [enabled] is off (the master switch is off).
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final row = ArenaListRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: enabled ? () => onChanged(!value) : null,
      trailing: Switch(value: value, onChanged: enabled ? onChanged : null),
    );
    return enabled ? row : Opacity(opacity: 0.45, child: row);
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.rows, {this.note});
  final String title;
  final List<Widget> rows;

  /// A plain line under the group.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ArenaSectionLabel(label: title),
        _Padded(ArenaRowGroup(children: rows)),
        if (note != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _Padded(
            Text(
              note!,
              style: ArenaType.caption.copyWith(color: arena.textMuted),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _Padded extends StatelessWidget {
  const _Padded(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5),
    child: child,
  );
}
