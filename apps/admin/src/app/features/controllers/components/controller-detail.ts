import { Component, computed, inject, input, linkedSignal, output, signal } from '@angular/core';
import { FormField, form, maxLength, validate } from '@angular/forms/signals';
import { MatFormField, MatHint, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatOption, MatSelect } from '@angular/material/select';
import { MatSnackBar } from '@angular/material/snack-bar';
import { toAppError } from '../../../core/auth/auth-api';
import { FloorStore } from '../../../core/floor/floor-store';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailRow } from '../../../shared/list-detail/detail-row';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { UnsavedBar } from '../../../shared/list-detail/unsaved-bar';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { ControllersStore } from '../data/controllers-store';
import {
  CONTROLLER_STATUSES,
  Controller,
  ControllerChange,
  ControllerStatus,
  MAX_LABEL,
  labelTaken,
  statusInfo,
} from '../data/controller.models';

interface Draft {
  label: string;
  homeId: string;
  status: ControllerStatus;
  notes: string;
}

const draftOf = (c: Controller): Draft => ({
  label: c.label,
  homeId: c.homeId,
  status: c.status,
  notes: c.notes ?? '',
});

/**
 * One pad: its label and home station, its condition (status and why), and where it is now. Edits
 * collect in a draft with the unsaved-changes bar. A status or note change alone is a
 * controller.set_status; a new label or home is a controller.upsert built on a fresh read, so the
 * pad's location and loan (the floor's to change) are kept as the server has them.
 */
@Component({
  selector: 'app-controller-detail',
  imports: [
    DetailPane,
    DetailSection,
    DetailRow,
    StatusPill,
    UnsavedBar,
    FormField,
    MatFormField,
    MatLabel,
    MatHint,
    MatInput,
    MatSelect,
    MatOption,
  ],
  template: `
    @let c = controller();
    <app-detail-pane
      [crumb]="'Controllers / ' + c.label"
      icon="videogame_asset"
      [heading]="c.label"
      [subtitle]="where()"
      (closed)="closed.emit()"
    >
      <app-status-pill chip [tone]="info().tone">{{ info().label }}</app-status-pill>

      <app-detail-section heading="Controller">
        <mat-form-field>
          <mat-label>Label</mat-label>
          <input matInput autocomplete="off" [formField]="f.label" />
          <mat-hint>What is written on the pad</mat-hint>
        </mat-form-field>
        <mat-form-field>
          <mat-label>Home station</mat-label>
          <mat-select [formField]="f.homeId">
            @for (s of homeOptions(); track s.id) {
              <mat-option [value]="s.id">{{ s.name }}</mat-option>
            }
          </mat-select>
          <mat-hint>Where it belongs and goes back to after a loan</mat-hint>
        </mat-form-field>
      </app-detail-section>

      <app-detail-section
        heading="Condition"
        subtitle="Only usable controllers can be given to players or lent to another station."
      >
        <mat-form-field>
          <mat-label>Status</mat-label>
          <mat-select [formField]="f.status">
            @for (s of statuses; track s.value) {
              <mat-option [value]="s.value">{{ s.label }}</mat-option>
            }
          </mat-select>
          <mat-hint>{{ draftInfo().sub }}</mat-hint>
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
        @if (error()) {
          <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
        }
      </app-detail-section>

      <app-detail-section heading="Where it is">
        <app-detail-row label="Now at" [value]="stationName(c.currentId)" />
        <app-detail-row label="Home" [value]="stationName(c.homeId)" />
        @if (c.loanReturnTo) {
          <app-detail-row
            label="On loan"
            [value]="'Goes back to ' + stationName(c.loanReturnTo) + ' when the session ends'"
          />
        }
        <p class="text-[13px] leading-[1.45] text-muted">
          Staff move and lend controllers between stations on the floor app.
        </p>
      </app-detail-section>

      @if (dirty()) {
        <app-unsaved-bar footer [busy]="busy()" (discard)="discard()" (save)="save()" />
      }
    </app-detail-pane>
  `,
})
export class ControllerDetail {
  private readonly store = inject(ControllersStore);
  private readonly floor = inject(FloorStore);
  private readonly snack = inject(MatSnackBar);

  readonly controller = input.required<Controller>();
  readonly closed = output<void>();

  protected readonly statuses = CONTROLLER_STATUSES;
  protected readonly info = computed(() => statusInfo(this.controller().status));
  protected readonly where = computed(() => {
    const c = this.controller();
    const at = `At ${this.stationName(c.currentId)}`;
    return c.currentId === c.homeId ? at : `${at} · belongs to ${this.stationName(c.homeId)}`;
  });
  /** Stations on the floor, plus the pad's home if that station was removed. */
  protected readonly homeOptions = computed(() =>
    this.floor
      .stations()
      .filter((s) => s.status !== 'disabled' || s.id === this.controller().homeId),
  );

  /** Only a change to this pad resets the draft (a reload of the list for another pad does not). */
  private readonly saved = computed(() => draftOf(this.controller()), {
    equal: (a, b) =>
      a.label === b.label && a.homeId === b.homeId && a.status === b.status && a.notes === b.notes,
  });
  protected readonly draft = linkedSignal<Draft>(() => this.saved());
  protected readonly f = form(this.draft, (p) => {
    maxLength(p.label, MAX_LABEL, { message: `Use up to ${MAX_LABEL} characters` });
    validate(p.label, ({ value }) => {
      const label = value().trim();
      if (!label) return { kind: 'label', message: 'A controller needs a label' };
      return labelTaken(label, this.store.controllers(), this.controller().id)
        ? { kind: 'taken', message: `A controller is already labelled ${label}` }
        : null;
    });
    validate(p.homeId, ({ value }) =>
      this.homeOptions().some((s) => s.id === value())
        ? null
        : { kind: 'home', message: 'Pick a home station' },
    );
  });
  protected readonly draftInfo = computed(() => statusInfo(this.draft().status));
  /** What the draft changes, field by field (empty when nothing). */
  private readonly change = computed<ControllerChange>(() => {
    const d = this.draft();
    const s = this.saved();
    const notes = d.notes.trim();
    return {
      ...(d.label.trim() !== s.label ? { label: d.label.trim() } : {}),
      ...(d.homeId !== s.homeId ? { homeId: d.homeId } : {}),
      ...(d.status !== s.status ? { status: d.status } : {}),
      ...(notes !== s.notes ? { notes: notes || null } : {}),
    };
  });
  protected readonly dirty = computed(() => Object.keys(this.change()).length > 0);
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  protected stationName(id: string): string {
    return this.floor.stationById().get(id)?.name ?? 'Unknown station';
  }

  protected discard(): void {
    this.draft.set(this.saved());
    this.error.set('');
  }

  protected async save(): Promise<void> {
    const first = this.f().errorSummary()[0];
    if (first) {
      this.error.set(first.message ?? 'Check the values');
      return;
    }
    const c = this.controller();
    const change = this.change();
    const d = this.draft();
    this.busy.set(true);
    this.error.set('');
    try {
      if (change.label !== undefined || change.homeId !== undefined) {
        await this.store.edit(c.id, change);
      } else {
        await this.store.setStatus(c.id, d.status, d.notes.trim() || null);
      }
      this.snack.open(`${change.label ?? c.label} saved`, undefined, { duration: 3200 });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
