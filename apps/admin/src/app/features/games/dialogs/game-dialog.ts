import { Component, inject, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import {
  MAT_DIALOG_DATA,
  MatDialogActions,
  MatDialogContent,
  MatDialogRef,
  MatDialogTitle,
} from '@angular/material/dialog';
import { MatFormField, MatHint, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatOption, MatSelect } from '@angular/material/select';
import { toAppError } from '../../../core/auth/auth-api';
import { FloorStore } from '../../../core/floor/floor-store';
import { PushRefusal } from '../../../core/sync/push-ops';
import { AgeRating, GameMedia } from '../../../core/floor/floor.models';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import { AGE_RATINGS, MEDIA } from '../data/game-view';

export interface GameDialogData {
  /** Platforms to choose from (in use, plus the game-based station types). */
  readonly platforms: readonly string[];
  /** The platform picked in the list's filter, if any. */
  readonly platform?: string;
  /** Stations it can be marked playable on (none are picked for it). */
  readonly stations: readonly { readonly id: string; readonly name: string }[];
}

/** Closes with the new game's id and the snackbar text; undefined when cancelled. */
export interface GameDialogResult {
  readonly id: string;
  readonly snack: string;
}

/**
 * Design: dialog `d.k === 'game'`. Adds a game to the catalog staff pick from when starting a
 * session, with its age rating and media (game.upsert), and optionally the stations it is
 * playable on (game.set_compat, in the same batch). Nothing is marked playable unless picked.
 */
@Component({
  selector: 'app-game-dialog',
  providers: [MATERIAL_DEFAULTS],
  imports: [
    MatDialogTitle,
    MatDialogContent,
    MatDialogActions,
    MatFormField,
    MatLabel,
    MatHint,
    MatInput,
    MatSelect,
    MatOption,
    MatButton,
  ],
  template: `
    <h2 mat-dialog-title>Add game</h2>
    <form novalidate (submit)="save($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <p class="text-sm leading-[1.4] text-muted">Staff can pick it when starting a session.</p>
          <mat-form-field>
            <mat-label>Title</mat-label>
            <input
              matInput
              autocomplete="off"
              maxlength="80"
              placeholder="e.g. Mortal Kombat 1"
              [value]="title()"
              (input)="title.set($any($event.target).value)"
            />
          </mat-form-field>
          <mat-form-field>
            <mat-label>Platform</mat-label>
            <mat-select [value]="platform()" (selectionChange)="platform.set($event.value)">
              @for (p of data.platforms; track p) {
                <mat-option [value]="p">{{ p }}</mat-option>
              }
            </mat-select>
          </mat-form-field>
          <div class="flex flex-col gap-5">
            <mat-form-field>
              <mat-label>Age rating</mat-label>
              <mat-select [value]="age()" (selectionChange)="age.set($event.value)">
                @for (a of ages; track a) {
                  <mat-option [value]="a">{{ a }}+</mat-option>
                }
              </mat-select>
            </mat-form-field>
            <mat-form-field>
              <mat-label>Media</mat-label>
              <mat-select [value]="mediaKey()" (selectionChange)="mediaKey.set($event.value)">
                @for (m of media; track m.key) {
                  <mat-option [value]="m.key">{{ m.label }}</mat-option>
                }
              </mat-select>
            </mat-form-field>
          </div>
          <mat-form-field>
            <mat-label>Playable on</mat-label>
            <mat-select
              multiple
              placeholder="No stations yet"
              [disabled]="!data.stations.length"
              [value]="playableOn()"
              (selectionChange)="playableOn.set($event.value)"
            >
              @for (s of data.stations; track s.id) {
                <mat-option [value]="s.id">{{ s.name }}</mat-option>
              }
            </mat-select>
            <mat-hint>Staff can start it only on these. You can change this later.</mat-hint>
          </mat-form-field>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" [disabled]="busy()">Add</button>
      </mat-dialog-actions>
    </form>
  `,
})
export class GameDialog {
  protected readonly data = inject<GameDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<GameDialog, GameDialogResult>>(MatDialogRef);
  private readonly floor = inject(FloorStore);

  protected readonly ages = AGE_RATINGS;
  protected readonly media = MEDIA;
  protected readonly title = signal('');
  /** The design's defaults for a new game: 3+, digital. */
  protected readonly age = signal<AgeRating>(3);
  protected readonly mediaKey = signal<GameMedia>('digital');
  protected readonly platform = signal(this.data.platform ?? this.data.platforms[0] ?? '');
  /** Station ids; none until the owner picks them. */
  protected readonly playableOn = signal<readonly string[]>([]);
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected async save(event: Event): Promise<void> {
    event.preventDefault();
    const name = this.title().trim();
    if (name.length < 2) {
      this.error.set('Enter a title');
      return;
    }
    if (this.floor.games().some((g) => g.name.toLowerCase() === name.toLowerCase())) {
      this.error.set(`${name} is already in the list`);
      return;
    }
    const id = crypto.randomUUID();
    this.busy.set(true);
    this.error.set('');
    const stations = this.playableOn();
    try {
      await this.floor.saveGame(
        {
          id,
          name,
          aliases: [],
          categoryId: null,
          platforms: this.platform() ? [this.platform()] : [],
          playerMode: 'single',
          maxLocalPlayers: 1,
          active: true,
          ageRating: this.age(),
          media: this.mediaKey(),
        },
        stations,
      );
      const on = stations.length;
      this.ref.close({
        id,
        snack: on
          ? `${name} added · playable on ${on} station${on === 1 ? '' : 's'}`
          : `${name} added`,
      });
    } catch (e) {
      const err = toAppError(e);
      if (e instanceof PushRefusal && e.applied.includes('game.upsert')) {
        // The game was saved; only some of its stations were refused. Show it as it is.
        this.ref.close({ id, snack: `${name} added · stations not saved: ${err.message}` });
        return;
      }
      this.error.set(err.message);
    } finally {
      this.busy.set(false);
    }
  }
}
