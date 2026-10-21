import { DOCUMENT } from '@angular/common';
import { Component, computed, effect, inject, input, linkedSignal, signal } from '@angular/core';
import { MatButton, MatIconButton } from '@angular/material/button';
import { MatButtonToggle, MatButtonToggleGroup } from '@angular/material/button-toggle';
import { MatChipListbox, MatChipListboxChange, MatChipOption } from '@angular/material/chips';
import { MatDialog } from '@angular/material/dialog';
import { MatFormField, MatLabel } from '@angular/material/form-field';
import { MatIcon } from '@angular/material/icon';
import { MatInput } from '@angular/material/input';
import { MatProgressBar } from '@angular/material/progress-bar';
import { MatOption, MatSelect } from '@angular/material/select';
import { MatSnackBar } from '@angular/material/snack-bar';
import { Router } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { Session } from '../../core/auth/session';
import { Clock } from '../../core/time/clock';
import { injectNow } from '../../core/time/ticker';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { formatDate, formatIsoDate, formatTime, istDayStartOf } from '../../shared/time/ist';
import { periodFor, periodProblem } from '../sales/data/sale.models';
import { AttendanceRulesStore } from '../settings/data/attendance-rules';
import { attendanceCsv } from './components/attendance-csv';
import { EntryDetail } from './components/entry-detail';
import { EntryRow } from './components/entry-row';
import { PunchMap } from './components/punch-map';
import { AttendanceStore } from './data/attendance-store';
import {
  LogFilter,
  LogRow,
  VERDICT_FILTERS,
  asVerdictFilter,
  filterRows,
  isOwnRecord,
} from './data/attendance.models';
import { CorrectDialog, CorrectDialogData, CorrectDialogResult } from './dialogs/correct-dialog';

/** The permission this screen needs (the owner holds every permission). */
export const ATTENDANCE_PERM = 'attendance_review';

const RANGES = [
  { key: 'today', label: 'Today' },
  { key: '7d', label: '7 days' },
  { key: '30d', label: '30 days' },
  { key: 'custom', label: 'Dates…' },
] as const;

const PAGE = 60;

/**
 * Staff › Attendance (docs/STAFF.md §6): everyone's clock-ins for a period of IST days (default
 * the last 7 days including today), filtered by person, where the punches were, entries waiting
 * for review and who is on the clock now; an entry's punch evidence and map; a Map view of
 * every punch; and a CSV export. Reviewers accept, correct and void entries in the detail and
 * add missing ones here (attendance.correct / attendance.review); superseded and voided rows
 * show only on request. Every filter, the view and the selected entry are in the URL
 * (`?range=30d&staff=…&where=outside&review=1&open=1&all=1&view=map&id=…`).
 */
