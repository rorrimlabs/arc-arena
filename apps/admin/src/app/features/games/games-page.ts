import { Component, computed, effect, inject, input, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatChipListbox, MatChipListboxChange, MatChipOption } from '@angular/material/chips';
import { MatDialog } from '@angular/material/dialog';
import { MatFormField, MatPrefix } from '@angular/material/form-field';
import { MatIcon } from '@angular/material/icon';
import { MatInput } from '@angular/material/input';
import { MatProgressBar } from '@angular/material/progress-bar';
import { MatSnackBar } from '@angular/material/snack-bar';
import { Router } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { FloorRead, FloorStore } from '../../core/floor/floor-store';
import { Game } from '../../core/floor/floor.models';
import { Layout } from '../../core/layout/layout';
import { injectNow } from '../../core/time/ticker';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { ListRow } from '../../shared/list-detail/list-row';
import { StatusPill } from '../../shared/status-pill/status-pill';
import { formatMinutes } from '../../shared/time/ist';
import { PricingStore } from '../pricing/data/pricing-store';
import { GameDetail } from './components/game-detail';
import {
  ageTone,
  gameIcon,
  gameStations,
  knownPlatforms,
  libraryOrder,
  platformLabel,
  playableCount,
} from './data/game-view';
import { GameDialog, GameDialogData, GameDialogResult } from './dialogs/game-dialog';

/**
 * Games (design: `if (p === 'games')`): the catalog staff pick from, searchable and filtered by
 * platform, with 30-day play. Platform and selection are in the URL (`?platform=PS5&id=…`); on a
 * wide screen the first game is shown when none is chosen, as in the design.
 */
@Component({
  selector: 'app-games-page',
  imports: [
    ListDetail,
    ListPaneHeader,
    ListRow,
    StatusPill,
    GameDetail,
    MatButton,
    MatChipListbox,
    MatChipOption,
    MatFormField,
    MatPrefix,
    MatIcon,
    MatInput,
    MatProgressBar,
  ],
  template: `
    <app-list-detail listLabel="Games" detailLabel="Game" [open]="!!selected()" (closed)="close()">
      <ng-container list>
        <app-list-pane-header title="Games">
          <button
            actions
            mat-flat-button
            type="button"
            [disabled]="!arena.canEdit()"
            (click)="add()"
          >
            <mat-icon aria-hidden="true">add</mat-icon>Add
          </button>
          <mat-form-field class="arena-search">
            <mat-icon matPrefix aria-hidden="true">search</mat-icon>
            <input
              matInput
              type="search"
              aria-label="Search games"
              placeholder="Search games"
              [value]="query()"
              (input)="query.set($any($event.target).value)"
            />
          </mat-form-field>
          @if (chips().length > 1) {
            <mat-chip-listbox aria-label="Platform" [value]="platform()" (change)="pick($event)">
              @for (c of chips(); track c.key) {
                <mat-chip-option [value]="c.key" [selectable]="c.key !== platform()">{{
                  c.label
                }}</mat-chip-option>
              }
            </mat-chip-listbox>
          }
        </app-list-pane-header>
        @if (loading()) {
          <mat-progress-bar mode="indeterminate" aria-label="Loading games" />
        }
        <div class="flex min-h-0 flex-1 flex-col overflow-y-auto p-2">
          @if (floor.errorOf(reads); as error) {
            <div class="flex flex-col items-center gap-3 px-4 py-12 text-center">
              <p role="alert" class="text-sm text-danger">{{ error }}</p>
              <button mat-stroked-button type="button" (click)="load(true)">Try again</button>
            </div>
          } @else if (!loading() || floor.games().length) {
            <ul class="flex flex-col gap-0.5" aria-label="Games">
              @for (g of filtered(); track g.id) {
                <li>
                  <app-list-row
                    [title]="g.name"
                    [subtitle]="subtitle(g)"
                    [icon]="icon(g)"
                    [selected]="g.id === selected()?.id"
                    [queryParams]="{ id: g.id }"
                    queryParamsHandling="merge"
                  >
                    @if (g.ageRating) {
                      <app-status-pill [tone]="ageTone(g.ageRating)"
                        >{{ g.ageRating }}+</app-status-pill
                      >
                    }
                    @if (unplayable().has(g.id)) {
                      <app-status-pill
                        tone="warning"
                        title="Staff can't start this game anywhere yet"
                        >No station</app-status-pill
                      >
                    }
                  </app-list-row>
                </li>
              }
            </ul>
            @if (!filtered().length) {
              <p class="px-4 py-12 text-center text-sm leading-[1.4] text-muted">
                {{ floor.games().length ? 'No games match.' : 'No games yet. Add the first one.' }}
              </p>
            }
          }
        </div>
      </ng-container>
      <ng-container detail>
        @if (selected(); as g) {
          <app-game-detail
            [game]="g"
            [stats]="stats().get(g.id)"
            [now]="now()"
            (closed)="close()"
            (edit)="edit(g)"
            (deleted)="close()"
          />
        }
      </ng-container>
    </app-list-detail>
  `,
})
export class GamesPage {
  protected readonly floor = inject(FloorStore);
  private readonly pricing = inject(PricingStore);
  protected readonly arena = inject(ArenaContext);
  private readonly layout = inject(Layout);
  private readonly router = inject(Router);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  /** `?platform=` — a platform code, or all. */
  readonly platformParam = input<string>(undefined, { alias: 'platform' });
  /** `?id=` — the selected game. */
  readonly id = input<string>();

