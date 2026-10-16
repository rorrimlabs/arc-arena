import { Component, computed, effect, inject, input, output } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatIcon } from '@angular/material/icon';
import { Router } from '@angular/router';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailRow } from '../../../shared/list-detail/detail-row';
import { GeoMap, GeoMarker } from '../../../shared/map/geo-map';
import { StatTile } from '../../../shared/stat-tile/stat-tile';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { formatDate, formatMinutes, formatTime } from '../../../shared/time/ist';
import { Geofence } from '../../settings/data/attendance-rules';
import { initials } from '../../users/components/user-format';
import { AttendanceStore } from '../data/attendance-store';
import { EntryActions } from '../data/entry-actions';
import { reviewReason } from '../data/today.models';
import {
  AttendanceEntry,
  LogRow,
  Punch,
  correctionLine,
  entryStatusLabel,
  entryFence,
  entryMinutes,
  flagLabel,
  flagTone,
  formatLatLng,
  locationStatusLabel,
  phoneSkew,
  reviewLabel,
  verdictLabel,
} from '../data/attendance.models';

interface EvidenceRow {
  readonly label: string;
  readonly value: string;
  readonly muted?: boolean;
}

/** "13 Oct, 9:02 am" */
function when(iso: string): string {
  return `${formatDate(iso)}, ${formatTime(iso)}`;
}

/** The evidence of one punch, as label / value rows. */
export function punchEvidence(p: Punch): EvidenceRow[] {
  const skew = phoneSkew(p);
  const located = p.lat !== null && p.lng !== null;
  return [
    { label: 'Server time', value: when(p.serverAt) },
    {
      label: 'Phone time',
      value: p.deviceAt ? `${formatTime(p.deviceAt)}${skew ? ` · ${skew}` : ''}` : 'Not sent',
      muted: !p.deviceAt,
    },
    { label: 'Where', value: verdictLabel(p.geofence) },
    { label: 'Location', value: locationStatusLabel(p.locationStatus) },
    {
      label: 'Position',
      value: located ? formatLatLng(p.lat as number, p.lng as number) : 'None',
      muted: !located,
    },
    {
      label: 'Accuracy',
      value: p.accuracyM !== null ? `±${Math.round(p.accuracyM)} m` : '—',
      muted: p.accuracyM === null,
    },
    {
      label: 'From the arena',
      value: p.distanceM !== null ? `${p.distanceM} m` : '—',
      muted: p.distanceM === null,
    },
    {
      label: 'Fake location',
      value: p.isMocked === null ? 'Not reported' : p.isMocked ? 'Yes' : 'No',
      muted: p.isMocked === null,
    },
    { label: 'Device', value: p.deviceId || '—', muted: !p.deviceId },
  ];
}

/** How many earlier versions of an entry the detail follows back. */
const MAX_CHAIN = 10;

/**
 * One attendance entry: in, out and worked time, and why it needs review in plain words. The
 * evidence stays one click away under Technical details: how it was corrected (each earlier
 * version, by whom and why), its flags, both punches side by side, and a map with each punch's
 * pin and the area it was judged against (the current one when the punch carries none). A
 * reviewer (`attendance_review`) can accept a pending entry, correct its times or void it,
 * never for their own entries unless they are the owner.
 */