@Component({
  selector: 'app-attendance-page',
  imports: [
    ListDetail,
    ListPaneHeader,
    EntryRow,
    EntryDetail,
    PunchMap,
    MatButton,
    MatIconButton,
    MatButtonToggleGroup,
    MatButtonToggle,
    MatChipListbox,
    MatChipOption,
    MatFormField,
    MatLabel,
    MatInput,
    MatSelect,
    MatOption,
    MatIcon,
    MatProgressBar,
  ],
  template: `
    <app-list-detail
      listLabel="Attendance entries"
      [detailLabel]="selected() ? 'Attendance entry' : 'Punch map'"
      emptyText="Pick an entry to see both punches and where they happened"
      [open]="!!selected() || mapView()"
      (closed)="close()"
    >
      <ng-container list>
        <app-list-pane-header
          title="Attendance records"
          back="/staff/attendance"
          backLabel="Back to attendance"
        >
          <mat-button-toggle-group
            actions
            aria-label="View"
            hideSingleSelectionIndicator
            [value]="mapView() ? 'map' : 'list'"
            (change)="setParams({ view: $event.value === 'map' ? 'map' : null })"
          >
            <mat-button-toggle value="list">List</mat-button-toggle>
            <mat-button-toggle value="map">Map</mat-button-toggle>
          </mat-button-toggle-group>
          <mat-chip-listbox aria-label="Days" [value]="range()" (change)="pickRange($event)">
            @for (r of ranges; track r.key) {
              <mat-chip-option [value]="r.key" [selectable]="r.key !== range()">{{
                r.label
              }}</mat-chip-option>
            }
          </mat-chip-listbox>
          @if (range() === 'custom') {
            <div class="flex flex-wrap gap-2">
              <mat-form-field class="w-44">
                <mat-label>From</mat-label>
                <input
                  matInput
                  type="date"
                  aria-label="First day"
                  [value]="period().first"
                  [max]="today()"
                  (change)="pickDates($any($event.target).value, period().last)"
                />
              </mat-form-field>
              <mat-form-field class="w-44">
                <mat-label>To</mat-label>
                <input
                  matInput
                  type="date"
                  aria-label="Last day"
                  [value]="period().last"
                  [max]="today()"
                  (change)="pickDates(period().first, $any($event.target).value)"
                />
              </mat-form-field>
            </div>
            @if (dateError()) {
              <p role="alert" class="text-[13px] leading-[1.3] text-danger">{{ dateError() }}</p>
            }
          }
          <div class="grid grid-cols-2 gap-2">
            <mat-form-field class="arena-dense">
              <mat-label>Staff</mat-label>
              <mat-select
                [value]="staffId() ?? ''"
                (selectionChange)="setParams({ staff: $event.value || null })"
              >
                <mat-option value="">Everyone</mat-option>
                @for (s of store.staff(); track s.id) {
                  <mat-option [value]="s.id">{{ s.name }}</mat-option>
                }
              </mat-select>
            </mat-form-field>
            <mat-form-field class="arena-dense">
              <mat-label>Location</mat-label>
              <mat-select
                [value]="verdict()"
                (selectionChange)="
                  setParams({ where: $event.value === 'any' ? null : $event.value })
                "
              >
                @for (v of verdicts; track v.value) {
                  <mat-option [value]="v.value">{{ v.label }}</mat-option>
                }
              </mat-select>
            </mat-form-field>
          </div>
          <mat-chip-listbox
            multiple
            aria-label="Show only"
            [value]="only()"
            (change)="pickOnly($event)"
          >
            <mat-chip-option value="review">Needs review</mat-chip-option>
            <mat-chip-option value="open">On the clock now</mat-chip-option>
            <mat-chip-option value="all">Show voided/superseded</mat-chip-option>
          </mat-chip-listbox>
          <div class="flex items-center gap-2">
            <p class="min-w-0 flex-1 text-[13px] leading-[1.3] text-muted" aria-live="polite">
              {{ summary() }}
            </p>
            <div class="arena-compact flex flex-none items-center">
              <button mat-button type="button" [disabled]="!store.log()" (click)="addEntry()">
                <mat-icon aria-hidden="true">more_time</mat-icon>Add missing entry
              </button>
              <button
                mat-icon-button
                type="button"
                [attr.aria-label]="refreshLabel()"
                [disabled]="store.loading()"
                (click)="store.refresh()"
              >
                <mat-icon aria-hidden="true">refresh</mat-icon>
              </button>
              <button
                mat-button
                type="button"
                [disabled]="!filtered().length"
                (click)="exportCsv()"
              >
                <mat-icon aria-hidden="true">download</mat-icon>Export CSV
              </button>
            </div>
          </div>
        </app-list-pane-header>
        @if (store.loading()) {
          <mat-progress-bar mode="indeterminate" aria-label="Loading attendance" />
        }
        <div class="flex min-h-0 flex-1 flex-col overflow-y-auto p-2">
          @if (store.loadError(); as error) {
            <div class="flex flex-col items-center gap-3 px-4 py-12 text-center">
              <p role="alert" class="text-sm text-danger">{{ error }}</p>
              <button
                mat-stroked-button
                type="button"
                (click)="store.load({ ...period(), withInactive: withInactive() }, true)"
              >
                Try again
              </button>
            </div>
          } @else if (store.log()) {
            <ul class="flex flex-col gap-0.5" aria-label="Entries">
              @for (r of visible(); track r.entry.id) {
                <li>
                  <app-entry-row
                    [row]="r"
                    [now]="now()"
                    [selected]="r.entry.id === selected()?.entry?.id"
                  />
                </li>
              }
            </ul>
            @if (!filtered().length) {
              <p class="px-4 py-12 text-center text-sm leading-[1.4] text-muted">
                No entries match these filters.
              </p>
            }
            @if (filtered().length > visible().length) {
              <div class="flex justify-center py-2">
                <button mat-stroked-button type="button" (click)="shown.set(shown() + page)">
                  Show more · {{ filtered().length - visible().length }} left
                </button>
              </div>
            }
          }
        </div>
      </ng-container>
      <ng-container detail>
        @if (selected(); as row) {
          <app-entry-detail
            [row]="row"
            [canReview]="true"
            [ownRecord]="isOwn(row)"
            [now]="now()"
            [currentFence]="rules.rules()?.geofence ?? null"
            (closed)="close()"
          />
        } @else if (mapView()) {
          <app-punch-map
            [rows]="filtered()"
            [now]="now()"
            [period]="periodLabel()"
            [fence]="rules.rules()?.geofence ?? null"
            (closed)="close()"
          />
        }
      </ng-container>
    </app-list-detail>
  `,
})
export class AttendancePage {
  protected readonly store = inject(AttendanceStore);
  protected readonly rules = inject(AttendanceRulesStore);
  private readonly arena = inject(ArenaContext);
  private readonly session = inject(Session);
  private readonly clock = inject(Clock);
  private readonly router = inject(Router);
  private readonly snack = inject(MatSnackBar);
  private readonly document = inject(DOCUMENT);
  private readonly dialog = inject(MatDialog);

