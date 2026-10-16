import { Component, computed, effect, inject, linkedSignal, output, signal } from '@angular/core';
import { MatFormField, MatHint, MatLabel, MatSuffix } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatRadioButton, MatRadioGroup } from '@angular/material/radio';
import { MatOption, MatSelect } from '@angular/material/select';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { UnsavedBar } from '../../../shared/list-detail/unsaved-bar';
import { formatMinutes } from '../../../shared/time/ist';
import {
  DEFAULT_WORK_HOURS,
  EXTRA_BASES,
  ROUNDINGS,
  WEEKDAYS,
  WORK_HOURS_LIMITS,
  WorkHoursDraft,
  WorkHoursStore,
  fromWorkHoursDraft,
  sameWorkHoursDraft,
  toWorkHoursDraft,
  workHoursProblems,
  workHoursSummary,
} from '../data/work-hours';

/**
 * Settings › Working hours (docs/STAFF_API.md, key `work_hours`): late grace, early leave, when
 * the shift break is taken off, rounding, the full-day and half-day thresholds, the standard day
 * and how extra hours are counted, the week start and the auto clock-out grace. Edits collect
 * in a draft with the unsaved-changes bar; Save sends the whole object, checked here against
 * the server's ranges first.
 */
@Component({
  selector: 'app-work-hours-settings',
  imports: [
    DetailPane,
    DetailSection,
    UnsavedBar,
    MatFormField,
    MatLabel,
    MatHint,
    MatSuffix,
    MatInput,
    MatRadioGroup,
    MatRadioButton,
    MatSelect,
    MatOption,
  ],
  template: `
    <app-detail-pane
      crumb="Settings / Staff / Attendance calculation rules"
      icon="schedule"
      heading="Attendance calculation rules"
      [subtitle]="summary()"
      (closed)="closed.emit()"
    >
      @if (store.loadError(); as error) {
        <app-detail-section>
          <p role="alert" class="text-[13px] leading-[1.45] text-danger">
            Working hours couldn't load: {{ error }}
          </p>
        </app-detail-section>
      } @else if (!store.rules()) {
        <app-detail-section>
          <p class="text-[13px] leading-[1.45] text-muted">Loading…</p>
        </app-detail-section>
      } @else {
        @let d = draft();
        @let p = shownProblems();
        <p class="text-[13px] leading-[1.45] text-muted">
          How each day's clock-ins become worked hours, late marks, half days and extra hours on
          the calendar and in salary drafts. Days in a finalised salary run keep the figures they
          were paid on.
        </p>

        <app-detail-section
          heading="Late and early"
          subtitle="Measured against the start and end of the person's shift."
        >
          <div class="grid grid-cols-[repeat(auto-fit,minmax(200px,1fr))] gap-3">
            <mat-form-field>
              <mat-label>Late grace</mat-label>
              <input
                matInput
                type="number"
                inputmode="numeric"
                aria-describedby="wh-late-error"
                [attr.aria-invalid]="!!p.lateGrace"
                [disabled]="!canEdit()"
                [value]="d.lateGrace"
                (input)="set({ lateGrace: $any($event.target).value })"
              />
              <span matTextSuffix>min</span>
              <mat-hint>Clocking in later than this after the shift start counts as late</mat-hint>
            </mat-form-field>
            <mat-form-field>
              <mat-label>Early-leave threshold</mat-label>
              <input
                matInput
                type="number"
                inputmode="numeric"
                aria-describedby="wh-early-error"
                [attr.aria-invalid]="!!p.earlyLeave"
                [disabled]="!canEdit()"
                [value]="d.earlyLeave"
                (input)="set({ earlyLeave: $any($event.target).value })"
              />
              <span matTextSuffix>min</span>
              <mat-hint>Leaving more than this before the shift end counts as leaving early</mat-hint>
            </mat-form-field>
          </div>
          @if (p.lateGrace) {
            <p id="wh-late-error" role="alert" class="text-[13px] leading-[1.4] text-danger">
              {{ p.lateGrace }}
            </p>
          }
          @if (p.earlyLeave) {
            <p id="wh-early-error" role="alert" class="text-[13px] leading-[1.4] text-danger">
              {{ p.earlyLeave }}
            </p>
          }
        </app-detail-section>

        <app-detail-section
          heading="Breaks and rounding"
          subtitle="The shift's unpaid break is taken off a day once enough time is clocked."
        >
          <mat-form-field class="max-w-80">
            <mat-label>Take the break off after</mat-label>
            <input
              matInput
              type="number"
              inputmode="numeric"
              aria-describedby="wh-break-error"
              [attr.aria-invalid]="!!p.breakAfter"
              [disabled]="!canEdit()"
              [value]="d.breakAfter"
              (input)="set({ breakAfter: $any($event.target).value })"
            />
            <span matTextSuffix>min worked</span>
            <mat-hint>{{ breakHint() }}</mat-hint>
          </mat-form-field>
          @if (p.breakAfter) {
            <p id="wh-break-error" role="alert" class="text-[13px] leading-[1.4] text-danger">
              {{ p.breakAfter }}
            </p>
          }
          <span class="text-[15px] leading-[1.3]" id="wh-rounding-label"
            >Round each day's worked time</span
          >
          <mat-radio-group
            class="flex flex-col gap-3"
            aria-labelledby="wh-rounding-label"
            [disabled]="!canEdit()"
            [value]="d.rounding"
            (change)="set({ rounding: $event.value })"
          >
            @for (o of roundings; track o.value) {
              <mat-radio-button [value]="o.value">
                <span class="flex flex-col gap-0.5">
                  <span class="text-[15px] leading-[1.3]">{{ o.label }}</span>
                  <span class="text-[13px] leading-[1.3] text-muted">{{ o.sub }}</span>
                </span>
              </mat-radio-button>
            }
          </mat-radio-group>
        </app-detail-section>

        <app-detail-section
          heading="Full and half days"
          subtitle="Share of the scheduled time someone must work for the day to count."
        >
          <div class="grid grid-cols-[repeat(auto-fit,minmax(200px,1fr))] gap-3">
            <mat-form-field>
              <mat-label>Full day from</mat-label>
              <input
                matInput
                type="number"
                inputmode="numeric"
                aria-describedby="wh-full-error"
                [attr.aria-invalid]="!!p.fullDayPct"
                [disabled]="!canEdit()"
                [value]="d.fullDayPct"
                (input)="set({ fullDayPct: $any($event.target).value })"
              />
              <span matTextSuffix>% of scheduled</span>
            </mat-form-field>
            <mat-form-field>
              <mat-label>Half day from</mat-label>
              <input
                matInput
                type="number"
                inputmode="numeric"
                aria-describedby="wh-half-error"
                [attr.aria-invalid]="!!p.halfDayPct"
                [disabled]="!canEdit()"
                [value]="d.halfDayPct"
                (input)="set({ halfDayPct: $any($event.target).value })"
              />
              <span matTextSuffix>% of scheduled</span>
              <mat-hint>Less than this counts as absent</mat-hint>
            </mat-form-field>
          </div>
          @if (p.fullDayPct) {
            <p id="wh-full-error" role="alert" class="text-[13px] leading-[1.4] text-danger">
              {{ p.fullDayPct }}
            </p>
          }
          @if (p.halfDayPct) {
            <p id="wh-half-error" role="alert" class="text-[13px] leading-[1.4] text-danger">
              {{ p.halfDayPct }}
            </p>
          }
        </app-detail-section>

        <app-detail-section
          heading="Extra hours"
          subtitle="Every minute worked on a holiday or week off is extra too."
        >
          <span class="text-[15px] leading-[1.3]" id="wh-standard-label">Standard day</span>
          <div
            class="grid max-w-96 grid-cols-2 gap-3"
            role="group"
            aria-labelledby="wh-standard-label"
            aria-describedby="wh-standard-help wh-standard-error"
          >
            <mat-form-field>
              <mat-label>Hours</mat-label>
              <input
                matInput
                type="number"
                inputmode="numeric"
                [attr.aria-invalid]="!!p.standardDay"
                [disabled]="!canEdit()"
                [value]="d.standardHours"
                (input)="set({ standardHours: $any($event.target).value })"
              />
              <span matTextSuffix>h</span>
            </mat-form-field>
            <mat-form-field>
              <mat-label>Minutes</mat-label>
              <input
                matInput
                type="number"
                inputmode="numeric"
                [attr.aria-invalid]="!!p.standardDay"
                [disabled]="!canEdit()"
                [value]="d.standardMinutes"
                (input)="set({ standardMinutes: $any($event.target).value })"
              />
              <span matTextSuffix>min</span>
            </mat-form-field>
          </div>
          <p id="wh-standard-help" class="text-[13px] leading-[1.4] text-muted">
            Extra hours start after this on a working day. Also the day's length for staff
            without a shift. A person can have their own in Pay setup.
          </p>
          @if (p.standardDay) {
            <p id="wh-standard-error" role="alert" class="text-[13px] leading-[1.4] text-danger">
              {{ p.standardDay }}
            </p>
          }
          <span class="text-[15px] leading-[1.3]" id="wh-basis-label">Count extra hours</span>
          <mat-radio-group
            class="flex flex-col gap-3"
            aria-labelledby="wh-basis-label"
            [disabled]="!canEdit()"
            [value]="d.extraBasis"
            (change)="set({ extraBasis: $event.value })"
          >
            @for (o of bases; track o.value) {
              <mat-radio-button [value]="o.value">
                <span class="flex flex-col gap-0.5">
                  <span class="text-[15px] leading-[1.3]">{{ o.label }}</span>
                  <span class="text-[13px] leading-[1.3] text-muted">{{ o.sub }}</span>
                </span>
              </mat-radio-button>
            }
          </mat-radio-group>
          <mat-form-field class="max-w-72">
            <mat-label>Week starts on</mat-label>
            <mat-select
              [disabled]="!canEdit()"
              [value]="d.weekStart"
              (selectionChange)="set({ weekStart: $event.value })"
            >
              @for (w of weekdays; track w.value) {
                <mat-option [value]="w.value">{{ w.label }}</mat-option>
              }
            </mat-select>
            <mat-hint>For weekly extra hours and the calendar's weeks</mat-hint>
          </mat-form-field>
        </app-detail-section>

        <app-detail-section
          heading="Forgotten clock-outs"
          subtitle="A clock-in still open this long after the shift ends is closed at the shift end and flagged for review."
        >
          <mat-form-field class="max-w-80">
            <mat-label>Auto clock-out after the shift end</mat-label>
            <input
              matInput
              type="number"
              inputmode="numeric"
              aria-describedby="wh-auto-error"
              [attr.aria-invalid]="!!p.autoOutAfter"
              [disabled]="!canEdit()"
              [value]="d.autoOutAfter"
              (input)="set({ autoOutAfter: $any($event.target).value })"
            />
            <span matTextSuffix>min</span>
            <mat-hint
              >{{ limits.autoOutAfterMin[0] }}–{{ limits.autoOutAfterMin[1] }} minutes</mat-hint
            >
          </mat-form-field>
          @if (p.autoOutAfter) {
            <p id="wh-auto-error" role="alert" class="text-[13px] leading-[1.4] text-danger">
              {{ p.autoOutAfter }}
            </p>
          }
          @if (error()) {
            <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
          }
        </app-detail-section>
      }

      @if (dirty()) {
        <app-unsaved-bar footer [busy]="busy()" (discard)="discard()" (save)="save()" />
      }
    </app-detail-pane>
  `,
})
export class WorkHoursSettings {
  private readonly arena = inject(ArenaContext);
  protected readonly store = inject(WorkHoursStore);
  private readonly snack = inject(MatSnackBar);
  readonly closed = output<void>();

