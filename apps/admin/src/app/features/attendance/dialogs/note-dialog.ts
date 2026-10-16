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
import { toAppError } from '../../../core/auth/auth-api';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import { CORRECTION_MESSAGES } from '../data/attendance.models';

export interface NoteDialogData {
  readonly title: string;
  readonly message: string;
  /** The confirm button, e.g. "Void entry". */
  readonly confirm: string;
  /** The field's label: "Reason" (required) or "Note (optional)". */
  readonly label: string;
  readonly required: boolean;
  readonly danger?: boolean;
  /** Runs the write with the typed text; resolves with the snackbar text. Refusals stay here. */
  readonly run: (text: string) => Promise<string>;
}

/**
 * A yes/no question with a text: Void (a reason is required) or Accept (an optional note).
 * The write runs from the dialog so a refusal is shown in it; closes with the snackbar text.
 */
@Component({
  selector: 'app-note-dialog',
  providers: [MATERIAL_DEFAULTS],
  imports: [
    MatDialogTitle,
    MatDialogContent,
    MatDialogActions,
    MatFormField,
    MatLabel,
    MatHint,
    MatInput,
    MatButton,
  ],
  template: `
    <h2 mat-dialog-title>{{ data.title }}</h2>
    <form novalidate (submit)="save($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <p class="text-sm leading-[1.4] text-muted">{{ data.message }}</p>
          <mat-form-field>
            <mat-label>{{ data.label }}</mat-label>
            <textarea
              matInput
              rows="2"
              maxlength="500"
              [value]="text()"
              (input)="text.set($any($event.target).value); error.set('')"
            ></textarea>
            @if (data.required) {
              <mat-hint>Kept with the entry's history</mat-hint>
            }
          </mat-form-field>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button
          mat-flat-button
          type="submit"
          [class.danger-fill]="data.danger"
          [disabled]="busy()"
        >
          {{ data.confirm }}
        </button>
      </mat-dialog-actions>
    </form>
  `,
})
export class NoteDialog {
  protected readonly data = inject<NoteDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<NoteDialog, string>>(MatDialogRef);

  protected readonly text = signal('');
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected async save(event: Event): Promise<void> {
    event.preventDefault();
    const text = this.text().trim();
    if (this.data.required && !text) {
      this.error.set(CORRECTION_MESSAGES['reason_required']);
      return;
    }
    this.busy.set(true);
    this.error.set('');
    try {
      this.ref.close(await this.data.run(text));
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
