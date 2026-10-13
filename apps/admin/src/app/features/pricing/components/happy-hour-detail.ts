import { Component, computed, inject, linkedSignal, output, signal } from '@angular/core';
import { MatFormField, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatSlideToggle } from '@angular/material/slide-toggle';
import { MatSnackBar } from '@angular/material/snack-bar';
import { toAppError } from '../../../core/auth/auth-api';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { UnsavedBar } from '../../../shared/list-detail/unsaved-bar';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { PricingStore } from '../data/pricing-store';
import {
  BusinessHours,
  WEEKDAYS,
  formatMinuteOfDay,
  fromTimeInput,
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
    StatusPill,
    UnsavedBar,
    MatFormField,
    MatLabel,
    MatInput,
    MatSlideToggle,
  ],
  template: `
    <app-detail-pane
      crumb="Pricing / Happy hour"
      icon="schedule"
      heading="Happy hour"
      [subtitle]="summary() || 'No happy hour set'"
      (closed)="closed.emit()"
    >
      <app-status-pill chip [tone]="summary() ? 'primary' : 'info'">{{
        summary() ? 'On' : 'Off'
      }}</app-status-pill>

      <app-detail-section
        heading="Weekly windows"
        subtitle="Times in IST. Types with happy-hour pricing charge their happy-hour price inside these windows."
      >
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
