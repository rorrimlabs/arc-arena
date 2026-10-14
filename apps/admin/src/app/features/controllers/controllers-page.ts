import { Component, computed, effect, inject, input } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatProgressBar } from '@angular/material/progress-bar';
import { MatSnackBar } from '@angular/material/snack-bar';
import { Router } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { FloorRead, FloorStore } from '../../core/floor/floor-store';
import { Layout } from '../../core/layout/layout';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { ListRow } from '../../shared/list-detail/list-row';
import { StatusPill } from '../../shared/status-pill/status-pill';
import { ControllerDetail } from './components/controller-detail';
import { ControllersStore } from './data/controllers-store';
import { Controller, statusInfo } from './data/controller.models';
import {
  ControllerDialog,
  ControllerDialogData,
  ControllerDialogResult,
} from './dialogs/controller-dialog';

interface StationGroup {
  readonly id: string;
  readonly heading: string;
  readonly pads: readonly Controller[];
}

/**
 * Controllers: the arena's pads, listed under the station each one is at now (a lent pad shows
 * where it belongs). Add, rename, re-home and set the condition here; moving and lending pads is
 * done on the floor app. The selection is in the URL (`?id=<pad>`); on a wide screen the first pad
 * shows when none is chosen.
 */
@Component({
  selector: 'app-controllers-page',
  imports: [
    ListDetail,
    ListPaneHeader,
    ListRow,
    StatusPill,
    ControllerDetail,
    MatButton,
    MatIcon,
    MatProgressBar,
  ],
  template: `
    <app-list-detail
      listLabel="Controllers"
      detailLabel="Controller"
      [open]="!!selected()"
      (closed)="close()"
    >
      <ng-container list>
        <app-list-pane-header title="Controllers">
          <button
            actions
            mat-flat-button
            type="button"
            [disabled]="!arena.canEdit() || !onFloor().length"
            (click)="add()"
          >
            <mat-icon aria-hidden="true">add</mat-icon>Add
          </button>
        </app-list-pane-header>
        @if (loading()) {
          <mat-progress-bar mode="indeterminate" aria-label="Loading controllers" />
        }
        <div class="flex min-h-0 flex-1 flex-col overflow-y-auto p-2">
          @if (error(); as message) {
            <div class="flex flex-col items-center gap-3 px-4 py-12 text-center">
              <p role="alert" class="text-sm text-danger">{{ message }}</p>
              <button mat-stroked-button type="button" (click)="load(true)">Try again</button>
            </div>
          } @else if (ready()) {
            @for (g of groups(); track g.id) {
              <section [attr.aria-labelledby]="'pads-' + g.id">
                <h2
                  [id]="'pads-' + g.id"
                  class="px-3 pt-4 pb-2 text-xs leading-none font-semibold text-subtle"
                >
                  {{ g.heading }}
                </h2>
                <ul class="flex flex-col gap-0.5">
                  @for (c of g.pads; track c.id) {
                    <li>
                      <app-list-row
                        [title]="c.label"
                        [subtitle]="subtitle(c)"
                        icon="videogame_asset"
                        [selected]="c.id === selected()?.id"
                        [queryParams]="{ id: c.id }"
                      >
                        <app-status-pill [tone]="tone(c)">{{ label(c) }}</app-status-pill>
                      </app-list-row>
                    </li>
                  }
                </ul>
              </section>
            } @empty {
              <p class="px-4 py-12 text-center text-sm leading-[1.4] text-muted">
                {{
                  onFloor().length
                    ? 'No controllers yet. Add each pad with the label written on it, e.g. HEX-1, so staff can see which are free.'
                    : 'Add a station first, then its controllers.'
                }}
              </p>
            }
          }
        </div>
      </ng-container>
      <ng-container detail>
        @if (selected(); as c) {
          <app-controller-detail [controller]="c" (closed)="close()" />
        }
      </ng-container>
    </app-list-detail>
  `,
})
export class ControllersPage {
  protected readonly store = inject(ControllersStore);
  protected readonly floor = inject(FloorStore);
  protected readonly arena = inject(ArenaContext);
  private readonly layout = inject(Layout);
  private readonly router = inject(Router);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  /** What this screen reads from the floor (and reports errors for). */
  private readonly reads: readonly FloorRead[] = ['stations'];

  /** `?id=` — the selected pad. */
  readonly id = input<string>();

  protected readonly loading = computed(() => this.store.loading() || this.floor.loading());
  protected readonly error = computed(
    () => this.store.loadError() || this.floor.errorOf(this.reads),
  );
  protected readonly ready = computed(() => this.store.ready() && this.floor.stationsReady());
  /** Stations a pad can be added to (removed ones are left out). */
  protected readonly onFloor = computed(() =>
    this.floor.stations().filter((s) => s.status !== 'disabled'),
  );
  /** Pads by the station they are at, in the floor's station order. */
  protected readonly groups = computed<StationGroup[]>(() => {
    const stations = this.floor.stations();
    const pads = this.store.controllers();
    const usable = (list: readonly Controller[]) =>
      `${list.filter((c) => c.status === 'usable').length} of ${list.length} usable`;
    const groups: StationGroup[] = stations
      .map((s) => {
        const here = pads.filter((c) => c.currentId === s.id);
        const name = s.status === 'disabled' ? `${s.name} (removed)` : s.name;
        return { id: s.id, heading: `${name} · ${usable(here)}`, pads: here };
      })
      .filter((g) => g.pads.length);
    const known = new Set(stations.map((s) => s.id));
    const lost = pads.filter((c) => !known.has(c.currentId));
    if (lost.length) groups.push({ id: 'unknown', heading: 'Unknown station', pads: lost });
    return groups;
  });
  protected readonly selected = computed<Controller | undefined>(() => {
    const id = this.id();
    if (id) return this.store.byId().get(id);
    return this.layout.wideDetail() ? this.groups()[0]?.pads[0] : undefined;
  });

  constructor() {
    // Load (and reload on an arena switch) what this screen shows.
    effect(() => {
      if (this.arena.current().id) this.load();
    });
  }

  protected load(force = false): void {
    void this.store.load(force);
    void this.floor.load(this.reads, force);
  }

  protected subtitle(c: Controller): string {
    const name = (id: string) => this.floor.stationById().get(id)?.name ?? 'unknown station';
    return (
      [
        c.currentId !== c.homeId ? `Belongs to ${name(c.homeId)}` : '',
        c.loanReturnTo ? 'on loan' : '',
        c.notes ?? '',
      ]
        .filter(Boolean)
        .join(' · ') || 'At home'
    );
  }

  protected tone(c: Controller) {
    return statusInfo(c.status).tone;
  }

  protected label(c: Controller): string {
    return statusInfo(c.status).label;
  }

  protected close(): void {
    void this.router.navigate([], { queryParams: { id: null }, queryParamsHandling: 'merge' });
  }

  protected add(): void {
    this.dialog
      .open<ControllerDialog, ControllerDialogData, ControllerDialogResult>(ControllerDialog, {
        data: { stationId: this.selected()?.currentId },
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((result) => {
        if (!result) return;
        this.snack.open(result.snack, undefined, { duration: 3200 });
        void this.router.navigate([], { queryParams: { id: result.id } });
      });
  }
}
