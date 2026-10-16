import { Component, computed, inject, output, signal } from '@angular/core';
import { MatSlideToggleChange } from '@angular/material/slide-toggle';
import { MatSnackBar } from '@angular/material/snack-bar';
import { RouterLink } from '@angular/router';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailRow } from '../../../shared/list-detail/detail-row';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { ListRow } from '../../../shared/list-detail/list-row';
import { ToggleRow } from '../../../shared/list-detail/toggle-row';
import { formatCount } from '../../../shared/staff/staff-format';
import { ShiftsStore } from '../../shifts/data/shifts-store';
import { daysLabel, shiftTimes } from '../../shifts/data/shifts.models';
import { AttendanceRulesStore } from '../data/attendance-rules';
import { LeaveRulesStore } from '../data/leave-rules';

/**
 * Settings › Staff: the few things most venues set (working hours, how staff clock in, whether
 * clock-ins are checked against the venue's location, paid leave a year), and every other rule
 * under Advanced settings, each in its own panel with the values it already has. Location checks
 * are off for a new venue; turning them on needs the venue's location (Clock-in and location
 * rules) and then flags clock-ins away from it for review.
 */
@Component({
  selector: 'app-staff-settings',
  imports: [DetailPane, DetailSection, DetailRow, ListRow, ToggleRow, RouterLink],
  template: `
    <app-detail-pane
      crumb="Settings / Staff"
      icon="badge"
      heading="Staff"
      subtitle="How your team clocks in, and the rules attendance and pay follow"
      (closed)="closed.emit()"
    >
      <app-detail-section heading="Working hours">
        @for (s of shifts(); track s.id) {
          <app-detail-row [label]="s.name" [value]="times(s) + ' · ' + days(s.days)" />
        } @empty {
          <p class="text-sm leading-[1.4] text-muted">
            No working hours yet. Without a shift every day is a day off, so nobody is shown absent.
          </p>
        }
        <a class="text-sm font-medium text-primary-text" routerLink="/settings/schedule"
          >Shifts and staff holidays</a
        >
      </app-detail-section>

      <app-detail-section
        heading="Attendance"
        subtitle="Staff clock in and out on the floor app. The time always comes from the server, never the phone."
      >
        <app-toggle-row
          label="Check the venue's location"
          [sub]="locationSub()"
          [checked]="locationOn()"
          [disabled]="!canEdit() || busy() || !rules.rules()"
          (changed)="toggleLocation($event)"
        />
        @if (error()) {
          <p role="alert" class="text-[13px] leading-[1.4] text-danger">{{ error() }}</p>
        }
      </app-detail-section>

      <app-detail-section heading="Leave">
        <app-detail-row label="Paid leave a year" [value]="leaveDays()" />
        <p class="text-[13px] leading-[1.4] text-muted">
          Per employee, from their joining date. Record leave on Attendance or on the employee in
          Team.
        </p>
      </app-detail-section>

      <details class="group">
        <summary
          class="flex cursor-pointer list-none items-center gap-2 py-2 text-sm font-semibold [&::-webkit-details-marker]:hidden"
        >
          <span
            class="icon text-[20px] text-muted transition-transform group-open:rotate-90"
            aria-hidden="true"
            >chevron_right</span
          >
          Advanced settings
        </summary>
        <ul class="flex flex-col gap-0.5 pt-2" aria-label="Advanced staff settings">
          <li>
            <app-list-row
              title="Clock-in and location rules"
              subtitle="Venue location and radius, GPS accuracy, fake locations, auto close"
              icon="location_on"
              [queryParams]="{ id: 'attendance' }"
            />
          </li>
          <li>
            <app-list-row
              title="Attendance calculation rules"
              subtitle="Late grace, early leave, half days, breaks, rounding, extra hours"
              icon="schedule"
              [queryParams]="{ id: 'workhours' }"
            />
          </li>
          <li>
            <app-list-row
              title="Leave rules"
              subtitle="Paid leave a year, half days, backdating"
              icon="event_available"
              [queryParams]="{ id: 'leave' }"
            />
          </li>
          @if (canPay()) {
            <li>
              <app-list-row
                title="Payroll calculation rules"
                subtitle="Pay period, deductions, late rule, extra-hours rate"
                icon="rule"
                [queryParams]="{ id: 'payrules' }"
              />
            </li>
          }
        </ul>
      </details>
    </app-detail-pane>
  `,
})
export class StaffSettings {
  protected readonly rules = inject(AttendanceRulesStore);
  private readonly leaveRules = inject(LeaveRulesStore);
  private readonly shiftsStore = inject(ShiftsStore);
  private readonly arena = inject(ArenaContext);
  private readonly snack = inject(MatSnackBar);

  readonly closed = output<void>();

  protected readonly times = shiftTimes;
  protected readonly days = daysLabel;
  protected readonly canEdit = this.arena.canEdit;
  protected readonly canPay = computed(() => this.arena.hasPerm('payroll'));
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  protected readonly shifts = computed(() => this.shiftsStore.shifts().filter((s) => s.active));
  protected readonly locationOn = computed(
    () => (this.rules.rules()?.outsideRule ?? 'flag') !== 'allow',
  );
  protected readonly locationSub = computed(() => {
    const r = this.rules.rules();
    if (!r || r.outsideRule === 'allow') {
      return 'Off: staff can clock in from anywhere.';
    }
    if (!r.geofence) return 'On, but the venue location is not set: every clock-in is flagged.';
    return r.outsideRule === 'block'
      ? `On: clock-ins farther than ${r.geofence.radiusM} m from the venue are refused.`
      : `On: clock-ins farther than ${r.geofence.radiusM} m from the venue are flagged for review.`;
  });
  protected readonly leaveDays = computed(() => {
    const r = this.leaveRules.rules();
    return r ? `${formatCount(r.paidLeaveDays)} days` : '—';
  });

  constructor() {
    void this.rules.load();
    void this.leaveRules.load();
    void this.shiftsStore.load();
  }

  /**
   * Off: accept every clock-in wherever it happens (outside rule allow). On: flag clock-ins away
   * from the venue for review, which needs the venue's location first.
   */
  protected async toggleLocation(event: MatSlideToggleChange): Promise<void> {
    const r = this.rules.rules();
    if (!r) return;
    this.error.set('');
    if (event.checked && !r.geofence) {
      event.source.checked = false;
      this.error.set(
        'Set the venue location first: Advanced settings › Clock-in and location rules.',
      );
      return;
    }
    this.busy.set(true);
    try {
      await this.rules.save({ ...r, outsideRule: event.checked ? 'flag' : 'allow' });
      this.snack.open(event.checked ? 'Location checks on' : 'Location checks off', undefined, {
        duration: 3200,
      });
    } catch (e) {
      event.source.checked = !event.checked;
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
