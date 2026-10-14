import { Component, computed, effect, inject, input, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { FloorStore } from '../../../core/floor/floor-store';
import { Station } from '../../../core/floor/floor.models';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { AccessoriesStore } from '../data/accessories-store';
import { Accessory, accessoryIcon, kindName, statusInfo } from '../data/accessory.models';
import {
  AccessoryDialog,
  AccessoryDialogData,
  AccessoryDialogResult,
} from '../dialogs/accessory-dialog';

/**
 * A station's accessories (pads, VR headsets, wheels…): those that belong here, where each one is
 * now, and those borrowed from other stations. Staff lend them on the floor app; here the owner
 * adds and edits them, sends a borrowed one back, or keeps it here for good.
 */
@Component({
  selector: 'app-station-accessories',
  imports: [DetailSection, StatusPill, MatButton, MatIcon],
  template: `
    <app-detail-section heading="Accessories" [subtitle]="subtitle()">
      @if (store.loadError(); as e) {
        <p role="alert" class="text-[13px] leading-[1.45] text-danger">
          Accessories couldn't load: {{ e }}
        </p>
      } @else if (!store.ready()) {
        <p class="text-[13px] leading-[1.45] text-muted">Loading…</p>
      } @else {
        <ul class="-mx-2 flex flex-col gap-0.5" aria-label="Belongs to this station">
          @for (a of own(); track a.id) {
            <li>
              <button
                type="button"
                class="flex min-h-12 w-full items-center gap-3 rounded-chip px-2 text-left hover:bg-info-soft"
                [disabled]="!canEdit()"
                (click)="edit(a)"
              >
                <span class="icon text-xl text-muted" aria-hidden="true">{{ icon(a) }}</span>
                <span class="flex min-w-0 flex-1 flex-col gap-0.75">
                  <span class="truncate text-sm leading-[1.2] font-medium">{{ a.label }}</span>
                  <span class="truncate text-xs leading-[1.2] text-muted">{{ line(a) }}</span>
                </span>
                <app-status-pill [tone]="tone(a)">{{ label(a) }}</app-status-pill>
              </button>
            </li>
          } @empty {
            <li class="px-2 text-[13px] leading-[1.45] text-muted">
              Nothing belongs here yet. Add each controller, headset or wheel with its name.
            </li>
          }
        </ul>
        @if (borrowed().length) {
          <h3 class="pt-2 text-xs leading-none font-semibold text-subtle">Borrowed here now</h3>
          <ul class="-mx-2 flex flex-col gap-0.5" aria-label="Borrowed here now">
            @for (a of borrowed(); track a.id) {
              <li class="flex min-h-12 items-center gap-3 px-2">
                <span class="icon text-xl text-muted" aria-hidden="true">{{ icon(a) }}</span>
                <span class="flex min-w-0 flex-1 flex-col gap-0.75">
                  <span class="truncate text-sm leading-[1.2] font-medium">{{ a.label }}</span>
                  <span class="truncate text-xs leading-[1.2] text-muted"
                    >{{ kind(a) }} · belongs to {{ stationName(a.homeId) }}</span
                  >
                </span>
                <span class="arena-compact flex gap-1">
                  <button
                    mat-button
                    type="button"
                    [disabled]="busy() || !canEdit()"
                    (click)="sendBack(a)"
                  >
                    Send back
                  </button>
                  <button
                    mat-button
                    type="button"
                    [disabled]="busy() || !canEdit()"
                    (click)="keep(a)"
                  >
                    Keep here
                  </button>
                </span>
              </li>
            }
          </ul>
        }
        <div>
          <button
            mat-stroked-button
            type="button"
            [disabled]="!canEdit() || station().status === 'disabled'"
            (click)="add()"
          >
            <mat-icon aria-hidden="true">add</mat-icon>Accessory
          </button>
        </div>
      }
    </app-detail-section>
  `,
})
export class StationAccessories {
  protected readonly canEdit = inject(ArenaContext).canEdit;
  private readonly arena = inject(ArenaContext);
  protected readonly store = inject(AccessoriesStore);
  private readonly floor = inject(FloorStore);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  readonly station = input.required<Station>();

  /** Belongs here (retired ones last). */
  protected readonly own = computed(() =>
    this.store
      .accessories()
      .filter((a) => a.homeId === this.station().id)
      .sort((a, b) => Number(a.status === 'retired') - Number(b.status === 'retired')),
  );
  protected readonly borrowed = computed(() =>
    this.store
      .accessories()
      .filter((a) => a.currentId === this.station().id && a.homeId !== this.station().id),
  );
  protected readonly subtitle = computed(() => {
    const own = this.own().filter((a) => a.status !== 'retired');
    if (!own.length) return 'Controllers, headsets, wheels… named and tracked here.';
    const usable = own.filter((a) => a.status === 'usable' && a.currentId === this.station().id);
    return `${usable.length} of ${own.length} here and usable`;
  });
  protected readonly busy = signal(false);

  constructor() {
    effect(() => {
      if (this.arena.current().id) void this.store.load();
    });
  }

  protected icon(a: Accessory): string {
    return accessoryIcon(this.kind(a));
  }

  protected kind(a: Accessory): string {
    return kindName(a, this.store.kindById());
  }

  /** "Controller · here", "VR headset · lent to VOID", or the status note. */
  protected line(a: Accessory): string {
    const where =
      a.currentId === a.homeId ? 'here' : `lent to ${this.stationName(a.currentId)}`;
    return [this.kind(a), a.notes || where].join(' · ');
  }

  protected label(a: Accessory): string {
    return statusInfo(a.status).label;
  }

  protected tone(a: Accessory) {
    return statusInfo(a.status).tone;
  }

  protected stationName(id: string): string {
    return this.floor.stationById().get(id)?.name ?? 'another station';
  }

  protected add(): void {
    this.open({ stationId: this.station().id });
  }

  protected edit(a: Accessory): void {
    this.open({ stationId: this.station().id, accessory: a });
  }

  protected async sendBack(a: Accessory): Promise<void> {
    await this.run(
      () => this.store.move(a.id, 'returnHome'),
      `${a.label} sent back to ${this.stationName(a.homeId)}`,
    );
  }

  protected async keep(a: Accessory): Promise<void> {
    const s = this.station();
    await this.run(() => this.store.move(a.id, 'permanent', s.id), `${a.label} now belongs to ${s.name}`);
  }

  private open(data: AccessoryDialogData): void {
    this.dialog
      .open<AccessoryDialog, AccessoryDialogData, AccessoryDialogResult>(AccessoryDialog, {
        data,
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((snack) => {
        if (snack) this.say(snack);
      });
  }

  private async run(change: () => Promise<void>, done: string): Promise<void> {
    this.busy.set(true);
    try {
      await change();
      this.say(done);
    } catch (e) {
      this.say(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }

  private say(message: string): void {
    this.snack.open(message, undefined, { duration: 3200 });
  }
}