  /** `?range=` — today | 7d | 30d | custom (default 7d). */
  readonly rangeParam = input<string>(undefined, { alias: 'range' });
  readonly fromParam = input<string>(undefined, { alias: 'from' });
  readonly toParam = input<string>(undefined, { alias: 'to' });
  /** `?staff=` — a staff profile id. */
  readonly staffParam = input<string>(undefined, { alias: 'staff' });
  /** `?where=` — inside | outside | unknown. */
  readonly whereParam = input<string>(undefined, { alias: 'where' });
  /** `?review=1` — only entries waiting for review. */
  readonly reviewParam = input<string>(undefined, { alias: 'review' });
  /** `?open=1` — only entries still on the clock. */
  readonly openParam = input<string>(undefined, { alias: 'open' });
  /** `?all=1` — superseded and voided rows too. */
  readonly allParam = input<string>(undefined, { alias: 'all' });
  /** `?view=map` — every punch on one map. */
  readonly viewParam = input<string>(undefined, { alias: 'view' });
  /** `?id=` — the selected entry. */
  readonly id = input<string>();

  protected readonly ranges = RANGES;
  protected readonly verdicts = VERDICT_FILTERS;
  protected readonly page = PAGE;

  /** Live "now" for open entries' elapsed time; also moves "today" at midnight IST. */
  protected readonly now = injectNow(30_000);
  protected readonly today = computed(() => formatIsoDate(this.now()));
  protected readonly period = computed(() =>
    periodFor(
      this.rangeParam() ?? '7d',
      this.fromParam(),
      this.toParam(),
      istDayStartOf(this.today()) ?? this.clock.now(),
    ),
  );
  protected readonly range = computed(() => this.period().range);
  protected readonly staffId = computed(() => this.staffParam() || null);
  protected readonly verdict = computed(() => asVerdictFilter(this.whereParam()));
  protected readonly needsReview = computed(() => this.reviewParam() === '1');
  protected readonly onClock = computed(() => this.openParam() === '1');
  protected readonly withInactive = computed(() => this.allParam() === '1');
  protected readonly only = computed(() => [
    ...(this.needsReview() ? ['review'] : []),
    ...(this.onClock() ? ['open'] : []),
    ...(this.withInactive() ? ['all'] : []),
  ]);
  protected readonly mapView = computed(() => this.viewParam() === 'map');
  protected readonly dateError = signal('');

  private readonly filter = computed<LogFilter>(() => ({
    first: this.period().first,
    last: this.period().last,
    staffId: this.staffId(),
    verdict: this.verdict(),
    needsReview: this.needsReview(),
    onClock: this.onClock(),
  }));
  protected readonly filtered = computed(() => filterRows(this.store.rows(), this.filter()));
  /** How many rows are listed; a new filter starts from the top again. */
  protected readonly shown = linkedSignal({ source: this.filter, computation: () => PAGE });
  protected readonly visible = computed(() => this.filtered().slice(0, this.shown()));
  protected readonly selected = computed<LogRow | undefined>(() => {
    const id = this.id();
    return id ? this.store.byId().get(id) : undefined;
  });
  protected readonly summary = computed(() => {
    const rows = this.filtered();
    const pending = rows.filter((r) => r.entry.review === 'pending').length;
    const open = rows.filter((r) => !r.entry.outAt).length;
    return [
      `${rows.length} entr${rows.length === 1 ? 'y' : 'ies'}`,
      pending ? `${pending} need${pending === 1 ? 's' : ''} review` : '',
      open ? `${open} on the clock` : '',
    ]
      .filter(Boolean)
      .join(' · ');
  });
  protected readonly periodLabel = computed(() => {
    if (this.onClock()) return 'On the clock now';
    const p = this.period();
    const first = istDayStartOf(p.first);
    const last = istDayStartOf(p.last);
    if (!first || !last) return '';
    return p.first === p.last ? formatDate(first) : `${formatDate(first)} – ${formatDate(last)}`;
  });
  protected readonly refreshLabel = computed(() => {
    const at = this.store.loadedAt();
    return at ? `Refresh (updated ${formatTime(at)})` : 'Refresh';
  });

