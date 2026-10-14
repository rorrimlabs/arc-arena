import { Component, inject } from '@angular/core';
import { MatButton } from '@angular/material/button';
import {
  MAT_DIALOG_DATA,
  MatDialogActions,
  MatDialogClose,
  MatDialogContent,
  MatDialogTitle,
} from '@angular/material/dialog';

export interface ConfirmDialogData {
  readonly title: string;
  readonly message: string;
  /**
   * The confirm button's label, e.g. "Remove". Without one the dialog only informs: a single
   * Close button (closes with false).
   */
  readonly confirm?: string;
  /** Destructive: the confirm button is filled in danger. */
  readonly danger?: boolean;
}

/** The design's dialog frame for a yes/no question. Closes with true when confirmed. */
@Component({
  selector: 'app-confirm-dialog',
  imports: [MatDialogTitle, MatDialogContent, MatDialogActions, MatDialogClose, MatButton],
  template: `
    <h2 mat-dialog-title>{{ data.title }}</h2>
    <mat-dialog-content>
      <p class="pt-1 text-sm leading-[1.4] text-muted">{{ data.message }}</p>
    </mat-dialog-content>
    <mat-dialog-actions align="end">
      <button mat-button type="button" [mat-dialog-close]="false">
        {{ data.confirm ? 'Cancel' : 'Close' }}
      </button>
      @if (data.confirm) {
        <button
          mat-flat-button
          type="button"
          [class.danger-fill]="data.danger"
          [mat-dialog-close]="true"
        >
          {{ data.confirm }}
        </button>
      }
    </mat-dialog-actions>
  `,
})
export class ConfirmDialog {
  protected readonly data = inject<ConfirmDialogData>(MAT_DIALOG_DATA);
}
