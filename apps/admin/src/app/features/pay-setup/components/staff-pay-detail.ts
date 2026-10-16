import { NgTemplateOutlet } from '@angular/common';
import { Component, computed, inject, input, linkedSignal, output, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatFormField, MatHint, MatLabel, MatSuffix } from '@angular/material/form-field';
import { MatIcon } from '@angular/material/icon';
import { MatInput } from '@angular/material/input';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { Clock } from '../../../core/time/clock';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { ToggleRow } from '../../../shared/list-detail/toggle-row';
import { formatPaise } from '../../../shared/money/rupees.pipe';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { formatCount, formatDayYear, formatHMin } from '../../../shared/staff/staff-format';
import { formatIsoDate } from '../../../shared/time/ist';
import { initials } from '../../users/components/user-format';
import { payTypeLabel, perLabel, policyOn } from '../../payroll/data/pay-policy';
import { PaySetupStore } from '../data/pay-setup-store';
import {
  HrDraft,
  PayRate,
  PayStaff,
  hrProblems,
  minEffectiveFrom,
  rateOn,
  rateSummary,
  resolvedProfile,
  sameHrDraft,
  toHrDraft,
} from '../data/pay-setup.models';
import { PayRateDialog, PayRateDialogData } from '../dialogs/pay-rate-dialog';

/**
 * One person's pay setup: the HR profile (joined and left on, tracked or not, employee code, and
 * their own standard day and paid-leave allowance, empty = the arena's) and their pay rates, the
 * one in force now and the history, with New rate from… (rates are never edited).
 */
