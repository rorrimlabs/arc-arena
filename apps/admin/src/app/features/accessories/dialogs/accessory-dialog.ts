import { Component, computed, inject, signal } from '@angular/core';
import { FormField, form, maxLength, validate } from '@angular/forms/signals';
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
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import { formatDate, formatTime } from '../../../shared/time/ist';
import { AccessoriesStore } from '../data/accessories-store';
import {
  ACCESSORY_STATUSES,
  Accessory,
  AccessoryChange,
  AccessoryMove,
  AccessoryStatus,
  MAX_LABEL,
  labelTaken,
  nextLabel,
  statusInfo,
} from '../data/accessory.models';

export interface AccessoryDialogData {
  /** The station the accessory is added to (or that the screen shows). */
  readonly stationId: string;
  /** Absent: add one. Present: edit it. */
  readonly accessory?: Accessory;
}

/** Closes with the snackbar text; undefined when cancelled. */
export type AccessoryDialogResult = string;

/** '' is "no kind": a game pad from before kinds existed. */
const NO_KIND = '';

/**
 * Adds an accessory to a station, or edits one: its name, kind, home station and condition
 * (controller.upsert / controller.set_status). Editing also shows its latest moves, read only when
 * the dialog opens.
 */
@Component({
  selector: 'app-accessory-dialog',
  providers: [MATERIAL_DEFAULTS],
  imports: [
    FormField,
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
    <h2 mat-dialog-title>{{ editing ? 'Edit ' + data.accessory?.label : 'Add accessory' }}</h2>
    <form novalidate (submit)="save($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          @if (!editing) {
            <p class="text-sm leading-[1.4] text-muted">
              Give it the name written on it, so staff can find it. It belongs to
              {{ stationName(data.stationId) }} and staff see it on the floor app straight away.
            </p>
          }
          <mat-form-field>
            <mat-label>Name</mat-label>
            <input matInput autocomplete="off" [placeholder]="auto()" [formField]="f.label" />
          </mat-form-field>
          <mat-form-field>
            <mat-label>Kind</mat-label>
            <mat-select [formField]="f.kindId">
              @for (k of kindOptions(); track k.id) {
                <mat-option [value]="k.id">{{ k.name }}</mat-option>
              }
            </mat-select>
            <mat-hint>{{ kindHint() }}</mat-hint>
          </mat-form-field>
          @if (editing) {
            <mat-form-field>
              <mat-label>Home station</mat-label>
              <mat-select [formField]="f.homeId">
                @for (s of homeOptions(); track s.id) {
                  <mat-option [value]="s.id">{{ s.name }}</mat-option>
                }
              </mat-select>
              <mat-hint>Where it belongs and goes back to after a loan</mat-hint>
            </mat-form-field>
            <mat-form-field>
              <mat-label>Status</mat-label>
              <mat-select [formField]="f.status">
                @for (s of statuses; track s.value) {
                  <mat-option [value]="s.value">{{ s.label }}</mat-option>
                }
              </mat-select>
              <mat-hint>{{ statusSub() }}</mat-hint>
            </mat-form-field>
            <mat-form-field>
              <mat-label>Note</mat-label>
              <input
                matInput
                autocomplete="off"
                placeholder="e.g. Left stick drift"
                [formField]="f.notes"
              />
            </mat-form-field>
            <section aria-labelledby="acc-moves" class="flex flex-col gap-2">
              <h3 id="acc-moves" class="text-sm leading-none font-semibold">Recent moves</h3>
              @if (movesError()) {
                <p role="alert" class="text-[13px] text-danger">{{ movesError() }}</p>
              } @else if (moves() === null) {
                <p class="text-[13px] text-muted">Loading…</p>
              } @else {
                <ul class="flex flex-col gap-1.5">
                  @for (m of moves(); track m.id) {
                    <li class="flex justify-between gap-3 text-[13px] leading-[1.3]">
                      <span>{{ moveLabel(m) }}</span>
                      <span class="text-muted tabular-nums">{{ when(m.at) }}</span>
                    </li>
                  } @empty {
                    <li class="text-[13px] text-muted">It has never left its station.</li>
                  }
                </ul>
              }
            </section>
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
export class AccessoryDialog {
  protected readonly data = inject<AccessoryDialogData>(MAT_DIALOG_DATA);
  protected readonly ref =
    inject<MatDialogRef<AccessoryDialog, AccessoryDialogResult>>(MatDialogRef);
  private readonly floor = inject(FloorStore);
  private readonly store = inject(AccessoriesStore);

  protected readonly editing = !!this.data.accessory;
  protected readonly statuses = ACCESSORY_STATUSES;

  /** Active kinds, the accessory's own kind if retired, and "Game pad" when no kind is a pad. */
  protected readonly kindOptions = computed(() => {
    const own = this.data.accessory?.kindId ?? null;
    const kinds = this.store.kinds().filter((k) => k.active || k.id === own);
    const options = kinds.map((k) => ({ id: k.id, name: k.name }));
    if (!own && (this.editing || !kinds.some((k) => k.countsAsController))) {
      options.unshift({ id: NO_KIND, name: 'Game pad' });
    }
    return options;
  });
  /** Stations on the floor, plus the accessory's home if that station was removed. */
  protected readonly homeOptions = computed(() =>
    this.floor
      .stations()
      .filter((s) => s.status !== 'disabled' || s.id === this.data.accessory?.homeId),
  );

  protected readonly model = signal({
    label: this.data.accessory?.label ?? '',
    kindId:
      this.data.accessory?.kindId ??
      (this.editing
        ? NO_KIND
        : (this.store.kinds().find((k) => k.active && k.countsAsController)?.id ?? NO_KIND)),
    homeId: this.data.accessory?.homeId ?? this.data.stationId,
    status: (this.data.accessory?.status ?? 'usable') as AccessoryStatus,
    notes: this.data.accessory?.notes ?? '',
  });
  /** The name a blank field becomes (a new accessory only). */
  protected readonly auto = computed(() =>
    this.editing
      ? ''
      : nextLabel(this.stationName(this.data.stationId), this.data.stationId, this.store.accessories()),
  );
  protected readonly f = form(this.model, (p) => {
    maxLength(p.label, MAX_LABEL, { message: `Use up to ${MAX_LABEL} characters` });
    validate(p.label, ({ value }) => {
      const label = value().trim() || this.auto();
      if (!label) return { kind: 'label', message: 'Give it a name' };
      return labelTaken(label, this.store.accessories(), this.data.accessory?.id)
        ? { kind: 'taken', message: `Another accessory is already called ${label}` }
        : null;
    });
  });
  protected readonly kindHint = computed(() => {
    const id = this.model().kindId;
    const k = id ? this.store.kindById().get(id) : null;
    return !id || k?.countsAsController
      ? 'A controller: handed to players and sets the controller-count price'
      : 'Tracked at its station; does not change the price';
  });
  protected readonly statusSub = computed(() => statusInfo(this.model().status).sub);

  protected readonly moves = signal<readonly AccessoryMove[] | null>(null);
  protected readonly movesError = signal('');
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  constructor() {
    const a = this.data.accessory;
    if (a) {
      this.store.moves(a.id, 10).then(
        (m) => this.moves.set(m),
        (e) => this.movesError.set(toAppError(e).message),
      );
    }
  }

  protected stationName(id: string): string {
    return this.floor.stationById().get(id)?.name ?? 'Unknown station';
  }

  protected moveLabel(m: AccessoryMove): string {
    if (m.kind === 'returnHome') return `Back to ${this.stationName(m.toId)}`;
    if (m.kind === 'permanent') return `Moved to ${this.stationName(m.toId)} for good`;
    return `Lent to ${this.stationName(m.toId)}`;
  }

  protected when(at: string): string {
    return `${formatDate(at)}, ${formatTime(at)}`;
  }

  protected async save(event: Event): Promise<void> {
    event.preventDefault();
    const first = this.f().errorSummary()[0];
    if (first) {
      this.error.set(first.message ?? 'Check the form');
      return;
    }
    const m = this.model();
    const label = m.label.trim() || this.auto();
    const kindId = m.kindId || null;
    this.busy.set(true);
    this.error.set('');
    try {
      const a = this.data.accessory;
      if (!a) {
        await this.store.add(label, kindId, this.data.stationId);
        this.ref.close(`${label} added to ${this.stationName(this.data.stationId)}`);
        return;
      }
      const notes = m.notes.trim() || null;
      const change: AccessoryChange = {
        ...(label !== a.label ? { label } : {}),
        ...(kindId !== a.kindId ? { kindId } : {}),
        ...(m.homeId !== a.homeId ? { homeId: m.homeId } : {}),
        ...(m.status !== a.status ? { status: m.status } : {}),
        ...(notes !== a.notes ? { notes } : {}),
      };
      if (!Object.keys(change).length) {
        this.ref.close();
        return;
      }
      if (change.label !== undefined || change.kindId !== undefined || change.homeId !== undefined) {
        await this.store.edit(a.id, change);
      } else {
        await this.store.setStatus(a.id, m.status, notes);
      }
      this.ref.close(`${label} saved`);
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