@Component({
  selector: 'app-entry-detail',
  imports: [
    DetailPane,
    DetailRow,
    StatTile,
    StatusPill,
    GeoMap,
    MatButton,
    MatIcon,
  ],
  template: `
    @let r = row();
    <app-detail-pane
      [crumb]="'Staff / Attendance / ' + r.staffName"
      [heading]="r.staffName"
      [subtitle]="subtitle()"
      [initials]="initialsOf(r.staffName)"
      (closed)="closed.emit()"
    >
      @if (actionable()) {
        <div actions class="arena-compact flex flex-wrap gap-2">
          @if (r.entry.review === 'pending') {
            <button mat-stroked-button type="button" (click)="accept()">
              <mat-icon aria-hidden="true">check</mat-icon>Accept
            </button>
          }
          <button mat-stroked-button type="button" (click)="correct()">
            <mat-icon aria-hidden="true">edit_calendar</mat-icon>Correct times
          </button>
          <button mat-button type="button" class="danger-action" (click)="voidEntry()">
            <mat-icon aria-hidden="true">block</mat-icon>Void
          </button>
        </div>
      }
      @if (inactive(); as st) {
        <app-status-pill chip [tone]="st.tone">{{ st.label }}</app-status-pill>
      }
      @if (review(); as rv) {
        <app-status-pill chip [tone]="rv.tone">{{ rv.label }}</app-status-pill>
      }
      <div stats class="grid grid-cols-[repeat(auto-fit,minmax(130px,1fr))] gap-3">
        <app-stat-tile label="Clock-in" [value]="time(r.entry.inAt)" />
        <app-stat-tile
          label="Clock-out"
          [value]="r.entry.outAt ? time(r.entry.outAt) : 'On the clock'"
        />
        <app-stat-tile [label]="r.entry.outAt ? 'Worked' : 'So far'" [value]="duration()" />
      </div>

      @if (canReview() && ownRecord() && r.entry.status === 'active') {
        <p role="note" class="text-[13px] leading-[1.45] text-muted">
          This is your own entry: someone else with Review attendance corrects or accepts it.
        </p>
      }

      @if (r.entry.review === 'pending') {
        <p
          role="note"
          class="rounded-card bg-warning-soft px-4 py-3 text-sm leading-[1.4] font-medium text-warning"
        >
          {{ reason() }}
        </p>
      }
      @if (r.entry.reason) {
        <p class="text-[13px] leading-[1.45] text-muted">
          {{ r.entry.source === 'manual' && !r.entry.replacesId ? 'Added by hand' : 'Note' }}{{
            byName(r.entry) ? ' by ' + byName(r.entry) : ''
          }}: {{ r.entry.reason }}
        </p>
      }
      @if (r.entry.outSource === 'auto') {
        <p class="text-[13px] leading-[1.45] text-muted">
          They didn't clock out, so the entry was closed automatically.
          @if (r.outPunch) {
            Their later clock-out tap is kept as evidence.
          }
        </p>
      }

      <details class="group rounded-card border border-border">
        <summary
          class="flex cursor-pointer list-none items-center gap-2 px-4 py-3 text-sm font-medium [&::-webkit-details-marker]:hidden"
        >
          <span class="icon text-[20px] text-muted transition-transform group-open:rotate-90" aria-hidden="true"
            >chevron_right</span
          >
          Technical details
          <span class="text-[12.5px] font-normal text-muted">Location, device, history</span>
        </summary>
        <div class="flex flex-col gap-5 border-t border-border p-4">
          @if (r.entry.replacesId) {
            <section class="flex flex-col gap-2" aria-label="Correction history">
              <h4 class="text-sm leading-none font-semibold">Correction history</h4>
              <ol class="flex flex-col gap-1.5 text-[13px] leading-[1.45]">
                @for (c of chain(); track $index) {
                  <li>{{ c }}</li>
                }
              </ol>
            </section>
          }
          @if (r.entry.flags.length) {
            <section class="flex flex-col gap-2" aria-label="Flags">
              <h4 class="text-sm leading-none font-semibold">Flags</h4>
              <div class="flex flex-wrap gap-1.5">
                @for (f of r.entry.flags; track f) {
                  <app-status-pill [tone]="flagTone(f)">{{ flagLabel(f) }}</app-status-pill>
                }
              </div>
            </section>
          }
          <div class="grid grid-cols-[repeat(auto-fit,minmax(220px,1fr))] gap-5">
            @for (side of sides(); track side.title) {
              <section class="flex flex-col gap-2.5" [attr.aria-label]="side.title">
                <h4 class="text-sm leading-none font-semibold">{{ side.title }}</h4>
                @if (side.punch; as p) {
                  @for (e of evidence(p); track e.label) {
                    <app-detail-row [label]="e.label" [value]="e.value" [muted]="!!e.muted" />
                  }
                } @else {
                  <p class="text-[13px] leading-[1.45] text-muted">{{ side.none }}</p>
                }
              </section>
            }
          </div>
          @if (markers().length || fence()) {
            <section class="flex flex-col gap-2" aria-label="Map">
              <h4 class="text-sm leading-none font-semibold">Map</h4>
              <p class="text-[12.5px] leading-[1.4] text-muted">{{ mapNote() }}</p>
              <app-geo-map
                [label]="'Map of ' + r.staffName + '’s clock-in and clock-out'"
                height="240px"
                [center]="fence() ? { lat: fence()!.lat, lng: fence()!.lng } : null"
                [radius]="fence()?.radiusM ?? null"
                [markers]="markers()"
              />
              <p class="text-[12.5px] leading-[1.4] text-muted">
                Solid pin: clock-in. Hollow pin: clock-out. Circle: the venue's area.
              </p>
            </section>
          }
        </div>
      </details>
    </app-detail-pane>
  `,
})
export class EntryDetail {
  private readonly store = inject(AttendanceStore);
  private readonly actions = inject(EntryActions);
  private readonly router = inject(Router);

