import { Component, computed, effect, inject, input, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatFormField, MatHint, MatLabel } from '@angular/material/form-field';
import { MatIcon } from '@angular/material/icon';
import { MatInput } from '@angular/material/input';
import { MatProgressBar } from '@angular/material/progress-bar';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { FloorStore } from '../../../core/floor/floor-store';
import { Game, GameControl, GameControlInput } from '../../../core/floor/floor.models';
import { DetailSection } from '../../../shared/list-detail/detail-section';

const COMMON_BUTTONS = [
  'CROSS',
  'CIRCLE',
  'SQUARE',
  'TRIANGLE',
  'L1',
  'R1',
  'L2',
  'R2',
  'DPAD_UP',
  'DPAD_DOWN',
  'DPAD_LEFT',
  'DPAD_RIGHT',
  'LEFT_STICK',
  'RIGHT_STICK',
  'OPTIONS',
] as const;

const BUTTON_LABELS: Record<string, string> = {
  CROSS: '✕ Cross',
  CIRCLE: '○ Circle',
  SQUARE: '▢ Square',
  TRIANGLE: '△ Triangle',
  L1: 'L1',
  R1: 'R1',
  L2: 'L2',
  R2: 'R2',
  DPAD_UP: '↑ Up',
  DPAD_DOWN: '↓ Down',
  DPAD_LEFT: '← Left',
  DPAD_RIGHT: '→ Right',
  LEFT_STICK: 'L Stick',
  RIGHT_STICK: 'R Stick',
  OPTIONS: 'Options',
};

/**
 * Control guide for staff to read out to players (game_controls, op_game_replace_controls).
 * Actions are grouped by section (e.g. Attacking, Defending) with button tokens and explanations.
 */
@Component({
  selector: 'app-game-controls',
  imports: [DetailSection, MatButton, MatIcon, MatFormField, MatLabel, MatHint, MatInput, MatProgressBar],
  template: `
    <app-detail-section
      heading="Game controls"
      subtitle="Buttons staff read out to players during a session."
    >
      @if (loading()) {
        <mat-progress-bar mode="indeterminate" aria-label="Loading controls" />
      }

      @if (error()) {
        <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
      }

      @for (sec of sections(); track sec.name) {
        <div class="flex flex-col gap-2">
          <h4 class="text-xs font-semibold tracking-wide text-muted uppercase">{{ sec.name }}</h4>
          <div class="flex flex-col gap-2">
            @for (c of sec.items; track c.id) {
              <div
                class="flex items-start justify-between gap-3 rounded-lg border border-border bg-surface-raised p-2.5"
              >
                <div class="flex min-w-0 flex-1 flex-col gap-1">
                  <div class="flex flex-wrap items-center gap-2">
                    <span class="text-sm font-medium">{{ c.action }}</span>
                    <div class="flex flex-wrap gap-1">
                      @for (btn of c.buttons; track btn) {
                        <span
                          class="inline-flex items-center rounded bg-surface px-1.5 py-0.5 text-xs font-mono font-semibold text-text shadow-xs border border-border"
                        >
                          {{ buttonLabel(btn) }}
                        </span>
                      }
                    </div>
                  </div>
                  @if (c.explanation) {
                    <span class="text-xs text-muted">{{ c.explanation }}</span>
                  }
                </div>
                @if (canEdit()) {
                  <button
                    mat-icon-button
                    type="button"
                    class="text-muted hover:text-danger -mr-1 -mt-1 h-8 w-8"
                    [disabled]="saving()"
                    aria-label="Remove control"
                    (click)="remove(c.id)"
                  >
                    <mat-icon class="text-base leading-none">delete_outline</mat-icon>
                  </button>
                }
              </div>
            }
          </div>
        </div>
      } @empty {
        @if (!loading() && !showForm()) {
          <p class="text-[13px] leading-[1.45] text-muted">
            No controls configured yet. Add common actions like shoot, pass, sprint, or combos.
          </p>
        }
      }

      @if (showForm()) {
        <div class="flex flex-col gap-3 rounded-lg border border-border bg-surface-raised p-3">
          <span class="text-sm font-semibold">Add control</span>
          <mat-form-field class="arena-dense" subscriptSizing="dynamic">
            <mat-label>Section</mat-label>
            <input
              matInput
              autocomplete="off"
              placeholder="e.g. Attacking, Defending"
              [value]="formSection()"
              (input)="formSection.set($any($event.target).value)"
            />
          </mat-form-field>
          @if (knownSections().length) {
            <div class="flex flex-wrap gap-1">
              @for (s of knownSections(); track s) {
                <button
                  type="button"
                  class="rounded-full border border-border px-2 py-0.5 text-xs text-muted hover:bg-surface"
                  (click)="formSection.set(s)"
                >
                  {{ s }}
                </button>
              }
            </div>
          }
          <mat-form-field class="arena-dense" subscriptSizing="dynamic">
            <mat-label>Action</mat-label>
            <input
              matInput
              autocomplete="off"
              placeholder="e.g. Shoot, Short Pass"
              [value]="formAction()"
              (input)="formAction.set($any($event.target).value)"
            />
          </mat-form-field>
          <div class="flex flex-col gap-1">
            <span class="text-xs font-medium text-muted">Buttons</span>
            <div class="flex flex-wrap gap-1">
              @for (btn of commonButtons; track btn) {
                <button
                  type="button"
                  class="rounded border px-2 py-1 text-xs font-mono font-medium transition-colors"
                  [class.bg-primary]="hasButton(btn)"
                  [class.text-white]="hasButton(btn)"
                  [class.border-primary]="hasButton(btn)"
                  [class.border-border]="!hasButton(btn)"
                  [class.bg-surface]="!hasButton(btn)"
                  (click)="toggleButton(btn)"
                >
                  {{ buttonLabel(btn) }}
                </button>
              }
            </div>
            @if (formButtons().length) {
              <span class="text-xs text-muted font-mono">
                Order: {{ formButtons().join(' → ') }}
              </span>
            }
          </div>
          <mat-form-field class="arena-dense" subscriptSizing="dynamic">
            <mat-label>Explanation (optional)</mat-label>
            <input
              matInput
              autocomplete="off"
              placeholder="e.g. Hold for power shot"
              [value]="formExplanation()"
              (input)="formExplanation.set($any($event.target).value)"
            />
          </mat-form-field>
          <div class="flex justify-end gap-2 pt-1">
            <button mat-button type="button" [disabled]="saving()" (click)="cancelForm()">
              Cancel
            </button>
            <button
              mat-flat-button
              type="button"
              [disabled]="saving() || !canSubmitForm()"
              (click)="saveNewControl()"
            >
              {{ saving() ? 'Saving…' : 'Add' }}
            </button>
          </div>
        </div>
      } @else if (canEdit()) {
        <div>
          <button
            mat-stroked-button
            type="button"
            class="arena-dense"
            [disabled]="loading() || saving()"
            (click)="showForm.set(true)"
          >
            <mat-icon aria-hidden="true">add</mat-icon>Add control
          </button>
        </div>
      }
    </app-detail-section>
  `,
})
export class GameControls {
  private readonly floor = inject(FloorStore);
  private readonly snack = inject(MatSnackBar);
  protected readonly canEdit = inject(ArenaContext).canEdit;

