import { Component, computed, inject, signal } from '@angular/core';
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
import { AgeRating, Game, GameMedia, PlayMode } from '../../../core/floor/floor.models';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import { AGE_RATINGS, MAX_PLAYERS, MEDIA, PLAY_MODES } from '../data/game-view';

export interface GameDialogData {
  /** Platforms to choose from (in use, plus the game-based station types). */
  readonly platforms: readonly string[];
  /** The platform picked in the list's filter, if any (a new game starts on it). */
  readonly platform?: string;
  /** Stations a new game can be marked playable on (none are picked for it). */
  readonly stations: readonly { readonly id: string; readonly name: string }[];
  /** The game to edit; absent to add one. */
  readonly game?: Game;
}

/** Closes with the game's id and the snackbar text; undefined when cancelled. */
export interface GameDialogResult {
  readonly id: string;
  readonly snack: string;
}

/** The longest title the server stores (game.upsert refuses longer: invalid_name). */
const MAX_TITLE = 80;

/**
 * Design: dialog `d.k === 'game'`. Adds a game to the catalog staff pick from when starting a
 * session (game.upsert, plus game.set_compat for the stations picked, in the same batch), or edits
 * one: title, platforms, play modes (one or more), players per station, age rating and media. An edit sends the
 * active flag it showed, so it is refused (not applied) if the game was archived or restored
 * elsewhere meanwhile. Station statuses of an existing game are set on its detail pane.
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
    <h2 mat-dialog-title>{{ editing ? 'Edit ' + editing.name : 'Add game' }}</h2>
    <form novalidate (submit)="save($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          @if (!editing) {
            <p class="text-sm leading-[1.4] text-muted">
              Staff can pick it when starting a session.
            </p>
          }
          <mat-form-field>
            <mat-label>Title</mat-label>
            <input
              matInput
              autocomplete="off"
              [attr.maxlength]="maxTitle"
              placeholder="e.g. Mortal Kombat 1"
              [value]="title()"
              (input)="title.set($any($event.target).value)"
            />
            @if (editing) {
              <mat-hint>Past bills show the game by its current title.</mat-hint>
            }
          </mat-form-field>
          <mat-form-field>
            <mat-label>Platforms</mat-label>
            <mat-select
              multiple
              placeholder="No platform"
              [value]="platforms()"
              (selectionChange)="platforms.set($event.value)"
            >
              @for (p of platformChoices(); track p) {
                <mat-option [value]="p">{{ p }}</mat-option>
              }
            </mat-select>
          </mat-form-field>
          <div class="grid grid-cols-2 gap-4">
            <mat-form-field>
              <mat-label>Play modes</mat-label>
              <mat-select
                multiple
                placeholder="Pick at least one"
                [value]="playModes()"
                (selectionChange)="setModes($event.value)"
              >
                @for (m of modes; track m.key) {
                  <mat-option [value]="m.key">{{ m.label }}</mat-option>
                }
              </mat-select>
            </mat-form-field>
            <mat-form-field>
              <mat-label>Players per station</mat-label>
              <mat-select
                [value]="maxPlayers()"
                [disabled]="!local()"
                (selectionChange)="maxPlayers.set($event.value)"
              >
                @for (n of playerCounts; track n) {
                  <mat-option [value]="n">{{ n }}</mat-option>
                }
              </mat-select>
              <mat-hint>{{
                local() ? 'Most controllers one station may use on it' : 'One: no local multiplayer'
              }}</mat-hint>
            </mat-form-field>
          </div>
          <div class="grid grid-cols-2 gap-4">
            <mat-form-field>
              <mat-label>Age rating</mat-label>
              <mat-select
                placeholder="Not set"
                [value]="age()"
                (selectionChange)="age.set($event.value)"
              >
                @if (editing) {
                  <mat-option [value]="null">Not set</mat-option>
                }
                @for (a of ages; track a) {
                  <mat-option [value]="a">{{ a }}+</mat-option>
                }
              </mat-select>
            </mat-form-field>
            <mat-form-field>
              <mat-label>Media</mat-label>
              <mat-select
                placeholder="Not set"
                [value]="mediaKey()"
                (selectionChange)="mediaKey.set($event.value)"
              >
                @if (editing) {
                  <mat-option [value]="null">Not set</mat-option>
                }
                @for (m of media; track m.key) {
                  <mat-option [value]="m.key">{{ m.label }}</mat-option>
                }
              </mat-select>
            </mat-form-field>
          </div>
          @if (!editing) {
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
          }
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" [disabled]="busy()">
          {{ editing ? 'Save' : 'Add' }}
        </button>
      </mat-dialog-actions>
    </form>
  `,
})
export class GameDialog {
  protected readonly data = inject<GameDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<GameDialog, GameDialogResult>>(MatDialogRef);
  private readonly floor = inject(FloorStore);

  protected readonly editing = this.data.game;
  protected readonly ages = AGE_RATINGS;
  protected readonly media = MEDIA;
  protected readonly modes = PLAY_MODES;
  protected readonly playerCounts = Array.from({ length: MAX_PLAYERS }, (_, i) => i + 1);
  protected readonly maxTitle = MAX_TITLE;

  protected readonly title = signal(this.editing?.name ?? '');
  /** The design's defaults for a new game: 3+, digital, single player. */
  protected readonly age = signal<AgeRating | null>(this.editing ? this.editing.ageRating : 3);
  protected readonly mediaKey = signal<GameMedia | null>(
    this.editing ? this.editing.media : 'digital',
  );
  protected readonly platforms = signal<readonly string[]>(
    this.editing
      ? this.editing.platforms
      : [this.data.platform ?? this.data.platforms[0]].filter((p): p is string => !!p),
  );
  protected readonly playModes = signal<readonly PlayMode[]>(this.editing?.playModes ?? ['single']);
  protected readonly maxPlayers = signal(this.editing?.maxLocalPlayers ?? 1);
  /** Only local multiplayer puts more than one controller on a station. */
  protected readonly local = computed(() => this.playModes().includes('local'));
  /** Station ids; none until the owner picks them. */
  protected readonly playableOn = signal<readonly string[]>([]);
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  /** The choices, plus any platform the game already has (kept unless unticked). */
  protected readonly platformChoices = computed(() =>
    [...new Set([...this.data.platforms, ...(this.editing?.platforms ?? [])])].sort(),
  );

  protected setModes(picked: readonly PlayMode[]): void {
    // Kept in the order they are stored and shown.
    this.playModes.set(PLAY_MODES.map((m) => m.key).filter((k) => picked.includes(k)));
    // Without local multiplayer a station takes one controller; with it at least two.
    if (!this.local()) this.maxPlayers.set(1);
    else if (this.maxPlayers() < 2) this.maxPlayers.set(2);
  }

  protected async save(event: Event): Promise<void> {
    event.preventDefault();
    if (this.busy()) return;
    const name = this.title().trim();
    if (name.length < 2) {
      this.error.set('Enter a title');
      return;
    }
    if (name.length > MAX_TITLE) {
      this.error.set(`Keep the title to ${MAX_TITLE} characters`);
      return;
    }
    if (!this.playModes().length) {
      this.error.set('Pick at least one play mode');
      return;
    }
    const id = this.editing?.id ?? crypto.randomUUID();
    if (
      this.floor.games().some((g) => g.id !== id && g.name.toLowerCase() === name.toLowerCase())
    ) {
      this.error.set(`${name} is already in the list`);
      return;
    }
    this.busy.set(true);
    this.error.set('');
    const stations = this.editing ? [] : this.playableOn();
    const game = {
      id,
      name,
      aliases: this.editing?.aliases ?? [],
      categoryId: this.editing?.categoryId ?? null,
      platforms: this.platforms(),
      playModes: this.playModes(),
      maxLocalPlayers: this.maxPlayers(),
      active: this.editing?.active ?? true,
      ageRating: this.age(),
      media: this.mediaKey(),
    };
    try {
      await this.floor.saveGame(game, stations, this.editing?.active);
      const on = stations.length;
      this.ref.close({
        id,
        snack: this.editing
          ? `${name} saved`
          : on
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