  readonly row = input.required<LogRow>();
  /** The viewer holds `attendance_review`. */
  readonly canReview = input(false);
  /** The entry is the viewer's own and they are not the owner (own-record rule). */
  readonly ownRecord = input(false);
  /** The arena's current geofence, drawn when the punches carry none. */
  readonly currentFence = input<Geofence | null>(null);
  /** The arena checks where people clock in (location reasons are worded only then). */
  readonly locationChecked = input(true);
  /** "Now", for the elapsed time of an entry still open. */
  readonly now = input.required<Date>();
  readonly closed = output<void>();

  protected readonly initialsOf = initials;
  protected readonly flagLabel = flagLabel;
  protected readonly flagTone = flagTone;
  protected readonly time = formatTime;
  protected readonly evidence = punchEvidence;

  protected readonly review = computed(() => reviewLabel(this.row().entry.review));
  protected readonly reason = computed(() =>
    reviewReason(this.row().entry, this.locationChecked()),
  );
  protected readonly inactive = computed(() => entryStatusLabel(this.row().entry.status));
  /** Accept / Correct / Void apply: a reviewer, not their own, and the row still counts. */
  protected readonly actionable = computed(
    () => this.canReview() && !this.ownRecord() && this.row().entry.status === 'active',
  );
  /**
   * The entry's earlier versions, newest first: "Corrected from 9:02 am–6:10 pm by Arjun ·
   * wrong clock-out" for each (the correction's author and reason are on the newer row).
   */
  protected readonly chain = computed(() => {
    const lines: string[] = [];
    let current: AttendanceEntry | undefined = this.row().entry;
    for (let i = 0; current?.replacesId && i < MAX_CHAIN; i++) {
      const previous = this.store.entry(current.replacesId);
      if (!previous) {
        lines.push('Corrected from an earlier version (loading…)');
        break;
      }
      lines.push(correctionLine(previous, this.byName(current), current.reason, formatTime));
      current = previous;
    }
    return lines;
  });

  constructor() {
    // Read the earlier versions the log does not hold (superseded rows are hidden by default).
    effect(() => {
      const ids: string[] = [];
      let current: AttendanceEntry | undefined = this.row().entry;
      for (let i = 0; current?.replacesId && i < MAX_CHAIN; i++) {
        const previous = this.store.entry(current.replacesId);
        if (!previous) {
          ids.push(current.replacesId);
          break;
        }
        current = previous;
      }
      if (ids.length) void this.store.fetchEntries(ids);
    });
  }

  /** Who made a row (the reviewer, for a correction), by their name in this arena. */
  protected byName(e: AttendanceEntry): string | null {
    if (!e.createdBy) return null;
    return this.store.staff().find((s) => s.userId === e.createdBy)?.name ?? null;
  }

  protected accept(): void {
    void this.actions.accept(this.row());
  }

  protected async voidEntry(): Promise<void> {
    if (await this.actions.voidEntry(this.row())) {
      void this.router.navigate([], { queryParams: { id: null }, queryParamsHandling: 'merge' });
    }
  }

  /** Correct the times; then shows the new row. */
  protected async correct(): Promise<void> {
    const id = await this.actions.correct(this.row());
    if (id) {
      void this.router.navigate([], { queryParams: { id }, queryParamsHandling: 'merge' });
    }
  }

  protected readonly subtitle = computed(() => {
    const e = this.row().entry;
    return `Work date ${formatDate(e.inAt)}`;
  });
  protected readonly duration = computed(() =>
    formatMinutes(entryMinutes(this.row().entry, this.now())),
  );
  protected readonly sides = computed(() => {
    const r = this.row();
    return [
      { title: 'Clock-in', punch: r.inPunch, none: 'Added by hand: no punch.' },
      {
        title: 'Clock-out',
        punch: r.outPunch,
        none: r.entry.outAt ? 'Closed without a clock-out punch.' : 'Still on the clock.',
      },
    ];
  });
  private readonly judged = computed(() => entryFence(this.row(), this.currentFence()));
  protected readonly fence = computed(() => this.judged().fence);
  protected readonly mapNote = computed(() => {
    const j = this.judged();
    if (!j.fence) return 'No arena location was set.';
    return j.fromPunch
      ? 'The circle is the arena location these punches were checked against.'
      : 'The circle is the arena location set now.';
  });
  protected readonly markers = computed<GeoMarker[]>(() => {
    const r = this.row();
    const pins: GeoMarker[] = [];
    for (const p of [r.inPunch, r.outPunch]) {
      if (p && p.lat !== null && p.lng !== null) {
        pins.push({
          lat: p.lat,
          lng: p.lng,
          kind: p.kind,
          label: `${p.kind === 'in' ? 'Clock-in' : 'Clock-out'} ${formatTime(p.serverAt)} · ${verdictLabel(p.geofence)}`,
        });
      }
    }
    return pins;
  });
}
