import { Component, computed, effect, inject, input, linkedSignal, resource } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatFormField, MatPrefix } from '@angular/material/form-field';
import { MatIcon } from '@angular/material/icon';
import { MatInput } from '@angular/material/input';
import { MatProgressBar } from '@angular/material/progress-bar';
import { Router } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { FloorRead, FloorStore } from '../../core/floor/floor-store';
import { MemberRow, initials } from '../../core/floor/floor.models';
import { Layout } from '../../core/layout/layout';
import { injectNow } from '../../core/time/ticker';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { ListRow } from '../../shared/list-detail/list-row';
import { formatRupees } from '../../shared/money/rupees.pipe';
import { MemberDetail } from './components/member-detail';
import { daysAgo } from './data/member-view';

/** Members per page; "Show more" reads the next page from the server. */
const PAGE = 50;

/**
 * Members: registered customers, most recent visit first, searched by name or phone on the
 * server one page at a time (each with its figures). Read-only here: members register on the
 * floor app. Search and selection are in the URL (`?q=…&id=…`); on a wide screen the first member
 * is shown when none is chosen.
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
              (input)="typed($any($event.target).value)"
            />
          </mat-form-field>
          <p class="text-[13px] leading-[1.3] text-muted" aria-live="polite">{{ summary() }}</p>
        </app-list-pane-header>
        @if (page.isLoading()) {
          <mat-progress-bar mode="indeterminate" aria-label="Loading members" />
        }
        <div class="flex min-h-0 flex-1 flex-col overflow-y-auto p-2">
          @if (page.error()) {
            <div class="flex flex-col items-center gap-3 px-4 py-12 text-center">
              <p role="alert" class="text-sm text-danger">{{ error() }}</p>
              <button mat-stroked-button type="button" (click)="page.reload()">Try again</button>
            </div>
          } @else if (page.hasValue()) {
            <ul class="flex flex-col gap-0.5" aria-label="Members">
              @for (m of members(); track m.id) {
                <li>
                  <app-list-row
                    [title]="m.name"
                    [subtitle]="subtitle(m)"
                    [initials]="initials(m.name)"
                    [selected]="m.id === selected()?.id"
                    [queryParams]="{ id: m.id }"
                    queryParamsHandling="merge"
                  >
                    <span class="text-sm leading-none font-semibold tabular-nums">{{
                      rupees(m.spent30Paise)
                    }}</span>
                    <span class="text-xs leading-none text-muted">30 days</span>
                  </app-list-row>
                </li>
              }
            </ul>
            @if (!members().length) {
              <p class="px-4 py-12 text-center text-sm leading-[1.4] text-muted">
                {{ search() ? 'No members match.' : 'No members yet. Staff register them on the floor app.' }}
              </p>
            }
            @if (total() > members().length) {
              <div class="flex justify-center py-3">
                <button
                  mat-stroked-button
                  type="button"
                  [disabled]="page.isLoading()"
                  (click)="limit.set(limit() + pageSize)"
                >
                  Show more · {{ total() - members().length }} left
                </button>
              </div>
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
  /** Names of stations and games in a member's bills. */
  private readonly reads: readonly FloorRead[] = ['stations', 'games'];
  private readonly arena = inject(ArenaContext);
  private readonly layout = inject(Layout);
  private readonly router = inject(Router);

  /** `?id=` — the selected member. */
  readonly id = input<string>();
  /** `?q=` — the search (a link from a game's top players opens it on that member). */
  readonly q = input<string>();

  protected readonly now = injectNow(60_000);
  protected readonly initials = initials;
  protected readonly rupees = formatRupees;
  protected readonly pageSize = PAGE;
  /** What the field shows; the server is searched a moment after typing stops. */
  protected readonly query = linkedSignal(() => this.q() ?? '');
  protected readonly search = linkedSignal(() => this.q() ?? '');
  /** How many rows to read (grows with "Show more"; a new search starts again). */
  protected readonly limit = linkedSignal({ source: this.search, computation: () => PAGE });
  private timer: ReturnType<typeof setTimeout> | undefined;

  protected readonly page = resource({
    params: () => ({
      arena: this.arena.current().id,
      search: this.search(),
      limit: this.limit(),
      revision: this.floor.revision(),
    }),
    loader: ({ params }) =>
      params.arena
        ? this.floor.members(params.search, params.limit, 0)
        : Promise.resolve({ total: 0, rows: [] }),
  });
  protected readonly members = computed<readonly MemberRow[]>(() =>
    this.page.hasValue() ? this.page.value().rows : [],
  );
  protected readonly total = computed(() => (this.page.hasValue() ? this.page.value().total : 0));
  protected readonly error = computed(() =>
    this.page.error() ? 'Members couldn\'t load. Check the connection and try again.' : '',
  );
  protected readonly summary = computed(() => {
    const n = this.total();
    return `${n} member${n === 1 ? '' : 's'} · plans not connected yet`;
  });
  protected readonly selected = computed<MemberRow | undefined>(() => {
    const id = this.id();
    if (id) return this.members().find((m) => m.id === id);
    return this.layout.wideDetail() ? this.members()[0] : undefined;
  });

  constructor() {
    effect(() => {
      if (this.arena.current().id) void this.floor.load(this.reads);
    });
  }

  protected typed(value: string): void {
    this.query.set(value);
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.search.set(value.trim()), 250);
  }

  protected subtitle(m: MemberRow): string {
    const visits = `${m.visits} visit${m.visits === 1 ? '' : 's'}`;
    return `${visits} · last ${daysAgo(m.lastVisit, this.now()).toLowerCase()}`;
  }

  protected close(): void {
    void this.router.navigate([], { queryParams: { id: null }, queryParamsHandling: 'merge' });
  }
}
