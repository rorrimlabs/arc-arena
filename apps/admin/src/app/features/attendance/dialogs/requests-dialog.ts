import { Component, inject, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import {
  MatDialogActions,
  MatDialogContent,
  MatDialogRef,
  MatDialogTitle,
} from '@angular/material/dialog';
import { MatFormField, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { toAppError } from '../../../core/auth/auth-api';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import { formatDate, formatTime } from '../../../shared/time/ist';
import { AttendanceRequestRow, AttendanceRequestsStore } from '../data/attendance-requests';

/**
 * Missed-time requests from staff (Review attendance): each shows the times asked for and why.
 * Approve adds the stretch or fixes the clock-out as a correction (history kept, audited); Reject
 * keeps the request with the optional note, which the staff member sees.
 */
@Component({
  selector: 'app-requests-dialog',
  providers: [MATERIAL_DEFAULTS],
  imports: [
    MatDialogTitle,
    MatDialogContent,
    MatDialogActions,
    MatFormField,
    MatLabel,
    MatInput,
    MatButton,
  ],
  template: `
    <h2 mat-dialog-title>Missed time requests</h2>
    <mat-dialog-content>
      @if (store.pending().length === 0) {
        <p class="py-4 text-sm text-muted">No requests waiting.</p>
      }
      <ul class="flex flex-col gap-4 pt-1" aria-label="Requests">
        @for (r of store.pending(); track r.id) {
          <li class="flex flex-col gap-2 rounded-lg border border-border p-3">
            <p class="text-sm leading-[1.4] font-medium">{{ r.staffName || 'Staff' }}</p>
            <p class="text-sm leading-[1.4]">
              {{ r.kind === 'add' ? 'Missed clock-in and out' : 'Fix a clock-out' }} ·
              {{ when(r) }}
            </p>
            <p class="text-sm leading-[1.4] text-muted">“{{ r.reason }}”</p>
            <mat-form-field>
              <mat-label>Note (optional)</mat-label>
              <input
                matInput
                autocomplete="off"
                maxlength="500"
                [value]="notes()[r.id] ?? ''"
                (input)="setNote(r.id, $any($event.target).value)"
              />
            </mat-form-field>
            @if (errors()[r.id]; as error) {
              <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error }}</p>
            }
            <div class="flex justify-end gap-2">
              <button
                mat-button
                type="button"
                [disabled]="busy() === r.id"
                (click)="decide(r, false)"
              >
                Reject
              </button>
              <button
                mat-flat-button
                type="button"
                [disabled]="busy() === r.id"
                (click)="decide(r, true)"
              >
                Approve
              </button>
            </div>
          </li>
        }
      </ul>
    </mat-dialog-content>
    <mat-dialog-actions align="end">
      <button mat-button type="button" (click)="ref.close()">Close</button>
    </mat-dialog-actions>
  `,
})
export class RequestsDialog {
  protected readonly ref = inject<MatDialogRef<RequestsDialog, boolean>>(MatDialogRef);
  protected readonly store = inject(AttendanceRequestsStore);

  protected readonly notes = signal<Readonly<Record<string, string>>>({});
  protected readonly errors = signal<Readonly<Record<string, string>>>({});
  protected readonly busy = signal<string | null>(null);

  protected when(r: AttendanceRequestRow): string {
    return `${formatDate(r.inAt)}, ${formatTime(r.inAt)} → ${formatTime(r.outAt)}`;
  }

  protected setNote(id: string, text: string): void {
    this.notes.update((n) => ({ ...n, [id]: text }));
  }

  protected async decide(r: AttendanceRequestRow, approve: boolean): Promise<void> {
    this.busy.set(r.id);
    this.errors.update((e) => ({ ...e, [r.id]: '' }));
    try {
      await this.store.decide(r.id, approve, this.notes()[r.id] ?? '');
    } catch (e) {
      this.errors.update((x) => ({ ...x, [r.id]: toAppError(e).message }));
    } finally {
      this.busy.set(null);
    }
  }
}
