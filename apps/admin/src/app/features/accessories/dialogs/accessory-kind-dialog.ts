import { Component, inject, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import {
  MAT_DIALOG_DATA,
  MatDialogActions,
  MatDialogContent,
  MatDialogRef,
  MatDialogTitle,
} from '@angular/material/dialog';
import { MatFormField, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatSlideToggle } from '@angular/material/slide-toggle';
import { toAppError } from '../../../core/auth/auth-api';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import { AccessoriesStore } from '../data/accessories-store';
import { AccessoryKind } from '../data/accessory.models';

export interface AccessoryKindDialogData {
  /** Absent: add a kind. */
  readonly kind?: AccessoryKind;
}

/** Closes with the snackbar text; undefined when cancelled. */
export type AccessoryKindDialogResult = string;

/** Adds or edits an accessory kind (accessory_kind.upsert): its name and whether it is a pad. */
@Component({
  selector: 'app-accessory-kind-dialog',
  providers: [MATERIAL_DEFAULTS],
  imports: [
    MatDialogTitle,
    MatDialogContent,
    MatDialogActions,
    MatFormField,
    MatLabel,
    MatInput,
    MatSlideToggle,
    MatButton,
  ],
  template: `
    <h2 mat-dialog-title>{{ data.kind ? 'Edit accessory type' : 'Add accessory type' }}</h2>
    <form novalidate (submit)="save($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <mat-form-field>
            <mat-label>Name</mat-label>
            <input
              matInput
              autocomplete="off"
              maxlength="40"
              placeholder="e.g. Controller, VR headset, Steering wheel"
              [value]="name()"
              (input)="name.set($any($event.target).value)"
            />
          </mat-form-field>
          <div class="flex items-center justify-between gap-4">
            <span class="flex flex-col gap-1">
              <span class="text-[15px] leading-[1.3]" id="kind-pad">Counts as a controller</span>
              <span class="text-[13px] leading-[1.3] text-muted"
                >Handed to players, and sets the controller-count price</span
              >
            </span>
            <mat-slide-toggle
              hideIcon
              aria-labelledby="kind-pad"
              [checked]="pad()"
              (change)="pad.set($event.checked)"
            />
          </div>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" [disabled]="busy()">
          {{ data.kind ? 'Save' : 'Add type' }}
        </button>
      </mat-dialog-actions>
    </form>
  `,
})
export class AccessoryKindDialog {
  protected readonly data = inject<AccessoryKindDialogData>(MAT_DIALOG_DATA);
  protected readonly ref =
    inject<MatDialogRef<AccessoryKindDialog, AccessoryKindDialogResult>>(MatDialogRef);
  private readonly store = inject(AccessoriesStore);

  protected readonly name = signal(this.data.kind?.name ?? '');
  protected readonly pad = signal(this.data.kind?.countsAsController ?? false);
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected async save(event: Event): Promise<void> {
    event.preventDefault();
    const name = this.name().trim();
    if (!name || name.length > 40) {
      this.error.set('Enter a name of up to 40 characters');
      return;
    }
    const taken = this.store
      .kinds()
      .some((k) => k.id !== this.data.kind?.id && k.name.toLowerCase() === name.toLowerCase());
    if (taken) {
      this.error.set(`${name} already exists`);
      return;
    }
    const k = this.data.kind;
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.saveKind({
        id: k?.id ?? crypto.randomUUID(),
        name,
        countsAsController: this.pad(),
        sortOrder: k?.sortOrder ?? this.store.kinds().length,
        active: k?.active ?? true,
      });
      this.ref.close(k ? `${name} saved` : `${name} added`);
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