  readonly game = input.required<Game>();

  protected readonly controls = signal<GameControl[]>([]);
  protected readonly loading = signal(false);
  protected readonly saving = signal(false);
  protected readonly error = signal('');

  protected readonly showForm = signal(false);
  protected readonly formSection = signal('');
  protected readonly formAction = signal('');
  protected readonly formButtons = signal<string[]>([]);
  protected readonly formExplanation = signal('');

  protected readonly commonButtons = COMMON_BUTTONS;

  protected readonly knownSections = computed(() => [
    ...new Set(this.controls().map((c) => c.section).filter(Boolean)),
  ]);

  protected readonly sections = computed(() => {
    const list = this.controls();
    const map = new Map<string, GameControl[]>();
    for (const c of list) {
      const arr = map.get(c.section) ?? [];
      arr.push(c);
      map.set(c.section, arr);
    }
    return Array.from(map.entries()).map(([name, items]) => ({ name, items }));
  });

  constructor() {
    effect(() => {
      const g = this.game();
      if (g?.id) {
        void this.load(g.id);
      }
    });
  }

  async load(gameId: string): Promise<void> {
    this.loading.set(true);
    this.error.set('');
    try {
      const res = await this.floor.gameControls(gameId);
      this.controls.set(res);
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.loading.set(false);
    }
  }

  protected buttonLabel(token: string): string {
    return BUTTON_LABELS[token] ?? token.replace(/_/g, ' ');
  }

  protected hasButton(token: string): boolean {
    return this.formButtons().includes(token);
  }

  protected toggleButton(token: string): void {
    const cur = this.formButtons();
    if (cur.includes(token)) {
      this.formButtons.set(cur.filter((b) => b !== token));
    } else {
      this.formButtons.set([...cur, token]);
    }
  }

  protected canSubmitForm(): boolean {
    return (
      this.formSection().trim().length > 0 &&
      this.formAction().trim().length > 0 &&
      this.formButtons().length > 0
    );
  }

  protected cancelForm(): void {
    this.showForm.set(false);
    this.formSection.set('');
    this.formAction.set('');
    this.formButtons.set([]);
    this.formExplanation.set('');
  }

  protected async saveNewControl(): Promise<void> {
    if (!this.canSubmitForm()) return;
    const gameId = this.game().id;
    const newControl: GameControlInput = {
      id: crypto.randomUUID(),
      section: this.formSection().trim(),
      action: this.formAction().trim(),
      buttons: this.formButtons(),
      explanation: this.formExplanation().trim() || null,
      sortOrder: this.controls().length,
    };
    const nextList: GameControlInput[] = [...this.controls(), newControl];
    this.saving.set(true);
    this.error.set('');
    try {
      await this.floor.saveGameControls(gameId, nextList);
      this.snack.open('Control added', undefined, { duration: 2500 });
      this.cancelForm();
      await this.load(gameId);
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.saving.set(false);
    }
  }

  protected async remove(controlId: string): Promise<void> {
    const gameId = this.game().id;
    const nextList: GameControlInput[] = this.controls().filter((c) => c.id !== controlId);
    this.saving.set(true);
    this.error.set('');
    try {
      await this.floor.saveGameControls(gameId, nextList);
      this.snack.open('Control removed', undefined, { duration: 2500 });
      await this.load(gameId);
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.saving.set(false);
    }
  }
}
