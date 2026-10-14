import { Component, computed, inject, input, output, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatFormField, MatLabel } from '@angular/material/form-field';
import { MatIcon } from '@angular/material/icon';
import { MatOption, MatSelect, MatSelectChange } from '@angular/material/select';
import { MatSlideToggleChange } from '@angular/material/slide-toggle';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
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
  DeletePlan,
  deletePlan,
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
 * be started on, and the members who play it most. "Available to staff" archives or restores it
 * (game.set_active: hidden from new sessions and bookings, kept for history). Delete removes a
 * game nothing ever used (game.delete); one that is in play or has history is explained instead,
 * with Archive offered. Age rating and media save straight away (game.upsert).
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
      <div actions class="arena-compact flex gap-2">
        <button mat-button type="button" [disabled]="busy() || !canEdit()" (click)="edit.emit()">
          <mat-icon aria-hidden="true">edit</mat-icon>Edit
        </button>
        <button
          mat-button
          type="button"
          class="danger-action"
          [disabled]="busy() || !canEdit()"
          (click)="remove()"
        >
          <mat-icon aria-hidden="true">delete</mat-icon>Delete
        </button>
      </div>
      <div chip class="flex gap-2">
        @if (g.ageRating) {
          <app-status-pill [tone]="ageTone(g.ageRating)">{{ g.ageRating }}+</app-status-pill>
        }
        <app-status-pill [tone]="g.active ? 'primary' : 'info'">{{
          g.active ? 'Available' : 'Archived'
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
          [sub]="
            g.active
              ? 'Shown when starting a session or booking'
              : 'Archived · hidden from new sessions and bookings; past bills keep it'
          "
          [checked]="g.active"
          [disabled]="busy() || !canEdit()"
          (changed)="setActive($event)"
        />
        <div class="flex flex-col gap-4">
          <mat-form-field>
            <mat-label>Age rating</mat-label>
            <mat-select
              placeholder="Not set"
              [value]="g.ageRating"
              [disabled]="busy() || !canEdit()"
              (selectionChange)="saveDetails({ ageRating: $event.value }, $event)"
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
              [disabled]="busy() || !canEdit()"
              (selectionChange)="saveDetails({ media: $event.value }, $event)"
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
  /** Without the Settings permission the server refuses every change here. */
  protected readonly canEdit = inject(ArenaContext).canEdit;
  private readonly floor = inject(FloorStore);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  readonly game = input.required<Game>();
  readonly stats = input<GameStats | undefined>();
  readonly now = input.required<Date>();
  readonly closed = output<void>();
  /** Edit asked for (the page opens the dialog with its platform list). */
  readonly edit = output<void>();
  /** The game was deleted on the server (the page leaves its detail). */
  readonly deleted = output<void>();

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

  /**
   * Delete: reads what still uses the game, then either confirms a permanent delete (nothing
   * ever did) or explains why it cannot be deleted and offers to archive it instead.
   */
  protected async remove(): Promise<void> {
    if (this.busy()) return;
    const g = this.game();
    this.busy.set(true);
    this.error.set('');
    let plan: DeletePlan;
    try {
      plan = deletePlan(await this.floor.gameUsage(g.id));
    } catch (e) {
      this.error.set(toAppError(e).message);
      return;
    } finally {
      this.busy.set(false);
    }
    const archive = g.active ? 'Archive' : undefined;
    const archiveNote = g.active
      ? ' Archive it instead: staff stop seeing it for new sessions and bookings, and you can restore it here.'
      : ' It is already archived, so staff no longer see it.';
    const data: ConfirmDialogData =
      plan.kind === 'delete'
        ? {
            title: `Delete ${g.name} permanently?`,
            message:
              'It was never played or booked. This removes the game, its station statuses and its control guide on every device. It cannot be undone.',
            confirm: 'Delete',
            danger: true,
          }
        : plan.kind === 'in_play'
          ? {
              title: `${g.name} can't be deleted`,
              message:
                'It is being played on the floor right now.' +
                (g.active
                  ? ' Archive it instead: those sessions continue, and staff stop seeing it for new ones.'
                  : ' Those sessions continue until they end.'),
              confirm: archive,
            }
          : {
              title: `${g.name} can't be deleted`,
              message: `${plan.records} past session${plan.records === 1 ? '' : 's'} or booking${plan.records === 1 ? '' : 's'} use it, and deleting it would take it off those records.${archiveNote}`,
              confirm: archive,
            };
    this.dialog
      .open<ConfirmDialog, ConfirmDialogData, boolean>(ConfirmDialog, {
        data,
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe(async (yes) => {
        if (!yes) return;
        if (plan.kind === 'delete') await this.delete(g);
        else if (await this.change(false)) {
          this.snack.open(`${g.name} archived`, undefined, { duration: 3200 });
        }
      });
  }

  private async delete(g: Game): Promise<void> {
    this.busy.set(true);
    this.error.set('');
    try {
      await this.floor.deleteGame(g.id);
      this.snack.open(`${g.name} deleted`, undefined, { duration: 3200 });
      this.deleted.emit();
    } catch (e) {
      // Refused (it was played or booked since the check): the store reloaded what the server holds.
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }

  /**
   * Age rating or media: saved straight away, like the Available switch (game.upsert with the
   * active flag shown, so it never undoes an archive made elsewhere). A refusal puts the select
   * back to what the server holds.
   */
  protected async saveDetails(
    change: Partial<Pick<Game, 'ageRating' | 'media'>>,
    event: MatSelectChange,
  ): Promise<void> {
    const g = this.game();
    const before = 'ageRating' in change ? g.ageRating : g.media;
    this.busy.set(true);
    this.error.set('');
    try {
      await this.floor.saveGame({ ...g, ...change }, [], g.active);
      this.snack.open(`${g.name} saved`, undefined, { duration: 3200 });
    } catch (e) {
      event.source.value = before;
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