  /**
   * What this screen reads (and reports errors for): the catalog, where each game is installed
   * and its 30-day figures aggregated on the server. A game's top players are read when opened.
   */
  protected readonly reads: readonly FloorRead[] = [
    'games',
    'stations',
    'gameResources',
    'gameFigures',
  ];
  protected readonly now = injectNow(60_000);
  protected readonly loading = computed(() => this.floor.loading());
  protected readonly query = signal('');

  protected readonly stats = computed(() => this.floor.gameFigures());
  protected readonly platforms = computed(() => knownPlatforms(this.floor.games()));
  protected readonly platform = computed(() => {
    const p = this.platformParam();
    return p && this.platforms().includes(p) ? p : 'all';
  });
  protected readonly chips = computed(() => [
    { key: 'all', label: 'All' },
    ...this.platforms().map((p) => ({ key: p, label: p })),
  ]);
  protected readonly filtered = computed(() => {
    const p = this.platform();
    const q = this.query().trim().toLowerCase();
    return libraryOrder(this.floor.games()).filter(
      (g) =>
        (p === 'all' || g.platforms.includes(p)) &&
        (!q || [g.name, ...g.aliases].some((x) => x.toLowerCase().includes(q))),
    );
  });
  /** Games staff could pick but no station lets them start (warned in the list). */
  protected readonly unplayable = computed(() => {
    if (!this.floor.gameResourcesReady() || !this.floor.stationsReady()) return new Set<string>();
    const stations = gameStations(this.floor.stations());
    const byGame = this.floor.compatByGame();
    return new Set(
      this.floor
        .games()
        .filter((g) => g.active && playableCount(byGame.get(g.id), stations) === 0)
        .map((g) => g.id),
    );
  });
  protected readonly selected = computed<Game | undefined>(() => {
    const id = this.id();
    if (id) return this.floor.gameById().get(id);
    return this.layout.wideDetail() ? this.filtered()[0] : undefined;
  });

  constructor() {
    effect(() => {
      if (this.arena.current().id) void this.load();
    });
  }

  protected load(force = false): void {
    void this.floor.load(this.reads, force);
    void this.pricing.load(force);
  }

  protected subtitle(g: Game): string {
    const minutes = this.stats().get(g.id)?.minutes30 ?? 0;
    return [platformLabel(g), g.active ? '' : 'archived', formatMinutes(minutes)]
      .filter(Boolean)
      .join(' · ');
  }

  protected readonly ageTone = ageTone;

  protected icon(g: Game): string {
    return gameIcon(g);
  }

  protected pick(event: MatChipListboxChange): void {
    if (!event.value) return;
    void this.router.navigate([], {
      queryParams: { platform: event.value === 'all' ? null : event.value },
      queryParamsHandling: 'merge',
    });
  }

  protected close(): void {
    void this.router.navigate([], { queryParams: { id: null }, queryParamsHandling: 'merge' });
  }

  protected add(): void {
    const platform = this.platform();
    this.open({
      platforms: this.platformChoices(),
      platform: platform === 'all' ? undefined : platform,
      stations: gameStations(this.floor.stations()).map((s) => ({ id: s.id, name: s.name })),
    });
  }

  protected edit(game: Game): void {
    this.open({ platforms: this.platformChoices(), stations: [], game });
  }

  /** Platforms in use plus the game-based station types (what a game can be marked for). */
  private platformChoices(): string[] {
    const fromTypes = this.pricing
      .types()
      .filter((t) => t.usesGames && t.active)
      .map((t) => t.code);
    return knownPlatforms(this.floor.games(), fromTypes);
  }

  private open(data: GameDialogData): void {
    this.dialog
      .open<GameDialog, GameDialogData, GameDialogResult>(GameDialog, {
        data,
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((result) => {
        if (!result) return;
        this.snack.open(result.snack, undefined, { duration: 3200 });
        if (data.game) return;
        this.query.set('');
        void this.router.navigate([], { queryParams: { platform: null, id: result.id } });
      });
  }
}
