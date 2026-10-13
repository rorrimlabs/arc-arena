import { Component, computed, effect, inject, linkedSignal, output, signal } from '@angular/core';
import { MatChipListbox, MatChipListboxChange, MatChipOption } from '@angular/material/chips';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { UnsavedBar } from '../../../shared/list-detail/unsaved-bar';
import { formatMinutes } from '../../../shared/time/ist';
import { FloorOptionsStore, PRESET_CHOICES, WARN_CHOICES } from '../data/floor-options';

/**
 * Design: settings `sessions`. The floor options' start durations (what staff can pick when
 * starting a session or a booking) and the end-of-session warning, saved together from the
 * unsaved-changes bar; the floor app uses them after its next sync.
 */
@Component({
  selector: 'app-session-settings',
  imports: [DetailPane, DetailSection, UnsavedBar, MatChipListbox, MatChipOption],
  template: `
    <app-detail-pane
      crumb="Settings / Sessions"
      icon="timer"
      heading="Sessions"
      [subtitle]="arena.current().name"
      (closed)="closed.emit()"
    >
      <app-detail-section
        heading="Starting a session"
        subtitle="What staff can choose on the floor app."
      >
        @if (store.loadError(); as error) {
          <p role="alert" class="text-[13px] leading-[1.45] text-danger">
            Session options couldn't load: {{ error }}
          </p>
        } @else if (!presets()) {
          <p class="text-[13px] leading-[1.45] text-muted">Loading…</p>
        } @else {
          <div class="flex flex-col gap-2.5">
            <span class="text-[15px] leading-[1.3]" id="time-options">Time options</span>
            <mat-chip-listbox
              multiple
              aria-labelledby="time-options"
              [value]="presets()"
              [disabled]="busy()"
              (change)="pickPresets($event)"
            >
              @for (m of times(); track m) {
                <mat-chip-option [value]="m">{{ minutes(m) }}</mat-chip-option>
              }
            </mat-chip-listbox>
          </div>
          <div class="flex flex-col gap-2.5">
            <span class="text-[15px] leading-[1.3]" id="warn-before"
              >Warn staff before time ends</span
            >
            <mat-chip-listbox
              aria-labelledby="warn-before"
              [value]="warn()"
              [disabled]="busy()"
              (change)="pickWarn($event)"
            >
              @for (m of warns(); track m) {
                <mat-chip-option [value]="m" [selectable]="m !== warn()"
                  >{{ m }} min</mat-chip-option
                >
              }
            </mat-chip-listbox>
          </div>
        }
        @if (error()) {
          <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
        }
      </app-detail-section>

      @if (dirty()) {
        <app-unsaved-bar footer [busy]="busy()" (discard)="discard()" (save)="save()" />
      }
    </app-detail-pane>
  `,
})
export class SessionSettings {
  protected readonly arena = inject(ArenaContext);
  protected readonly store = inject(FloorOptionsStore);
  private readonly snack = inject(MatSnackBar);
  readonly closed = output<void>();

  protected readonly minutes = formatMinutes;
  protected readonly presets = linkedSignal(() => this.store.options()?.startPresets ?? null);
  protected readonly warn = linkedSignal(() => this.store.options()?.warnMinutes ?? null);
  /** The design's choices, plus any saved value outside them so it can be seen and removed. */
  protected readonly times = computed(() =>
    [...new Set([...PRESET_CHOICES, ...(this.store.options()?.startPresets ?? [])])].sort(
      (a, b) => a - b,
    ),
  );
  protected readonly warns = computed(() =>
    [...new Set([...WARN_CHOICES, this.store.options()?.warnMinutes ?? 5])].sort((a, b) => a - b),
  );
  protected readonly dirty = computed(() => {
    const saved = this.store.options();
    const presets = this.presets();
    if (!saved || !presets) return false;
    return presets.join() !== saved.startPresets.join() || this.warn() !== saved.warnMinutes;
  });
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  constructor() {
    effect(() => {
      if (this.arena.current().id) void this.store.load();
    });
  }

  protected pickPresets(event: MatChipListboxChange): void {
    const picked = ((event.value as number[]) ?? []).slice().sort((a, b) => a - b);
    if (!picked.length) {
      // Put the last one back: the floor needs at least one choice.
      event.source.value = this.presets();
      this.snack.open('Keep at least one time option', undefined, { duration: 3200 });
      return;
    }
    this.presets.set(picked);
  }

  protected pickWarn(event: MatChipListboxChange): void {
    if (event.value) this.warn.set(Number(event.value));
  }

  protected discard(): void {
    this.presets.set(this.store.options()?.startPresets ?? null);
    this.warn.set(this.store.options()?.warnMinutes ?? null);
    this.error.set('');
  }

  protected async save(): Promise<void> {
    const options = this.store.options();
    const presets = this.presets();
    const warn = this.warn();
    if (!options || !presets || warn == null) return;
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.save({ ...options, startPresets: presets, warnMinutes: warn });
      this.snack.open('Settings saved · the floor app updates on next refresh', undefined, {
        duration: 3200,
      });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
