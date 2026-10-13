import { Component, computed, inject, linkedSignal, output, signal } from '@angular/core';
import { MatFormField, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatChipListbox, MatChipOption } from '@angular/material/chips';
import { MatSlideToggle } from '@angular/material/slide-toggle';
import { MatSnackBar } from '@angular/material/snack-bar';
import { toAppError } from '../../../core/auth/auth-api';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailRow } from '../../../shared/list-detail/detail-row';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { UnsavedBar } from '../../../shared/list-detail/unsaved-bar';
import { NotConnected } from '../../../shared/not-connected/not-connected';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { PricingStore } from '../data/pricing-store';
import {
  BusinessHours,
  WEEKDAYS,
  formatMinuteOfDay,
  fromTimeInput,
  happyPreview,
  summarizeWindows,
  toTimeInput,
} from '../data/pricing.models';

interface DayDraft {
  readonly on: boolean;
  readonly from: string;
  readonly to: string;
}

const DEFAULT_FROM = 14 * 60;
const DEFAULT_TO = 17 * 60;

/**
 * Happy hour (the engine's `happy` band; stands in for the design's "Pricing rules"): one window
 * per weekday, IST. Types with happy-hour pricing charge their happy-hour rate inside it.
 * Saving keeps the opening hours as they are.
 */
@Component({
  selector: 'app-happy-hour-detail',
  imports: [
    DetailPane,
    DetailSection,
    DetailRow,
    StatusPill,
    UnsavedBar,
    MatFormField,
    MatLabel,
    MatInput,
    MatSlideToggle,
    MatChipListbox,
    MatChipOption,
    NotConnected,
  ],
  template: `
    <app-detail-pane
      crumb="Pricing / Happy hour"
      icon="trending_down"
      heading="Happy hour"
      [subtitle]="summary() || 'No happy hour set'"
      (closed)="closed.emit()"
    >
      <app-status-pill chip [tone]="summary() ? 'primary' : 'info'">{{
        summary() ? 'On' : 'Off'
      }}</app-status-pill>

      <app-detail-section
        heading="When"
        subtitle="Times in IST. Types with happy-hour pricing charge their happy-hour price inside these windows."
      >
        <div class="flex items-center justify-between gap-4">
          <span class="flex flex-col gap-1">
            <span class="text-[15px] leading-[1.3]" id="hh-active">Active</span>
            <span class="text-[13px] leading-[1.3] text-muted">{{
              anyOn() ? 'Applied to new sessions' : 'Not applied'
            }}</span>
          </span>
          <mat-slide-toggle
            hideIcon
            aria-labelledby="hh-active"
            [checked]="anyOn()"
            (change)="setAll($event.checked)"
          />
        </div>
        <mat-form-field>
          <mat-label>Name</mat-label>
          <input matInput disabled value="Happy hour" />
        </mat-form-field>
        @for (d of days; track d.key) {
          @let day = draft()[d.key];
          <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
            <div class="flex w-40 items-center gap-3">
              <mat-slide-toggle
                hideIcon
                [checked]="day.on"
                [attr.aria-label]="d.long + ' happy hour'"
                (change)="set(d.key, { on: $event.checked })"
              />
              <span class="flex flex-col">
                <span class="text-[15px] leading-[1.3]">{{ d.long }}</span>
                <span class="text-xs text-muted">{{ openText(d.key) }}</span>
              </span>
            </div>
            @if (day.on) {
              <mat-form-field class="arena-dense w-36">
                <mat-label>From</mat-label>
                <input
                  matInput
                  type="time"
                  [value]="day.from"
                  (input)="set(d.key, { from: $any($event.target).value })"
                />
              </mat-form-field>
              <mat-form-field class="arena-dense w-36">
                <mat-label>To</mat-label>
                <input
                  matInput
                  type="time"
                  [value]="day.to"
                  (input)="set(d.key, { to: $any($event.target).value })"
                />
              </mat-form-field>
            }
          </div>
        }
        @if (error()) {
          <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
        }
      </app-detail-section>

      <app-detail-section
        heading="Price change"
        subtitle="Per hour, set as a happy-hour price on each type's Base rate."
      >
        <div class="flex flex-col gap-2.5">
          <span class="text-[15px] leading-[1.3]" id="hh-dir">Type</span>
          <mat-chip-listbox disabled aria-labelledby="hh-dir">
            <mat-chip-option>Increase</mat-chip-option>
            <mat-chip-option>Discount</mat-chip-option>
          </mat-chip-listbox>
        </div>
        <div class="flex flex-col gap-2.5">
          <span class="text-[15px] leading-[1.3]" id="hh-by">By</span>
          <mat-chip-listbox disabled aria-labelledby="hh-by">
            <mat-chip-option>Percent %</mat-chip-option>
            <mat-chip-option>Flat ₹</mat-chip-option>
          </mat-chip-listbox>
        </div>
        <mat-form-field>
          <mat-label>Amount (%)</mat-label>
          <input matInput disabled value="" />
        </mat-form-field>
        <app-not-connected
          >Percentage and flat changes can't be saved yet; happy-hour prices are set per
          type.</app-not-connected
        >
      </app-detail-section>

      <app-detail-section heading="Applies to">
        <mat-chip-listbox multiple disabled aria-label="Station types with happy-hour pricing">
          @for (t of activeTypes(); track t.id) {
            <mat-chip-option [selected]="t.happyEligible">{{ t.name }}</mat-chip-option>
          }
        </mat-chip-listbox>
        <p class="text-[13px] leading-[1.45] text-muted">
          Turn happy-hour pricing on or off for a type with its Edit button.
        </p>
      </app-detail-section>

      @if (preview().length) {
        <app-detail-section
          heading="Preview"
          subtitle="What each type charges inside these windows."
        >
          @for (row of preview(); track row.name) {
            <app-detail-row [label]="row.name" [value]="row.value" [muted]="!row.included" />
          }
        </app-detail-section>
      }

      @if (dirty()) {
        <app-unsaved-bar footer [busy]="busy()" (discard)="discard()" (save)="save()" />
      }
    </app-detail-pane>
  `,
})
export class HappyHourDetail {
  private readonly store = inject(PricingStore);
  private readonly snack = inject(MatSnackBar);

