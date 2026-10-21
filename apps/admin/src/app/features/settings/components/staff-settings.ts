import { Component, computed, inject, input, output, signal } from '@angular/core';
import { MatSlideToggleChange } from '@angular/material/slide-toggle';
import { MatSnackBar } from '@angular/material/snack-bar';
import { RouterLink } from '@angular/router';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailRow } from '../../../shared/list-detail/detail-row';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { DetailTab, DetailTabs } from '../../../shared/list-detail/detail-tabs';
import { ToggleRow } from '../../../shared/list-detail/toggle-row';
import { formatCount } from '../../../shared/staff/staff-format';
import { PayRulesDetail } from '../../pay-setup/components/pay-rules-detail';
import { ScheduleTab } from '../../shifts/components/schedule-tab';
import { ShiftsStore } from '../../shifts/data/shifts-store';
import { daysLabel, shiftTimes } from '../../shifts/data/shifts.models';
import { AttendanceRulesStore } from '../data/attendance-rules';
import { LeaveRulesStore } from '../data/leave-rules';
import { AttendanceSettings } from './attendance-settings';
import { LeaveSettings } from './leave-settings';
import { TermsSettings } from './terms-settings';
import { WorkHoursSettings } from './work-hours-settings';

const STAFF = '/settings/staff';

/**
 * Settings › Staff, in routable tabs (`/settings/staff/<tab>`): General (the few things most
 * venues set: working hours, whether clock-ins are checked against the venue's location, paid
 * leave a year), Schedule (shifts, roster, staff holidays), then every other rule set with the
 * values it already has: Clock-in, Attendance, Leave, Terms (the staff terms everyone but owners
 * accepts on the floor app) and, for Payroll holders, Payroll. Location
 * checks are off for a new venue; turning them on needs the venue's location (Clock-in tab) and
 * then flags clock-ins away from it for review.
 */
@Component({
  selector: 'app-staff-settings',
  imports: [
    DetailPane,
    DetailSection,
    DetailRow,
    DetailTabs,
    ToggleRow,
    RouterLink,
    ScheduleTab,
    AttendanceSettings,
    WorkHoursSettings,
    LeaveSettings,
    TermsSettings,
    PayRulesDetail,
  ],
  template: `
    <app-detail-pane
      crumb="Settings / Staff"
      icon="badge"
      heading="Staff"
      subtitle="How your team clocks in, and the rules attendance and pay follow"
      (closed)="closed.emit()"
    >
      <app-detail-tabs label="Staff settings" [tabs]="tabs()" [active]="current()">
        @switch (current()) {
          @case ('general') {
          <app-detail-section heading="Working hours">
            @for (s of shifts(); track s.id) {
              <app-detail-row [label]="s.name" [value]="times(s) + ' · ' + days(s.days)" />
            } @empty {
              <p class="text-sm leading-[1.4] text-muted">
                No working hours yet. Without a shift every day is a day off, so nobody is shown absent.
              </p>
            }
            <a class="text-sm font-medium text-primary-text" routerLink="/settings/staff/schedule"
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
          }
          @case ('schedule') {
            <app-schedule-tab [shiftId]="item()" />
          }
          @case ('clock-in') {
            <app-attendance-settings />
          }
          @case ('attendance') {
            <app-work-hours-settings />
          }
          @case ('leave') {
            <app-leave-settings />
          }
          @case ('terms') {
            <app-terms-settings />
          }
          @case ('payroll') {
            <app-pay-rules-detail />
          }
        }
      </app-detail-tabs>
    </app-detail-pane>
  `,
})
export class StaffSettings {
  protected readonly rules = inject(AttendanceRulesStore);
  private readonly leaveRules = inject(LeaveRulesStore);
  private readonly shiftsStore = inject(ShiftsStore);
  private readonly arena = inject(ArenaContext);
  private readonly snack = inject(MatSnackBar);

  /** `/settings/staff/<tab>` (General when missing or not allowed). */
  readonly tab = input<string | undefined>(undefined);
  /** `/settings/staff/<tab>/<item>`: the shift open on Schedule. */
  readonly item = input<string | undefined>(undefined);
  readonly closed = output<void>();

  protected readonly times = shiftTimes;
  protected readonly days = daysLabel;
  protected readonly canEdit = this.arena.canEdit;
  protected readonly canPay = computed(() => this.arena.hasPerm('payroll'));
  protected readonly busy = signal(false);

  protected readonly tabs = computed<DetailTab[]>(() => [
    { key: 'general', label: 'General', link: STAFF },
    { key: 'schedule', label: 'Schedule', link: [STAFF, 'schedule'] },
    { key: 'clock-in', label: 'Clock-in', link: [STAFF, 'clock-in'] },
    { key: 'attendance', label: 'Attendance', link: [STAFF, 'attendance'] },
    { key: 'leave', label: 'Leave', link: [STAFF, 'leave'] },
    { key: 'terms', label: 'Terms', link: [STAFF, 'terms'] },
    ...(this.canPay() ? [{ key: 'payroll', label: 'Payroll', link: [STAFF, 'payroll'] }] : []),
  ]);
  protected readonly current = computed(
    () => this.tabs().find((t) => t.key === this.tab())?.key ?? 'general',
  );
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
        'Set the venue location first, on the Clock-in tab.',
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
