import { Component, computed, inject, input, output, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatFormField, MatLabel } from '@angular/material/form-field';
import { MatIcon } from '@angular/material/icon';
import { MatOption, MatSelect } from '@angular/material/select';
import { MatSlideToggleChange } from '@angular/material/slide-toggle';
import { MatSnackBar } from '@angular/material/snack-bar';
import { toAppError } from '../../../core/auth/auth-api';
import { FloorStore } from '../../../core/floor/floor-store';
import { Game } from '../../../core/floor/floor.models';
import { ConfirmDialog, ConfirmDialogData } from '../../../shared/confirm/confirm-dialog';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { LineRow } from '../../../shared/list-detail/line-row';
import { ToggleRow } from '../../../shared/list-detail/toggle-row';
import { StatTile } from '../../../shared/stat-tile/stat-tile';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { formatMinutes } from '../../../shared/time/ist';
import {
  AGE_RATINGS,
  ageTone,
  mediaLabel,
  GameStats,
  MEDIA,
  gameIcon,
  platformLabel,
  playerModeLabel,
  topFans,
} from '../data/game-view';
import { GameStations } from './game-stations';

/**
 * Design: `if (p === 'games')` detail. 30-day play, availability to staff, the stations it can
 * be started on, and the members who play it most. Remove hides it from staff (the catalog keeps it for past bills); age rating and
 * media are shown as designed but not stored yet.
 */
@Component({
  selector: 'app-game-detail',
  imports: [
    DetailPane,
    DetailSection,
    GameStations,
    LineRow,
    ToggleRow,
    StatTile,
    StatusPill,
    MatButton,
    MatIcon,
    MatFormField,
    MatLabel,
    MatSelect,
    MatOption,
  ],
  template: `
    @let g = game();
    <app-detail-pane
      [crumb]="'Games / ' + g.name"
      [icon]="icon()"
      [heading]="g.name"
      [subtitle]="platform() + ' · ' + players()"
      (closed)="closed.emit()"
    >
      @if (g.active) {
        <div actions class="arena-compact flex gap-2">
          <button
            mat-button
            type="button"
            class="danger-action"
            [disabled]="busy()"
            (click)="remove()"
          >
            <mat-icon aria-hidden="true">delete</mat-icon>Remove
          </button>
        </div>
      }
      <div chip class="flex gap-2">
        @if (g.ageRating) {
          <app-status-pill [tone]="ageTone(g.ageRating)">{{ g.ageRating }}+</app-status-pill>
        }
        <app-status-pill [tone]="g.active ? 'primary' : 'info'">{{
          g.active ? 'Available' : 'Hidden'
        }}</app-status-pill>
      </div>

      <div stats class="grid grid-cols-[repeat(auto-fit,minmax(130px,1fr))] gap-3">
        <app-stat-tile label="Hours · 30 days" [value]="hours()" />
        <app-stat-tile label="Sessions · 30 days" [value]="(stats()?.sessions30 ?? 0).toString()" />
        <app-stat-tile label="Playing now" [value]="(stats()?.playingNow ?? 0).toString()" />
      </div>

      <app-detail-section heading="Availability">
        <app-toggle-row
          label="Available to staff"
          [sub]="g.active ? 'Shown when starting a session' : 'Hidden from the game list'"
          [checked]="g.active"
          [disabled]="busy()"
          (changed)="setActive($event)"
        />
        <div class="flex flex-col gap-4">
          <mat-form-field>
            <mat-label>Age rating</mat-label>
            <mat-select
              placeholder="Not set"
              [value]="g.ageRating"
              [disabled]="busy()"
              (selectionChange)="saveDetails({ ageRating: $event.value })"
            >
              <mat-option [value]="null">Not set</mat-option>
              @for (a of ages; track a) {
                <mat-option [value]="a">{{ a }}+</mat-option>
              }
            </mat-select>
          </mat-form-field>
          <mat-form-field>
            <mat-label>Media</mat-label>
            <mat-select
              placeholder="Not set"
              [value]="g.media"
              [disabled]="busy()"
              (selectionChange)="saveDetails({ media: $event.value })"
            >
              <mat-option [value]="null">Not set</mat-option>
              @for (m of media; track m.key) {
                <mat-option [value]="m.key">{{ m.label }}</mat-option>
              }
            </mat-select>
          </mat-form-field>
        </div>
        @if (error()) {
          <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
        }
      </app-detail-section>

      <app-game-stations [game]="g" />

      <app-detail-section heading="Plays it most" subtitle="Members, last 30 days">
        @for (f of fans(); track f.customer.id) {
          <app-line-row
            [title]="f.customer.name"
            [subtitle]="f.sessions + (f.sessions === 1 ? ' session' : ' sessions')"
            [value]="minutes(f.minutes)"
            link="/members"
            [queryParams]="{ id: f.customer.id }"
          />
        } @empty {
          <p class="text-[13px] leading-[1.45] text-muted">No member sessions yet.</p>
        }
      </app-detail-section>
    </app-detail-pane>
  `,
})
export class GameDetail {
  private readonly floor = inject(FloorStore);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  readonly game = input.required<Game>();
  readonly stats = input<GameStats | undefined>();
  readonly now = input.required<Date>();
  readonly closed = output<void>();

  protected readonly ages = AGE_RATINGS;
  protected readonly ageTone = ageTone;
  protected readonly media = MEDIA;
  protected readonly minutes = formatMinutes;
  protected readonly icon = computed(() => gameIcon(this.game()));
  protected readonly platform = computed(() =>
    [platformLabel(this.game()), mediaLabel(this.game().media)].filter(Boolean).join(' · '),
  );
  protected readonly players = computed(() => playerModeLabel(this.game()));
  protected readonly hours = computed(() => `${Math.round((this.stats()?.minutes30 ?? 0) / 60)}h`);
  protected readonly fans = computed(() =>
    topFans(this.game().id, this.floor.plays(), this.floor.customerById(), this.now()),
  );
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  protected async setActive(event: MatSlideToggleChange): Promise<void> {
    const ok = await this.change(event.checked);
    if (!ok) event.source.checked = !event.checked;
  }

  protected remove(): void {
    const g = this.game();
    this.dialog
      .open<ConfirmDialog, ConfirmDialogData, boolean>(ConfirmDialog, {
        data: {
          title: `Remove ${g.name}?`,
          message:
            'Staff stop seeing it when starting a session. Past bills keep it, and you can make it available again here.',
          confirm: 'Remove',
          danger: true,
        },
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe(async (yes) => {
        if (yes && (await this.change(false))) {
          this.snack.open(`${g.name} removed`, undefined, { duration: 3200 });
        }
      });
  }

  /** Age rating or media: saved straight away, like the Available switch (game.upsert). */
  protected async saveDetails(change: Partial<Pick<Game, 'ageRating' | 'media'>>): Promise<void> {
    const g = this.game();
    this.busy.set(true);
    this.error.set('');
    try {
      await this.floor.saveGame({ ...g, ...change });
      this.snack.open(`${g.name} saved`, undefined, { duration: 3200 });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }

  private async change(active: boolean): Promise<boolean> {
    this.busy.set(true);
    this.error.set('');
    try {
      await this.floor.setGameActive(this.game().id, active);
      return true;
    } catch (e) {
      this.error.set(toAppError(e).message);
      return false;
    } finally {
      this.busy.set(false);
    }
  }
}