@Component({
  selector: 'app-staff-pay-detail',
  host: { class: 'flex flex-col gap-5' },
  imports: [
    NgTemplateOutlet,
    DetailPane,
    DetailSection,
    ToggleRow,
    StatusPill,
    MatButton,
    MatIcon,
    MatFormField,
    MatLabel,
    MatHint,
    MatSuffix,
    MatInput,
  ],
  template: `
    @let s = staff();
    <ng-template #pay>
      <app-detail-section
        heading="Pay rate"
        subtitle="Rates are effective-dated: a new rate takes over from its first day, and pay runs use the rate of each day."
      >
        @if (current(); as r) {
          <p class="text-sm leading-[1.4] font-medium">{{ summary() }}</p>
          <p class="text-[13px] leading-[1.4] text-muted">
            {{ type(r) }} since {{ day(r.effectiveFrom) }}.
            @if (r.extraHoursPaid && r.extraHourlyPaise === null) {
              Derived extra-hours rate: monthly = salary ÷ days in the pay period ÷ standard hours;
              daily = day rate ÷ standard hours; hourly = the hourly rate. Then × the multiplier in
              Pay rules.
            }
          </p>
        } @else if (upcoming()) {
          <p class="text-sm leading-[1.4]">Starts {{ day(upcoming()!.effectiveFrom) }}.</p>
        }
        @if (canEdit()) {
          <div>
            <button mat-stroked-button type="button" (click)="newRate()">
              <mat-icon aria-hidden="true">add</mat-icon>New rate from…
            </button>
          </div>
        }
        @if (rates().length) {
          <div class="-mx-2 overflow-x-auto">
            <table class="w-full min-w-[520px] border-collapse text-left text-[13px] leading-[1.3]">
              <caption class="sr-only">
                Pay rate history
              </caption>
              <thead>
                <tr class="border-b border-border text-xs text-muted">
                  <th scope="col" class="px-2 py-2 font-medium">From</th>
                  <th scope="col" class="px-2 py-2 font-medium">Pay type</th>
                  <th scope="col" class="px-2 py-2 text-right font-medium">Amount</th>
                  <th scope="col" class="px-2 py-2 font-medium">Extra hours</th>
                  <th scope="col" class="px-2 py-2 font-medium">Note</th>
                </tr>
              </thead>
              <tbody>
                @for (r of rates(); track r.id) {
                  <tr class="border-b border-border last:border-b-0">
                    <th scope="row" class="px-2 py-2 font-medium whitespace-nowrap">
                      {{ day(r.effectiveFrom) }}
                      @if (r.id === current()?.id) {
                        <span class="text-xs font-normal text-muted">(now)</span>
                      }
                    </th>
                    <td class="px-2 py-2">{{ type(r) }}</td>
                    <td class="px-2 py-2 text-right whitespace-nowrap tabular-nums">
                      {{ money(r.basePaise) }} {{ per(r.payType) }}
                    </td>
                    <td class="px-2 py-2">{{ extra(r) }}</td>
                    <td class="px-2 py-2 text-muted">{{ r.note ?? '' }}</td>
                  </tr>
                }
              </tbody>
            </table>
          </div>
        }
      </app-detail-section>

    </ng-template>
    <ng-template #profile>
      @let d = draft();
      @let p = problems();
      <app-detail-section
        heading="Employment"
        subtitle="The joining date starts each leave year. Empty overrides use the arena's settings."
      >
        <div class="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-3">
          <mat-form-field>
            <mat-label>Joined on</mat-label>
            <input
              matInput
              type="date"
              [disabled]="!canEdit()"
              [value]="d.joinedOn"
              (change)="set({ joinedOn: $any($event.target).value })"
            />
          </mat-form-field>
          <mat-form-field>
            <mat-label>Left on</mat-label>
            <input
              matInput
              type="date"
              aria-describedby="hr-dates-error"
              [attr.aria-invalid]="!!p.dates"
              [disabled]="!canEdit()"
              [value]="d.leftOn"
              (change)="set({ leftOn: $any($event.target).value })"
            />
            <mat-hint>Empty while they work here</mat-hint>
          </mat-form-field>
          <mat-form-field>
            <mat-label>Employee code</mat-label>
            <input
              matInput
              autocomplete="off"
              maxlength="40"
              [disabled]="!canEdit()"
              [value]="d.employeeCode"
              (input)="set({ employeeCode: $any($event.target).value })"
            />
          </mat-form-field>
        </div>
        @if (p.dates) {
          <p id="hr-dates-error" role="alert" class="text-[13px] leading-[1.4] text-danger">
            {{ p.dates }}
          </p>
        }
        <app-toggle-row
          label="Tracks attendance"
          sub="Clocks in and out, and appears on timesheets. Usually off for the owner."
          [checked]="d.tracksAttendance"
          [disabled]="!canEdit()"
          (changed)="set({ tracksAttendance: $event.checked })"
        />
        <div class="flex flex-wrap items-start gap-3">
          <mat-form-field class="w-36">
            <mat-label>Standard day</mat-label>
            <input
              matInput
              type="number"
              inputmode="numeric"
              min="1"
              max="24"
              aria-describedby="hr-std-help"
              [attr.aria-invalid]="!!p.standardDay"
              [placeholder]="defaultStdHours()"
              [disabled]="!canEdit()"
              [value]="d.stdHours"
              (input)="set({ stdHours: $any($event.target).value })"
            />
            <span matTextSuffix>h</span>
          </mat-form-field>
          <mat-form-field class="w-36">
            <mat-label>and</mat-label>
            <input
              matInput
              type="number"
              inputmode="numeric"
              min="0"
              max="59"
              aria-describedby="hr-std-help"
              [attr.aria-invalid]="!!p.standardDay"
              [placeholder]="defaultStdMinutes()"
              [disabled]="!canEdit()"
              [value]="d.stdMinutes"
              (input)="set({ stdMinutes: $any($event.target).value })"
            />
            <span matTextSuffix>min</span>
          </mat-form-field>
          <mat-form-field class="w-56">
            <mat-label>Paid leave a year</mat-label>
            <input
              matInput
              type="number"
              inputmode="decimal"
              min="0"
              max="366"
              step="0.5"
              [attr.aria-invalid]="!!p.paidLeaveDays"
              [placeholder]="defaultLeave()"
              [disabled]="!canEdit()"
              [value]="d.paidLeaveDays"
              (input)="set({ paidLeaveDays: $any($event.target).value })"
            />
            <span matTextSuffix>days</span>
            <mat-hint>Empty: arena's {{ defaultLeave() }}</mat-hint>
          </mat-form-field>
        </div>
        <p id="hr-std-help" class="-mt-2 text-[13px] leading-[1.4] text-muted">
          Extra hours start after the standard day. Empty: the arena's {{ defaultStd() }}.
        </p>
        @for (m of problemList(); track m) {
          <p role="alert" class="text-[13px] leading-[1.4] text-danger">{{ m }}</p>
        }
        @if (error()) {
          <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
        }
        @if (canEdit() && dirty()) {
          <div class="flex gap-2">
            <button mat-flat-button type="button" [disabled]="busy()" (click)="save()">
              Save profile
            </button>
            <button mat-button type="button" [disabled]="busy()" (click)="discard()">
              Discard
            </button>
          </div>
        }
      </app-detail-section>
    </ng-template>
    @if (part() === 'pay') {
      <ng-container [ngTemplateOutlet]="pay" />
    } @else if (part() === 'profile') {
      <ng-container [ngTemplateOutlet]="profile" />
    } @else {
    <app-detail-pane
      [crumb]="'Staff / Pay setup / ' + s.name"
      [heading]="s.name"
      [subtitle]="current() ? summary() : 'No pay rate yet: pay runs leave them out'"
      [initials]="initialsOf(s.name)"
      (closed)="closed.emit()"
    >
      @if (!s.active) {
        <app-status-pill chip tone="danger">Inactive</app-status-pill>
      }

      <ng-container [ngTemplateOutlet]="pay" />
      <ng-container [ngTemplateOutlet]="profile" />
    </app-detail-pane>
    }
  `,
})
export class StaffPayDetail {
  protected readonly store = inject(PaySetupStore);
  private readonly arena = inject(ArenaContext);
  private readonly clock = inject(Clock);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  readonly staff = input.required<PayStaff>();
  /**
   * 'all': the full pane (pay rate and HR profile). 'pay' / 'profile': just that part, as
   * sections inside another pane (the employee's Salary and Overview on Team).
   */
  readonly part = input<'all' | 'pay' | 'profile'>('all');
  readonly closed = output<void>();

