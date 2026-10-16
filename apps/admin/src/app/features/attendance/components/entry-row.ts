import { Component, computed, input } from '@angular/core';
import { RouterLink } from '@angular/router';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { formatDate, formatMinutes, formatTime } from '../../../shared/time/ist';
import { initials } from '../../users/components/user-format';
import {
  LogRow,
  entryMinutes,
  entryStatusLabel,
  flagLabel,
  flagTone,
  reviewLabel,
  rowFlags,
  verdictLabel,
  verdictTone,
} from '../data/attendance.models';

/**
 * One entry of the attendance list, in the list-row style (initials, name over a muted line,
 * selection tint) with a second line of badges: where each punch was, flags and review.
 * Selecting is a link so it lands in the URL and history.
 */
@Component({
  selector: 'app-entry-row',
  imports: [RouterLink, StatusPill],
  template: `
    @let r = row();
    <a
      [routerLink]="[]"
      [queryParams]="{ id: r.entry.id }"
      queryParamsHandling="merge"
      [attr.aria-current]="selected() ? 'true' : null"
      class="flex w-full items-start gap-3 rounded-card px-3 py-2.5 text-fg no-underline hover:bg-info-soft hover:text-fg"
      [class.bg-primary-soft]="selected()"
      [class.ring-1]="selected()"
      [class.ring-inset]="selected()"
      [class.ring-primary/30]="selected()"
    >
      <span
        class="grid size-10 flex-none place-items-center rounded-full bg-info-soft text-[13px] leading-none font-semibold"
        aria-hidden="true"
        >{{ initialsOf(r.staffName) }}</span
      >
      <span class="flex min-w-0 flex-1 flex-col gap-1.5">
        <span class="flex items-baseline gap-2">
          <span class="min-w-0 flex-1 truncate text-sm leading-[1.25] font-semibold">{{
            r.staffName
          }}</span>
          <span class="flex-none text-sm leading-none font-semibold tabular-nums">{{
            duration()
          }}</span>
        </span>
        <span class="truncate text-[12.5px] leading-[1.3] text-muted">{{ times() }}</span>
        <span class="flex flex-wrap gap-1">
          @if (r.inPunch; as p) {
            <app-status-pill [tone]="tone(p.geofence)"
              >In · {{ verdict(p.geofence) }}</app-status-pill
            >
          }
          @if (r.outPunch; as p) {
            <app-status-pill [tone]="tone(p.geofence)"
              >Out · {{ verdict(p.geofence) }}</app-status-pill
            >
          }
          @for (f of flags(); track f) {
            <app-status-pill [tone]="flagTone(f)">{{ flagLabel(f) }}</app-status-pill>
          }
          @if (review(); as rv) {
            <app-status-pill [tone]="rv.tone">{{ rv.label }}</app-status-pill>
          }
          @if (inactive(); as st) {
            <app-status-pill [tone]="st.tone">{{ st.label }}</app-status-pill>
          }
        </span>
      </span>
    </a>
  `,
})
export class EntryRow {
  readonly row = input.required<LogRow>();
  readonly selected = input(false);
  /** "Now", for the elapsed time of an entry still open. */
  readonly now = input.required<Date>();

  protected readonly initialsOf = initials;
  protected readonly verdict = verdictLabel;
  protected readonly tone = verdictTone;
  protected readonly flagLabel = flagLabel;
  protected readonly flagTone = flagTone;

  protected readonly flags = computed(() => rowFlags(this.row().entry.flags));
  protected readonly review = computed(() => reviewLabel(this.row().entry.review));
  protected readonly inactive = computed(() => entryStatusLabel(this.row().entry.status));
  protected readonly times = computed(() => {
    const e = this.row().entry;
    const out = e.outAt ? formatTime(e.outAt) : 'On the clock';
    return `${formatDate(e.inAt)} · ${formatTime(e.inAt)} → ${out}`;
  });
  protected readonly duration = computed(() =>
    formatMinutes(entryMinutes(this.row().entry, this.now())),
  );
}
