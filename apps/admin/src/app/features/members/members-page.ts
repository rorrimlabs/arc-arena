import { Component, computed, effect, inject, input, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatFormField, MatPrefix } from '@angular/material/form-field';
import { MatIcon } from '@angular/material/icon';
import { MatInput } from '@angular/material/input';
import { MatProgressBar } from '@angular/material/progress-bar';
import { Router } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { FloorStore } from '../../core/floor/floor-store';
import { initials } from '../../core/floor/floor.models';
import { Layout } from '../../core/layout/layout';
import { injectNow } from '../../core/time/ticker';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { ListRow } from '../../shared/list-detail/list-row';
import { formatRupees } from '../../shared/money/rupees.pipe';
import { MemberDetail } from './components/member-detail';
import { MemberSummary, daysAgo, matchesMember, summarizeMembers } from './data/member-view';

/**
 * Members (design: `if (p === 'members')`): registered customers, most recent visit first,
 * searchable by name or phone. Read-only here: members register on the floor app. Selection is
 * in the URL (`?id=`); on a wide screen the first member is shown when none is chosen.
 */
@Component({
  selector: 'app-members-page',
  imports: [
    ListDetail,
    ListPaneHeader,
    ListRow,
    MemberDetail,
    MatButton,
    MatFormField,
    MatPrefix,
    MatIcon,
    MatInput,
    MatProgressBar,
  ],
  template: `
    <app-list-detail
      listLabel="Members"
      detailLabel="Member"
      [open]="!!selected()"
      (closed)="close()"
    >
      <ng-container list>
        <app-list-pane-header title="Members">
          <mat-form-field class="arena-search">
            <mat-icon matPrefix aria-hidden="true">search</mat-icon>
            <input
              matInput
              type="search"
              aria-label="Search members"
              placeholder="Name or phone"
              [value]="query()"
              (input)="query.set($any($event.target).value)"
            />
          </mat-form-field>
          <p class="text-[13px] leading-[1.3] text-muted" aria-live="polite">{{ summary() }}</p>
        </app-list-pane-header>
        @if (floor.loading()) {
          <mat-progress-bar mode="indeterminate" aria-label="Loading members" />
        }
        <div class="flex min-h-0 flex-1 flex-col overflow-y-auto p-2">
          @if (floor.loadError(); as error) {
            <div class="flex flex-col items-center gap-3 px-4 py-12 text-center">
              <p role="alert" class="text-sm text-danger">{{ error }}</p>
              <button mat-stroked-button type="button" (click)="load(true)">Try again</button>
            </div>
          } @else if (!floor.loading() || members().length) {
            <ul class="flex flex-col gap-0.5" aria-label="Members">
              @for (m of filtered(); track m.customer.id) {
                <li>
                  <app-list-row
                    [title]="m.customer.name"
                    [subtitle]="subtitle(m)"
                    [initials]="initials(m.customer.name)"
                    [selected]="m.customer.id === selected()?.customer?.id"
                    [queryParams]="{ id: m.customer.id }"
                  >
                    <span class="text-sm leading-none font-semibold tabular-nums">{{
                      rupees(m.spent30Paise)
                    }}</span>
                    <span class="text-xs leading-none text-muted">30 days</span>
                  </app-list-row>
                </li>
              }
            </ul>
            @if (!filtered().length) {
              <p class="px-4 py-12 text-center text-sm leading-[1.4] text-muted">
                {{
                  members().length
                    ? 'No members match.'
                    : 'No members yet. Staff register them on the floor app.'
                }}
              </p>
            }
          }
        </div>
      </ng-container>
      <ng-container detail>
        @if (selected(); as m) {
          <app-member-detail [member]="m" [now]="now()" (closed)="close()" />
        }
      </ng-container>
    </app-list-detail>
  `,
})
export class MembersPage {
  protected readonly floor = inject(FloorStore);
  private readonly arena = inject(ArenaContext);
  private readonly layout = inject(Layout);
  private readonly router = inject(Router);

  /** `?id=` — the selected member. */
  readonly id = input<string>();

  protected readonly now = injectNow(60_000);
  protected readonly initials = initials;
  protected readonly rupees = formatRupees;
  protected readonly query = signal('');

  protected readonly members = computed(() =>
    summarizeMembers(this.floor.customers(), this.floor.visits(), this.floor.plays(), this.now()),
  );
  protected readonly filtered = computed(() =>
    this.members().filter((m) => matchesMember(m.customer, this.query())),
  );
  protected readonly summary = computed(() => {
    const n = this.filtered().length;
    return `${n} member${n === 1 ? '' : 's'} · plans not connected yet`;
  });
  protected readonly selected = computed<MemberSummary | undefined>(() => {
    const id = this.id();
    if (id) return this.members().find((m) => m.customer.id === id);
    return this.layout.wideDetail() ? this.filtered()[0] : undefined;
  });

  constructor() {
    effect(() => {
      if (this.arena.current().id) void this.load();
    });
  }

  protected load(force = false): void {
    void this.floor.load(['stations', 'games', 'customers', 'plays', 'visits'], force);
  }

  protected subtitle(m: MemberSummary): string {
    const visits = `${m.visits} visit${m.visits === 1 ? '' : 's'}`;
    return `${visits} · last ${daysAgo(m.lastVisit, this.now()).toLowerCase()}`;
  }

  protected close(): void {
    void this.router.navigate([], { queryParams: { id: null }, queryParamsHandling: 'merge' });
  }
}
