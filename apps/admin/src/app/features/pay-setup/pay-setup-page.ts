import { Component, computed, effect, inject, input } from '@angular/core';
import { MatButton, MatIconButton } from '@angular/material/button';
import { MatIcon } from '@angular/material/icon';
import { MatProgressBar } from '@angular/material/progress-bar';
import { Router } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { Clock } from '../../core/time/clock';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { ListRow } from '../../shared/list-detail/list-row';
import { StatusPill } from '../../shared/status-pill/status-pill';
import { formatIsoDate } from '../../shared/time/ist';
import { initials } from '../users/components/user-format';
import { PayRulesDetail } from './components/pay-rules-detail';
import { StaffPayDetail } from './components/staff-pay-detail';
import { PaySetupStore } from './data/pay-setup-store';
import { PayStaff, rateOn } from './data/pay-setup.models';
import { rateShort } from './dialogs/pay-rate-dialog';

/** The permission this screen needs (the owner holds every permission). */
export const PAY_SETUP_PERM = 'payroll';

/**
 * Staff › Pay setup (docs/STAFF.md §6): the arena's pay rules, then every staff member (inactive
 * ones too, marked) with their HR profile and effective-dated pay rates. The selection is in the
 * URL (`?id=rules` or `?id=<staff id>`).
 */
@Component({
  selector: 'app-pay-setup-page',
  imports: [
    ListDetail,
    ListPaneHeader,
    ListRow,
    StatusPill,
    StaffPayDetail,
    PayRulesDetail,
    MatButton,
    MatIconButton,
    MatIcon,
    MatProgressBar,
  ],
  template: `
    <app-list-detail
      listLabel="Pay setup"
      [detailLabel]="selectedStaff() ? 'Pay setup' : 'Pay rules'"
      emptyText="Pick a person or the pay rules"
      [open]="rules() || !!selectedStaff()"
      (closed)="close()"
    >
      <ng-container list>
        <app-list-pane-header title="Pay setup">
          <div class="flex items-center gap-2">
            <p class="min-w-0 flex-1 text-[13px] leading-[1.3] text-muted" aria-live="polite">
              {{ summary() }}
            </p>
            <button
              mat-icon-button
              type="button"
              class="arena-compact"
              aria-label="Refresh"
              [disabled]="store.loading()"
              (click)="store.refresh()"
            >
              <mat-icon aria-hidden="true">refresh</mat-icon>
            </button>
          </div>
        </app-list-pane-header>
        @if (store.loading()) {
          <mat-progress-bar mode="indeterminate" aria-label="Loading pay setup" />
        }
        <div class="flex min-h-0 flex-1 flex-col overflow-y-auto p-2">
          @if (store.loadError(); as error) {
            <div class="flex flex-col items-center gap-3 px-4 py-12 text-center">
              <p role="alert" class="text-sm text-danger">{{ error }}</p>
              <button mat-stroked-button type="button" (click)="store.load(true)">Try again</button>
            </div>
          } @else if (store.data()) {
            <ul class="flex flex-col gap-0.5" aria-label="Pay setup">
              <li>
                <app-list-row
                  title="Pay rules"
                  subtitle="Pay period, deductions, late rule, extra hours"
                  icon="rule"
                  [selected]="rules()"
                  [queryParams]="{ id: 'rules' }"
                />
              </li>
              @for (s of store.staff(); track s.id) {
                <li>
                  <app-list-row
                    [title]="s.name"
                    [subtitle]="rateText(s)"
                    [initials]="initialsOf(s.name)"
                    [selected]="s.id === selectedStaff()?.id"
                    [queryParams]="{ id: s.id }"
                  >
                    @if (!s.active) {
                      <app-status-pill tone="danger">Inactive</app-status-pill>
                    }
                  </app-list-row>
                </li>
              }
            </ul>
          }
        </div>
      </ng-container>
      <ng-container detail>
        @if (selectedStaff(); as s) {
          <app-staff-pay-detail [staff]="s" (closed)="close()" />
        } @else if (rules()) {
          <app-pay-rules-detail (closed)="close()" />
        }
      </ng-container>
    </app-list-detail>
  `,
})
export class PaySetupPage {
  protected readonly store = inject(PaySetupStore);
  private readonly arena = inject(ArenaContext);
  private readonly router = inject(Router);
  private readonly today = formatIsoDate(inject(Clock).now());

  /** `?id=` — `rules` or a staff profile id. */
  readonly id = input<string>();

  protected readonly initialsOf = initials;
  protected readonly rules = computed(() => this.id() === 'rules');
  protected readonly selectedStaff = computed(() => {
    const id = this.id();
    return id && id !== 'rules' ? this.store.staff().find((s) => s.id === id) : undefined;
  });
  protected readonly summary = computed(() => {
    const staff = this.store.staff();
    const unpaid = staff.filter(
      (s) => s.active && !rateOn(this.store.ratesOf(s.id), this.today),
    ).length;
    return [
      `${staff.length} ${staff.length === 1 ? 'person' : 'people'}`,
      unpaid ? `${unpaid} without a pay rate` : '',
    ]
      .filter(Boolean)
      .join(' · ');
  });

  constructor() {
    effect(() => {
      if (this.arena.current().id) void this.store.load();
    });
    effect(() => {
      if (this.arena.loaded() && this.arena.current().id && !this.arena.hasPerm(PAY_SETUP_PERM)) {
        void this.router.navigateByUrl('/overview');
      }
    });
  }

  protected rateText(s: PayStaff): string {
    const r = rateOn(this.store.ratesOf(s.id), this.today);
    return r ? rateShort(r) : 'No pay rate';
  }

  protected close(): void {
    void this.router.navigate([], { queryParams: { id: null }, queryParamsHandling: 'merge' });
  }
}