  readonly closed = output<void>();

  protected readonly days = WEEKDAYS.map((d) => ({
    ...d,
    long: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][
      Number(d.key) - 1
    ],
  }));

  private readonly hours = computed(() => this.store.hours());
  protected readonly summary = computed(() => summarizeWindows(this.hours()?.happy ?? {}));
  protected readonly activeTypes = computed(() => this.store.types().filter((t) => t.active));
  /** Enabled types only, as in the design's preview. */
  protected readonly preview = computed(() =>
    this.store
      .types()
      .filter((t) => t.active)
      .map((t) => ({ name: t.name, ...happyPreview(t, this.store.rates()) })),
  );

  private readonly saved = computed<Record<string, DayDraft>>(() => {
    const happy = this.hours()?.happy ?? {};
    const out: Record<string, DayDraft> = {};
    for (const d of WEEKDAYS) {
      const w = happy[d.key];
      out[d.key] = {
        on: !!w,
        from: toTimeInput(w?.start ?? DEFAULT_FROM),
        to: toTimeInput(w?.end ?? DEFAULT_TO),
      };
    }
    return out;
  });
  protected readonly draft = linkedSignal(() => this.saved());
  protected readonly dirty = computed(() =>
    WEEKDAYS.some((d) => {
      const a = this.draft()[d.key];
      const b = this.saved()[d.key];
      return a.on !== b.on || (a.on && (a.from !== b.from || a.to !== b.to));
    }),
  );
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected openText(day: string): string {
    const w = this.hours()?.open[day];
    return w ? `Open ${formatMinuteOfDay(w.start)}–${formatMinuteOfDay(w.end)}` : 'Closed';
  }

  protected readonly anyOn = computed(() => WEEKDAYS.some((d) => this.draft()[d.key].on));

  /** Active off clears every day; on brings back the saved days, or Mon–Fri by default. */
  protected setAll(on: boolean): void {
    const saved = this.saved();
    const restore = WEEKDAYS.some((d) => saved[d.key].on);
    this.draft.update((d) => {
      const next: Record<string, DayDraft> = {};
      for (const w of WEEKDAYS) {
        next[w.key] = { ...d[w.key], on: on && (restore ? saved[w.key].on : Number(w.key) <= 5) };
      }
      return next;
    });
  }

  protected set(day: string, change: Partial<DayDraft>): void {
    this.draft.update((d) => ({ ...d, [day]: { ...d[day], ...change } }));
  }

  protected discard(): void {
    this.draft.set(this.saved());
    this.error.set('');
  }

  protected async save(): Promise<void> {
    const hours = this.hours();
    if (!hours) return;
    const happy: Record<string, { start: number; end: number } | null> = {};
    for (const d of this.days) {
      const day = this.draft()[d.key];
      if (!day.on) {
        happy[d.key] = null;
        continue;
      }
      const start = fromTimeInput(day.from);
      const end = fromTimeInput(day.to);
      if (start == null || end == null || end <= start) {
        this.error.set(`${d.long}: the window must end after it starts`);
        return;
      }
      happy[d.key] = { start, end };
    }
    const next: BusinessHours = { open: hours.open, happy };
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.saveHours(next);
      this.snack.open('Happy hour saved · new sessions use it', undefined, { duration: 3200 });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
