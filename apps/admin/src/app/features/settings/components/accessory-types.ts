import { Component, computed, effect, inject, output, resource, signal } from '@angular/core';
import { MatButton, MatIconButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatMenu, MatMenuItem, MatMenuTrigger } from '@angular/material/menu';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { CatalogAccessory, VenueApi } from '../../../core/venue/venue';
import { ConfirmDialog, ConfirmDialogData } from '../../../shared/confirm/confirm-dialog';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { AccessoriesStore } from '../../accessories/data/accessories-store';
import { AccessoryKind, accessoryIcon } from '../../accessories/data/accessory.models';
import {
  AccessoryKindDialog,
  AccessoryKindDialogData,
  AccessoryKindDialogResult,
} from '../../accessories/dialogs/accessory-kind-dialog';

/**
 * Settings › Accessory types: the kinds of kit stations carry (Controller, VR headset, Steering
 * wheel, cue stick…), picked from the global catalog or the owner's own. Accessories themselves
 * are added on each station.
 */
@Component({
  selector: 'app-accessory-types',
  imports: [
    DetailPane,
    DetailSection,
    StatusPill,
    MatButton,
    MatIconButton,
    MatIcon,
    MatMenu,
    MatMenuItem,
    MatMenuTrigger,
  ],
  template: `
    <app-detail-pane
      crumb="Settings / Accessory types"
      icon="videogame_asset"
      heading="Accessory types"
      [subtitle]="arena.current().name"
      (closed)="closed.emit()"
    >
      <div actions class="flex gap-2">
        <button
          mat-stroked-button
          type="button"
          [disabled]="busy() || !arena.canEdit() || !offered().length"
          [matMenuTriggerFor]="catalogMenu"
        >
          <mat-icon aria-hidden="true">library_add</mat-icon>From catalog
        </button>
        <mat-menu #catalogMenu="matMenu">
          @for (c of offered(); track c.name) {
            <button mat-menu-item type="button" (click)="adopt(c)">
              <mat-icon aria-hidden="true">{{ icon(c.name) }}</mat-icon
              >{{ c.name }}
            </button>
          }
        </mat-menu>
        <button mat-flat-button type="button" [disabled]="!arena.canEdit()" (click)="add()">
          <mat-icon aria-hidden="true">add</mat-icon>Custom
        </button>
      </div>
      <app-detail-section
        heading="Types"
        subtitle="Add accessories of these types on each station (Stations › a station › Accessories)."
      >
        @if (store.loadError(); as e) {
          <p role="alert" class="text-[13px] leading-[1.45] text-danger">
            Accessory types couldn't load: {{ e }}
          </p>
        } @else if (!store.ready()) {
          <p class="text-[13px] leading-[1.45] text-muted">Loading…</p>
        } @else {
          <ul class="-mx-2 flex flex-col gap-0.5" aria-label="Accessory types">
            @for (k of store.kinds(); track k.id) {
              <li class="flex min-h-14 items-center gap-3 px-2">
                <span class="icon text-xl text-muted" aria-hidden="true">{{ icon(k.name) }}</span>
                <span class="flex min-w-0 flex-1 flex-col gap-0.75">
                  <span class="truncate text-sm leading-[1.2] font-medium">{{ k.name }}</span>
                  <span class="truncate text-xs leading-[1.2] text-muted">{{ line(k) }}</span>
                </span>
                @if (!k.active) {
                  <app-status-pill tone="info">Off</app-status-pill>
                }
                <button
                  mat-icon-button
                  type="button"
                  [disabled]="!arena.canEdit()"
                  [attr.aria-label]="'Edit ' + k.name"
                  (click)="edit(k)"
                >
                  <mat-icon aria-hidden="true">edit</mat-icon>
                </button>
                <button
                  mat-icon-button
                  type="button"
                  [disabled]="busy() || !arena.canEdit() || !k.active"
                  [attr.aria-label]="'Remove ' + k.name"
                  (click)="remove(k)"
                >
                  <mat-icon aria-hidden="true">delete</mat-icon>
                </button>
              </li>
            } @empty {
              <li class="px-2 text-[13px] leading-[1.45] text-muted">
                No accessory types yet. Pick one from the catalog (Controller, VR headset, Cue
                stick, Football…) or add your own.
              </li>
            }
          </ul>
        }
      </app-detail-section>
    </app-detail-pane>
  `,
})
export class AccessoryTypes {
  protected readonly arena = inject(ArenaContext);
  protected readonly store = inject(AccessoriesStore);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  readonly closed = output<void>();

  private readonly venueApi = inject(VenueApi);
  private readonly catalog = resource({ loader: () => this.venueApi.accessoryCatalog() });
  /** Catalog types the arena doesn't have yet (names are unique ignoring case). */
  protected readonly offered = computed(() => {
    const have = new Set(this.store.kinds().map((k) => k.name.trim().toLowerCase()));
    return this.catalog.hasValue()
      ? this.catalog.value().filter((c) => !have.has(c.name.toLowerCase()))
      : [];
  });

  protected readonly icon = accessoryIcon;
  protected readonly busy = signal(false);

  constructor() {
    effect(() => {
      if (this.arena.current().id) void this.store.load();
    });
  }

  protected line(k: AccessoryKind): string {
    const n = this.store.accessories().filter((a) => a.kindId === k.id).length;
    return [
      k.countsAsController ? 'Counts as a controller' : 'Tracked only',
      `${n} on stations`,
    ].join(' · ');
  }

  /** Adds a ready-made type from the global catalog. */
  protected async adopt(c: CatalogAccessory): Promise<void> {
    this.busy.set(true);
    try {
      await this.store.saveKind({
        id: crypto.randomUUID(),
        name: c.name,
        countsAsController: c.countsAsController,
        sortOrder: this.store.kinds().length,
        active: true,
      });
      this.say(`${c.name} added · add them on each station`);
    } catch (e) {
      this.say(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }

  protected add(): void {
    this.open({});
  }

  protected edit(k: AccessoryKind): void {
    this.open({ kind: k });
  }

  protected remove(k: AccessoryKind): void {
    this.dialog
      .open<ConfirmDialog, ConfirmDialogData, boolean>(ConfirmDialog, {
        data: {
          title: `Remove ${k.name}?`,
          message:
            'If no accessory is of this type it is deleted. Otherwise it is turned off: those accessories keep it, but new ones cannot use it.',
          confirm: 'Remove',
          danger: true,
        },
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe(async (yes) => {
        if (!yes) return;
        this.busy.set(true);
        try {
          const outcome = await this.store.removeKind(k.id);
          this.say(outcome === 'deleted' ? `${k.name} deleted` : `${k.name} turned off`);
        } catch (e) {
          this.say(toAppError(e).message);
        } finally {
          this.busy.set(false);
        }
      });
  }

  private open(data: AccessoryKindDialogData): void {
    this.dialog
      .open<AccessoryKindDialog, AccessoryKindDialogData, AccessoryKindDialogResult>(
        AccessoryKindDialog,
        { data, width: '520px', maxWidth: 'calc(100vw - 32px)' },
      )
      .afterClosed()
      .subscribe((snack) => {
        if (snack) this.say(snack);
      });
  }

  private say(message: string): void {
    this.snack.open(message, undefined, { duration: 3200 });
  }
}
