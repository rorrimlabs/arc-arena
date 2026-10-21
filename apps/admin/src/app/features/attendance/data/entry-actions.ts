import { Service, inject } from '@angular/core';
import { MatDialog } from '@angular/material/dialog';
import { MatSnackBar } from '@angular/material/snack-bar';
import { firstValueFrom } from 'rxjs';
import { CorrectDialog, CorrectDialogData, CorrectDialogResult } from '../dialogs/correct-dialog';
import { NoteDialog, NoteDialogData } from '../dialogs/note-dialog';
import { AttendanceStore } from './attendance-store';
import { LogRow } from './attendance.models';

/**
 * A reviewer's actions on one entry, shared by the day panel and the entry detail: accept a
 * pending entry (attendance.review, optional note), correct its times (attendance.correct
 * `edit`: the old row is kept as superseded) or void it (attendance.correct `void`, reason
 * required). The server checks the permission, the own-record rule and finalised periods.
 */
@Service()
export class EntryActions {
  private readonly store = inject(AttendanceStore);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  accept(r: LogRow): Promise<boolean> {
    return this.ask({
      title: `Accept ${r.staffName}'s entry?`,
      message: 'It stays as recorded and no longer needs review.',
      confirm: 'Accept',
      label: 'Note (optional)',
      required: false,
      run: async (note) => {
        await this.store.review(r.entry.id, note);
        return 'Entry accepted';
      },
    });
  }

  voidEntry(r: LogRow): Promise<boolean> {
    return this.ask({
      title: `Void ${r.staffName}'s entry?`,
      message:
        'It stops counting towards worked hours and pay. It is kept, marked voided, with your reason.',
      confirm: 'Void entry',
      label: 'Reason',
      required: true,
      danger: true,
      run: async (reason) => {
        await this.store.correct({ action: 'void', entry_id: r.entry.id, reason });
        return 'Entry voided';
      },
    });
  }

  /** Resolves with the corrected entry's new id, or null when cancelled. */
  async correct(r: LogRow): Promise<string | null> {
    const result = await firstValueFrom(
      this.dialog
        .open<CorrectDialog, CorrectDialogData, CorrectDialogResult>(CorrectDialog, {
          data: { entry: r.entry, staffName: r.staffName },
          width: '560px',
          maxWidth: 'calc(100vw - 32px)',
        })
        .afterClosed(),
    );
    if (!result) return null;
    this.say(result.snack);
    return result.id || null;
  }

  private async ask(data: NoteDialogData): Promise<boolean> {
    const snack = await firstValueFrom(
      this.dialog
        .open<NoteDialog, NoteDialogData, string>(NoteDialog, {
          data,
          width: '520px',
          maxWidth: 'calc(100vw - 32px)',
        })
        .afterClosed(),
    );
    if (snack) this.say(snack);
    return !!snack;
  }

  private say(message: string): void {
    this.snack.open(message, undefined, { duration: 3200 });
  }
}
