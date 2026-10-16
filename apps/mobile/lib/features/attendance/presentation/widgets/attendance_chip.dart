/// The attendance shortcut in the floor's header: "Clock in", or the live
/// "On the clock · 2h 05m" once clocked in. Tapping opens the Attendance
/// screen. Shown only when the app is connected to an arena online (punches
/// are timed by the server, so the offline demo has none).
library;

import 'package:arena_ops/app/providers/attendance_providers.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/duration_format.dart';
import 'package:arena_ops/domain/attendance/attendance_entry.dart';
import 'package:arena_ops/features/attendance/presentation/attendance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AttendanceChip extends ConsumerWidget {
  const AttendanceChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(attendanceAvailableProvider)) return const SizedBox.shrink();
    final arena = context.arena;
    final entries = ref.watch(myAttendanceProvider).value?.valueOrNull;
    final open = entries == null ? null : openEntryOf(entries);
    final now = ref.watch(nowProvider).value ?? ref.watch(clockProvider).now();

    final onClock = open != null;
    final label = entries == null
        ? 'Attendance'
        : onClock
            ? 'On the clock · ${formatMinutesLabel(open.workedAt(now))}'
            : 'Clock in';
    final fg = onClock ? arena.success : arena.text;

    return Semantics(
      button: true,
      label: onClock ? '$label. Open attendance to clock out.' : '$label. Open attendance.',
      excludeSemantics: true,
      child: Material(
        color: onClock ? arena.successSoft : arena.surfaceRaised,
        shape: StadiumBorder(
            side: BorderSide(color: onClock ? arena.success : arena.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const AttendanceScreen())),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onClock)
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: arena.success, shape: BoxShape.circle),
                    )
                  else
                    Icon(Icons.fingerprint_rounded, size: 18, color: fg),
                  const SizedBox(width: AppSpacing.sm),
                  Text(label, style: ArenaType.label.copyWith(color: fg)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
