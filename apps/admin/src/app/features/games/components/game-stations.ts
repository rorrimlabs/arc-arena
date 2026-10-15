import { Component, computed, inject, input, signal } from '@angular/core';
import { MatFormField } from '@angular/material/form-field';
import { MatOption, MatSelect, MatSelectChange } from '@angular/material/select';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { FloorStore } from '../../../core/floor/floor-store';
import { CompatStatus, Game } from '../../../core/floor/floor.models';
import { VenueStore } from '../../../core/venue/venue';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { COMPAT_CHOICES, compatLabel, gameStations, playableCount } from '../data/game-view';

/**
 * Where staff can start a game: one status per station (game.set_compat, saved straight away).
 * A station without a status is not installed; only Playable lets a session start the game
 * there (the floor app and the server refuse it anywhere else).
 */
@Component({
  selector: 'app-game-stations',
  imports: [DetailSection, MatFormField, MatSelect, MatOption],
  template: `
    <app-detail-section
      heading="Stations"
      subtitle="Staff can start this game only on stations marked Playable."
    >
      @if (noneWarning()) {
        <p
          role="note"
          class="flex items-start gap-2 rounded-chip bg-warning-soft px-3 py-2.5 text-[13px] leading-[1.4] font-medium text-warning"
        >
          <span class="icon text-[18px] leading-none" aria-hidden="true">warning</span>
          <span>
            Staff can't start this game anywhere yet. Mark the stations it is installed on as
            Playable.
          </span>
        </p>
      }
      @for (row of rows(); track row.id) {
        <div class="flex items-center justify-between gap-4">
          <span class="flex min-w-0 flex-col gap-1">
            <span class="truncate text-[15px] leading-[1.3]" [id]="'compat-' + row.id">{{
              row.name
            }}</span>
            <span class="truncate text-[13px] leading-[1.3] text-muted">{{ row.types }}</span>
          </span>
          <mat-form-field class="arena-dense w-48 flex-none" subscriptSizing="dynamic">
            <mat-select
              [aria-labelledby]="'compat-' + row.id"
              [value]="row.status"
              [disabled]="saving() !== null || !canEdit()"
              (selectionChange)="set(row.id, row.name, row.status, $event)"
            >
              @for (o of row.options; track o.key) {
                <mat-option [value]="o.key">{{ o.label }}</mat-option>
              }
            </mat-select>
          </mat-form-field>
        </div>
      } @empty {
        <p class="text-[13px] leading-[1.45] text-muted">
          No stations yet. Add them on the Stations screen first.
        </p>
      }
      @if (error()) {
        <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
      }
    </app-detail-section>
  `,
})
export class GameStations {
  private readonly floor = inject(FloorStore);
  private readonly snack = inject(MatSnackBar);
  protected readonly canEdit = inject(ArenaContext).canEdit;

  readonly game = input.required<Game>();

  private readonly venue = inject(VenueStore);
  private readonly stations = computed(() =>
    gameStations(this.floor.stations(), this.venue.gameTypeCodes()),
  );
  private readonly statuses = computed(() => this.floor.compatByGame().get(this.game().id));
  protected readonly rows = computed(() => {
    const statuses = this.statuses();
    return this.stations().map((s) => {
      const status: CompatStatus = statuses?.get(s.id) ?? 'not_installed';
      // A status the floor app set (maintenance…) stays visible until changed here.
      const options = COMPAT_CHOICES.some((c) => c.key === status)
        ? COMPAT_CHOICES
        : [...COMPAT_CHOICES, { key: status, label: compatLabel(status) }];
      return { id: s.id, name: s.name, types: s.activityCodes.join(', '), status, options };
    });
  });
  /** Shown once the statuses are in: no station would let staff start it. */
  protected readonly noneWarning = computed(
    () =>
      this.floor.gameResourcesReady() &&
      this.floor.stationsReady() &&
      this.stations().length > 0 &&
      playableCount(this.statuses(), this.stations()) === 0,
  );
  /** Station id with a change in flight. */
  protected readonly saving = signal<string | null>(null);
  protected readonly error = signal('');

  protected async set(
    stationId: string,
    stationName: string,
    before: CompatStatus,
    event: MatSelectChange,
  ): Promise<void> {
    const status = event.value as CompatStatus;
    const g = this.game();
    this.saving.set(stationId);
    this.error.set('');
    try {
      await this.floor.setGameCompat(g.id, stationId, status);
      this.snack.open(`${g.name} on ${stationName}: ${compatLabel(status)}`, undefined, {
        duration: 3200,
      });
    } catch (e) {
      // Refused: show what the server still holds.
      event.source.value = before;
      this.error.set(toAppError(e).message);
    } finally {
      this.saving.set(null);
    }
  }
}