  protected readonly limits = WORK_HOURS_LIMITS;
  protected readonly roundings = ROUNDINGS;
  protected readonly bases = EXTRA_BASES;
  protected readonly weekdays = WEEKDAYS;
  protected readonly canEdit = this.arena.canEdit;

  private readonly saved = computed(() =>
    toWorkHoursDraft(this.store.rules() ?? DEFAULT_WORK_HOURS),
  );
  /** The draft starts from (and follows) what the server holds. */
  protected readonly draft = linkedSignal<WorkHoursDraft>(() => this.saved());
  protected readonly dirty = computed(
    () => !!this.store.rules() && !sameWorkHoursDraft(this.draft(), this.saved()),
  );
  private readonly problems = computed(() => workHoursProblems(this.draft()));
  /** A save was tried: every problem shows from then on (until Discard). */
  private readonly tried = signal(false);
  /** "Half day must be less than full day" shows at once; the rest after a save attempt. */
  protected readonly shownProblems = computed(() => {
    const all = this.problems();
    if (this.tried()) return all;
    return all.halfDayPct === 'Half day must be less than full day'
      ? { halfDayPct: all.halfDayPct }
      : {};
  });
  protected readonly breakHint = computed(() => {
    const n = Number(this.draft().breakAfter);
    return Number.isInteger(n) && n > 0
      ? `A day shorter than ${formatMinutes(n)} keeps its break`
      : '0: always take the break off';
  });
  protected readonly summary = computed(() => {
    const r = this.store.rules();
    return r ? workHoursSummary(r) : this.arena.current().name;
  });
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  constructor() {
    effect(() => {
      if (this.arena.current().id) void this.store.load();
    });
  }

  protected set(change: Partial<WorkHoursDraft>): void {
    this.draft.update((d) => ({ ...d, ...change }));
    this.error.set('');
  }

  protected discard(): void {
    this.draft.set(this.saved());
    this.tried.set(false);
    this.error.set('');
  }

  protected async save(): Promise<void> {
    this.tried.set(true);
    const rules = fromWorkHoursDraft(this.draft());
    if (!rules) {
      this.error.set('Fix the values marked above, then save again');
      return;
    }
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.save(rules);
      this.tried.set(false);
      this.snack.open('Working hours saved', undefined, { duration: 3200 });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
