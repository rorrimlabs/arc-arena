/// A small map of an entry's punches (in / out pins) and the arena geofence.
library;

import 'package:arena_ops/app/providers/attendance_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/domain/attendance/attendance_entry.dart';
import 'package:arena_ops/domain/attendance/attendance_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class PunchMap extends ConsumerWidget {
  const PunchMap({super.key, required this.entry, this.height = 220});

  final AttendanceEntry entry;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final punches = [entry.inPunch, entry.outPunch]
        .whereType<AttendancePunch>()
        .where((p) => p.lat != null && p.lng != null)
        .toList();
    final fence = entry.inPunch?.geofence ?? entry.outPunch?.geofence;
    final points = [
      for (final p in punches) LatLng(p.lat!, p.lng!),
      if (fence != null) LatLng(fence.lat, fence.lng),
    ];
    final center = points.firstOrNull;

    final frame = BoxDecoration(
      color: arena.surfaceSunken,
      borderRadius: BorderRadius.circular(AppRadii.md),
      border: Border.all(color: arena.border),
    );
    if (center == null) {
      return Container(
        height: height,
        decoration: frame,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          'No location was recorded for this entry.',
          textAlign: TextAlign.center,
          style: ArenaType.caption.copyWith(color: arena.textMuted),
        ),
      );
    }

    return Semantics(
      label: 'Map of where you clocked in and out',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          height: height,
          decoration: frame,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 16,
              // Both pins and the arena in view, however far apart they are.
              initialCameraFit: points.length < 2
                  ? null
                  : CameraFit.coordinates(
                      coordinates: points,
                      padding: const EdgeInsets.all(40),
                      maxZoom: 17,
                    ),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom |
                    InteractiveFlag.drag |
                    InteractiveFlag.doubleTapZoom,
              ),
            ),
            children: [
              if (ref.watch(mapTilesEnabledProvider))
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'in.rorrim.arena_ops',
                ),
              if (fence != null)
                CircleLayer(circles: [
                  CircleMarker(
                    point: LatLng(fence.lat, fence.lng),
                    radius: fence.radiusM.toDouble(),
                    useRadiusInMeter: true,
                    color: arena.primary.withValues(alpha: 0.15),
                    borderColor: arena.primary,
                    borderStrokeWidth: 2,
                  ),
                ]),
              MarkerLayer(markers: [
                for (final p in punches)
                  Marker(
                    point: LatLng(p.lat!, p.lng!),
                    width: 36,
                    height: 36,
                    child: _Pin(kind: p.kind, verdict: p.verdict),
                  ),
              ]),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap: () => launchUrl(
                        Uri.parse('https://openstreetmap.org/copyright')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.kind, required this.verdict});

  final PunchKind kind;
  final GeofenceVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final color = switch (verdict) {
      GeofenceVerdict.inside => arena.success,
      GeofenceVerdict.outside => arena.danger,
      GeofenceVerdict.unknown => arena.warning,
    };
    return Semantics(
      label: kind == PunchKind.clockIn ? 'Clock-in' : 'Clock-out',
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: arena.surface, width: 3),
        ),
        alignment: Alignment.center,
        child: Text(
          kind == PunchKind.clockIn ? 'IN' : 'OUT',
          style: ArenaType.micro.copyWith(color: arena.textInverse, fontSize: 8),
        ),
      ),
    );
  }
}
