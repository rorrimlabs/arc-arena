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
import { ControllersStore } from '../data/controllers-store';
import { MAX_LABEL, labelTaken, nextLabel } from '../data/controller.models';

export interface ControllerDialogData {
  /** The station to add it to, if one is picked already. */
  readonly stationId?: string;
}

/** Closes with the new pad's id and the snackbar text; undefined when cancelled. */
export interface ControllerDialogResult {
  readonly id: string;
  readonly snack: string;
}

/**
 * Adds a pad to a station (controller.upsert): it belongs to and stands at that station, usable.
 * A blank label becomes the next free "<station>-<n>"; labels never repeat.
 */
@Component({
  selector: 'app-controller-dialog',
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
    <h2 mat-dialog-title>Add controller</h2>
    <form novalidate (submit)="save($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <p class="text-sm leading-[1.4] text-muted">
            Use the label written on the pad, so staff can find it. Staff see it on the floor app
            straight away.
          </p>
          <mat-form-field>
            <mat-label>Station</mat-label>
            <mat-select [formField]="f.stationId">
              @for (s of stations(); track s.id) {
                <mat-option [value]="s.id">{{ s.name }}</mat-option>
              }
            </mat-select>
            <mat-hint>Where it belongs and is now</mat-hint>
          </mat-form-field>
          <mat-form-field>
            <mat-label>Label</mat-label>
            <input matInput autocomplete="off" [placeholder]="auto()" [formField]="f.label" />
          </mat-form-field>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" [disabled]="busy() || !model().stationId">Add</button>
      </mat-dialog-actions>
    </form>
  `,
})
export class ControllerDialog {
  private readonly data = inject<ControllerDialogData>(MAT_DIALOG_DATA);
  protected readonly ref =
    inject<MatDialogRef<ControllerDialog, ControllerDialogResult>>(MatDialogRef);
  private readonly floor = inject(FloorStore);
  private readonly store = inject(ControllersStore);

  /** Stations on the floor (removed ones take no new pads). */
  protected readonly stations = computed(() =>
    this.floor.stations().filter((s) => s.status !== 'disabled'),
  );
  protected readonly model = signal({
    stationId:
      this.stations().find((s) => s.id === this.data.stationId)?.id ?? this.stations()[0]?.id ?? '',
    label: '',
  });
  private readonly station = computed(() =>
    this.stations().find((s) => s.id === this.model().stationId),
  );
  /** The label a blank field becomes. */
  protected readonly auto = computed(() => {
    const s = this.station();
    return s ? nextLabel(s.name, s.id, this.store.controllers()) : '';
  });
  protected readonly f = form(this.model, (p) => {
    validate(p.stationId, ({ value }) =>
      this.stations().some((s) => s.id === value())
        ? null
        : { kind: 'station', message: 'Pick a station' },
    );
    maxLength(p.label, MAX_LABEL, { message: `Use up to ${MAX_LABEL} characters` });
    validate(p.label, ({ value }) => {
      const label = value().trim() || this.auto();
      return labelTaken(label, this.store.controllers())
        ? { kind: 'taken', message: `A controller is already labelled ${label}` }
        : null;
    });
  });
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected async save(event: Event): Promise<void> {
    event.preventDefault();
    const first = this.f().errorSummary()[0];
    if (first) {
      this.error.set(first.message ?? 'Check the form');
      return;
    }
    const station = this.station();
    if (!station) return;
    const label = this.model().label.trim() || this.auto();
    this.busy.set(true);
    this.error.set('');
    try {
      const id = await this.store.add(label, station.id);
      this.ref.close({ id, snack: `${label} added to ${station.name}` });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