  protected readonly money = formatPaise;
  protected readonly per = perLabel;
  protected readonly day = formatDayYear;
  protected readonly initialsOf = initials;
  protected readonly canEdit = computed(() => this.arena.hasPerm('payroll'));
  private readonly today = formatIsoDate(this.clock.now());

  private readonly defaults = computed(
    () => this.store.data()?.defaults ?? { standardDayMin: 480, paidLeaveDays: 12 },
  );
  protected readonly defaultStd = computed(() => formatHMin(this.defaults().standardDayMin));
  protected readonly defaultStdHours = computed(() =>
    String(Math.floor(this.defaults().standardDayMin / 60)),
  );
  protected readonly defaultStdMinutes = computed(() =>
    String(this.defaults().standardDayMin % 60),
  );
  protected readonly defaultLeave = computed(() => formatCount(this.defaults().paidLeaveDays));

  protected readonly profile = computed(() =>
    resolvedProfile(this.staff(), this.store.profileOf().get(this.staff().id)),
  );
  private readonly saved = computed(() => toHrDraft(this.profile()));
  protected readonly draft = linkedSignal<HrDraft>(() => this.saved());
  protected readonly dirty = computed(() => !sameHrDraft(this.draft(), this.saved()));
  protected readonly problems = computed(() => hrProblems(this.draft()));
  protected readonly problemList = computed(() => {
    const p = this.problems();
    return [p.employeeCode, p.standardDay, p.paidLeaveDays].filter((m): m is string => !!m);
  });

  protected readonly rates = computed(() => this.store.ratesOf(this.staff().id));
  protected readonly current = computed(() => rateOn(this.rates(), this.today));
  protected readonly upcoming = computed(() =>
    [...this.rates()].reverse().find((r) => r.effectiveFrom > this.today),
  );
  private readonly multiplier = computed(
    () => policyOn(this.store.data()?.policies ?? [], this.today).extraMultiplier,
  );
  private readonly standardDay = computed(
    () => this.profile().standardDayMin ?? this.defaults().standardDayMin,
  );
  protected readonly summary = computed(() => {
    const r = this.current();
    return r ? rateSummary(r, this.standardDay(), this.multiplier()) : '';
  });

  protected readonly busy = signal(false);
  protected readonly error = signal('');

  protected type(r: PayRate): string {
    return payTypeLabel(r.payType);
  }

  protected extra(r: PayRate): string {
    if (!r.extraHoursPaid) return r.payType === 'hourly' ? 'At the hourly rate' : 'Not paid';
    return r.extraHourlyPaise !== null
      ? `${formatPaise(r.extraHourlyPaise)} / h`
      : 'Paid (derived rate)';
  }

  protected set(change: Partial<HrDraft>): void {
    this.draft.update((d) => ({ ...d, ...change }));
    this.error.set('');
  }

  protected discard(): void {
    this.draft.set(this.saved());
    this.error.set('');
  }

  protected async save(): Promise<void> {
    if (Object.keys(this.problems()).length) {
      this.error.set('Fix the values marked above');
      return;
    }
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.saveProfile(this.staff().id, this.draft());
      this.snack.open(`${this.staff().name}’s profile saved`, undefined, { duration: 3200 });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }

  protected newRate(): void {
    const finalisedEnd = this.store.data()?.finalisedEnd ?? null;
    const min = minEffectiveFrom(finalisedEnd);
    const data: PayRateDialogData = {
      staffId: this.staff().id,
      staffName: this.staff().name,
      existing: this.rates(),
      finalisedEnd,
      standardDayMin: this.standardDay(),
      multiplier: this.multiplier(),
      suggestedFrom: min && min > this.today ? min : this.today,
      current: this.current() ?? null,
    };
    this.dialog
      .open(PayRateDialog, { data, width: '520px', autoFocus: 'first-tabbable' })
      .afterClosed()
      .subscribe((done) => {
        if (done) this.snack.open('New rate added', undefined, { duration: 3200 });
      });
  }
}