  constructor() {
    // Load (and reload on an arena, period or day change) the current arena's log.
    effect(() => {
      const p = this.period();
      const withInactive = this.withInactive();
      if (this.arena.current().id) {
        void this.store.load({ first: p.first, last: p.last, withInactive });
      }
    });
    // The current geofence, for the Map view and punches judged without one.
    effect(() => {
      if (this.arena.current().id) void this.rules.load();
    });
    // The permission taken away live (or another arena picked without it): leave.
    effect(() => {
      if (this.arena.loaded() && this.arena.current().id && !this.arena.hasPerm(ATTENDANCE_PERM)) {
        void this.router.navigateByUrl('/overview');
      }
    });
  }

  protected setParams(params: Record<string, string | null>): void {
    void this.router.navigate([], { queryParams: params, queryParamsHandling: 'merge' });
  }

  protected pickRange(event: MatChipListboxChange): void {
    if (!event.value) return;
    this.dateError.set('');
    if (event.value === 'custom') {
      const p = this.period();
      this.setParams({ range: 'custom', from: p.first, to: p.last });
      return;
    }
    this.setParams({ range: event.value === '7d' ? null : event.value, from: null, to: null });
  }

  protected pickDates(first: string, last: string): void {
    let from = first;
    let to = last;
    if (from && to && from > to) {
      if (from !== this.period().first) to = from;
      else from = to;
    }
    const problem = periodProblem(from, to);
    this.dateError.set(problem ?? '');
    if (problem) return;
    this.setParams({ range: 'custom', from, to });
  }

  protected pickOnly(event: MatChipListboxChange): void {
    const picked = (event.value as string[] | null) ?? [];
    this.setParams({
      review: picked.includes('review') ? '1' : null,
      open: picked.includes('open') ? '1' : null,
      all: picked.includes('all') ? '1' : null,
    });
  }

  /** The entry is the viewer's own and they are not the owner: no accept, correct or void. */
  protected isOwn(row: LogRow): boolean {
    return isOwnRecord(
      row.entry.staffId,
      this.store.staff(),
      this.session.user()?.id,
      this.arena.currentRole(),
    );
  }

  /** attendance.correct `add`: a missing entry for someone (never yourself, unless the owner). */
  protected addEntry(): void {
    const userId = this.session.user()?.id;
    const owner = this.arena.currentRole() === 'owner';
    const staff = this.store
      .staff()
      .filter((s) => s.active && (owner || !userId || s.userId !== userId));
    this.dialog
      .open<CorrectDialog, CorrectDialogData, CorrectDialogResult>(CorrectDialog, {
        data: { staff, staffId: staff.some((s) => s.id === this.staffId()) ? this.staffId() : null },
        width: '560px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((result) => {
        if (!result) return;
        this.snack.open(result.snack, undefined, { duration: 3200 });
        if (result.id) this.setParams({ id: result.id, view: null });
      });
  }

  protected close(): void {
    if (this.id()) this.setParams({ id: null });
    else this.setParams({ view: null });
  }

  protected exportCsv(): void {
    const rows = this.filtered();
    const p = this.period();
    const user = this.session.user();
    const csv = attendanceCsv(rows, {
      arena: this.arena.current().name,
      first: p.first,
      last: p.last,
      generatedAt: this.clock.now(),
      generatedBy: user ? `${user.name} <${user.email}>` : null,
      filters: this.filterText(),
    });
    this.download(csv, p.first === p.last ? p.first : `${p.first}_to_${p.last}`);
    this.snack.open(`${rows.length} entr${rows.length === 1 ? 'y' : 'ies'} exported`, undefined, {
      duration: 3200,
    });
  }

  /** The list's filters in words, for the export. */
  private filterText(): string | null {
    const staff = this.staffId();
    const name = staff ? this.store.staff().find((s) => s.id === staff)?.name : null;
    const verdict = this.verdict();
    const parts = [
      name ?? '',
      verdict !== 'any' ? `location ${verdict}` : '',
      this.needsReview() ? 'needs review' : '',
      this.onClock() ? 'on the clock now (any day)' : '',
    ].filter(Boolean);
    return parts.length ? parts.join('; ') : null;
  }

  private download(csv: string, days: string): void {
    const slug = this.arena
      .current()
      .name.toLowerCase()
      .replace(/[^a-z0-9]+/g, '-');
    try {
      // A byte-order mark so spreadsheet apps read names as UTF-8.
      const url = URL.createObjectURL(new Blob(['﻿', csv], { type: 'text/csv' }));
      const a = this.document.createElement('a');
      a.href = url;
      a.download = `${slug || 'arena'}-attendance-${days}.csv`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(url));
    } catch {
      // Download blocked (e.g. a sandboxed preview): the snackbar still reports the count.
    }
  }
}
