import { Component, computed, input, output } from '@angular/core';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { GeoMap, GeoMarker } from '../../../shared/map/geo-map';
import { StatTile } from '../../../shared/stat-tile/stat-tile';
import { formatDate, formatMinutes, formatTime } from '../../../shared/time/ist';
import { Geofence } from '../../settings/data/attendance-rules';
import { LogRow, entryMinutes, verdictLabel } from '../data/attendance.models';

/** Every located punch of the rows, as pins. */
export function punchMarkers(rows: readonly LogRow[]): GeoMarker[] {
  const pins: GeoMarker[] = [];
  for (const r of rows) {
    for (const p of [r.inPunch, r.outPunch]) {
      if (p && p.lat !== null && p.lng !== null) {
        pins.push({
          lat: p.lat,
          lng: p.lng,
          kind: p.kind,
          label: `${r.staffName} · ${p.kind === 'in' ? 'in' : 'out'} ${formatDate(p.serverAt)}, ${formatTime(p.serverAt)} · ${verdictLabel(p.geofence)}`,
        });
      }
    }
  }
  return pins;
}

/**
 * The Map view: every punch of the filtered entries on one map with the arena's current
 * geofence, and the period's totals.
 */
@Component({
  selector: 'app-punch-map',
  imports: [DetailPane, DetailSection, GeoMap, StatTile],
  template: `
    <app-detail-pane
      crumb="Staff / Attendance / Map"
      icon="map"
      heading="Punch map"
      [subtitle]="period()"
      (closed)="closed.emit()"
    >
      <div stats class="grid grid-cols-[repeat(auto-fit,minmax(130px,1fr))] gap-3">
        <app-stat-tile label="Entries" [value]="rows().length.toString()" />
        <app-stat-tile label="Worked" [value]="worked()" />
        <app-stat-tile label="Need review" [value]="pending().toString()" />
        <app-stat-tile label="On the clock" [value]="open().toString()" />
      </div>
      <app-detail-section>
        <p class="text-[13px] leading-[1.4] text-muted">{{ note() }}</p>
        <app-geo-map
          label="Map of the listed clock-ins and clock-outs"
          height="min(560px, 60vh)"
          [center]="fence() ? { lat: fence()!.lat, lng: fence()!.lng } : null"
          [radius]="fence()?.radiusM ?? null"
          [markers]="markers()"
        />
        <p class="text-[12.5px] leading-[1.4] text-muted">
          Solid pin: clock-in. Hollow pin: clock-out. Circle: the arena's geofence now. Hover or tap
          a pin for who and when.
        </p>
      </app-detail-section>
    </app-detail-pane>
  `,
})
export class PunchMap {
  readonly rows = input.required<readonly LogRow[]>();
  readonly fence = input<Geofence | null>(null);
  /** "7–13 Oct", what the rows cover. */
  readonly period = input('');
  readonly now = input.required<Date>();
  readonly closed = output<void>();

  protected readonly markers = computed(() => punchMarkers(this.rows()));
  protected readonly worked = computed(() =>
    formatMinutes(this.rows().reduce((n, r) => n + entryMinutes(r.entry, this.now()), 0)),
  );
  protected readonly pending = computed(
    () => this.rows().filter((r) => r.entry.review === 'pending').length,
  );
  protected readonly open = computed(() => this.rows().filter((r) => !r.entry.outAt).length);
  protected readonly note = computed(() => {
    const pins = this.markers().length;
    const where = this.fence() ? '' : ' No arena location is set.';
    return `${pins} punch${pins === 1 ? '' : 'es'} with a position.${where}`;
  });
}
