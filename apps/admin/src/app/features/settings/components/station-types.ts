import { Component, computed, inject, output, resource, signal } from '@angular/core';
import { MatButton, MatIconButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatMenu, MatMenuItem, MatMenuTrigger } from '@angular/material/menu';
import { MatSlideToggle, MatSlideToggleChange } from '@angular/material/slide-toggle';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { CatalogType, VenueApi, VenueStore } from '../../../core/venue/venue';
import { ConfirmDialog, ConfirmDialogData } from '../../../shared/confirm/confirm-dialog';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { PricingStore } from '../../pricing/data/pricing-store';
import { StationType, billingLabel, typeIcon } from '../../pricing/data/pricing.models';
import { TypeDialog, TypeDialogData, TypeDialogResult } from '../dialogs/type-dialog';

/**
 * Settings › Station types: what staff can start on the floor (Game Station, VR, Pool Table…),
 * each with how it is billed and what it uses. Nothing is built in: the owner adds the arena's
 * own. Prices are set per type in Pricing.
 */
@Component({
  selector: 'app-station-types',
  imports: [
    DetailPane,
    DetailSection,
    MatButton,
    MatIconButton,
    MatIcon,
    MatMenu,
    MatMenuItem,
    MatMenuTrigger,
    MatSlideToggle,
  ],
  template: `
    <app-detail-pane
      crumb="Settings / Station types"
      icon="category"
      heading="Station types"
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
          @for (c of offered(); track c.code) {
            <button mat-menu-item type="button" (click)="adopt(c)">{{ c.name }}</button>
          }
        </mat-menu>
        <button mat-flat-button type="button" [disabled]="!arena.canEdit()" (click)="add()">
          <mat-icon aria-hidden="true">add</mat-icon>Custom
        </button>
      </div>
      <app-detail-section
        heading="Types"
        subtitle="Each station offers one or more of these. Turned-off types stay on past bills."
      >
        @if (store.loadError(); as e) {
          <p role="alert" class="text-[13px] leading-[1.45] text-danger">
            Station types couldn't load: {{ e }}
          </p>
        } @else if (!store.data()) {
          <p class="text-[13px] leading-[1.45] text-muted">Loading…</p>
        } @else {
          <ul class="-mx-2 flex flex-col gap-0.5" aria-label="Station types">
            @for (t of store.types(); track t.id) {
              <li class="flex min-h-14 items-center gap-3 rounded-chip px-2">
                <span class="icon text-xl text-muted" aria-hidden="true">{{ icon(t) }}</span>
                <span class="flex min-w-0 flex-1 flex-col gap-0.75">
                  <span class="truncate text-sm leading-[1.2] font-medium">{{ t.name }}</span>
                  <span class="truncate text-xs leading-[1.2] text-muted">{{ line(t) }}</span>
                </span>
                <mat-slide-toggle
                  hideIcon
                  [checked]="t.active"
                  [disabled]="busy() || !arena.canEdit()"
                  [attr.aria-label]="t.name + ' on'"
                  (change)="setActive(t, $event)"
                />
                <button
                  mat-icon-button
                  type="button"
                  [disabled]="!arena.canEdit()"
                  [attr.aria-label]="'Edit ' + t.name"
                  (click)="edit(t)"
                >
                  <mat-icon aria-hidden="true">edit</mat-icon>
                </button>
                <button
                  mat-icon-button
                  type="button"
                  [disabled]="busy() || !arena.canEdit()"
                  [attr.aria-label]="'Remove ' + t.name"
                  (click)="remove(t)"
                >
                  <mat-icon aria-hidden="true">delete</mat-icon>
                </button>
              </li>
            } @empty {
              <li class="px-2 text-[13px] leading-[1.45] text-muted">
                No station types yet. Pick one from the catalog (PlayStation, Pool table, Football
                turf…) or add your own.
              </li>
            }
          </ul>
        }
      </app-detail-section>
    </app-detail-pane>
  `,
})
export class StationTypes {
  protected readonly arena = inject(ArenaContext);
  protected readonly store = inject(PricingStore);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  readonly closed = output<void>();

  private readonly venueApi = inject(VenueApi);
  private readonly venue = inject(VenueStore);
  private readonly catalog = resource({ loader: () => this.venueApi.catalog() });
  /** Catalog types the venue doesn't have yet (a code is never added twice). */
  protected readonly offered = computed(() => {
    const have = new Set(this.store.types().map((t) => t.code));
    return this.catalog.hasValue() ? this.catalog.value().filter((c) => !have.has(c.code)) : [];
  });

  protected readonly icon = typeIcon;
  protected readonly busy = signal(false);

  /** "By the minute, hourly rate · controllers · games · 3 stations". */
  protected line(t: StationType): string {
    return [
      t.code,
      billingLabel(t.durationModel),
      t.usesControllers ? 'controllers' : null,
      t.usesGames ? 'games' : null,
      `${t.stations} station${t.stations === 1 ? '' : 's'}`,
    ]
      .filter(Boolean)
      .join(' · ');
  }

  /** Adds a ready-made type from the global catalog; the owner prices it in Pricing. */
  protected async adopt(c: CatalogType): Promise<void> {
    this.busy.set(true);
    try {
      await this.store.saveType({
        id: crypto.randomUUID(),
        code: c.code,
        name: c.name,
        usesControllers: c.usesControllers,
        usesGames: c.usesGames,
        durationModel: c.durationModel,
        sortOrder: this.store.types().length,
        active: true,
      });
      await this.venue.load(true);
      this.say(`${c.name} added · set its price in Pricing`);
    } catch (e) {
      this.say(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }

  protected add(): void {
    this.open({});
  }

  protected edit(t: StationType): void {
    this.open({ type: t });
  }

  protected async setActive(t: StationType, event: MatSlideToggleChange): Promise<void> {
    if (!event.checked && t.stations > 0) {
      event.source.checked = true;
      this.say(
        `Remove ${t.name} from its ${t.stations} station${t.stations === 1 ? '' : 's'} first`,
      );
      return;
    }
    this.busy.set(true);
    try {
      await this.store.saveType({ ...t, active: event.checked });
      this.say(event.checked ? `${t.name} turned on` : `${t.name} turned off`);
    } catch (e) {
      event.source.checked = !event.checked;
      this.say(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }

  /**
   * activity.remove: a type no session, booking or pad ever used is deleted with its prices; one
   * with history is turned off and kept for past bills. Refused while stations offer it.
   */
  protected remove(t: StationType): void {
    const data: ConfirmDialogData = t.stations
      ? {
          title: `${t.name} can't be removed yet`,
          message: `${t.stations} station${t.stations === 1 ? ' offers' : 's offer'} it. Change those stations' type (or remove them) first.`,
        }
      : {
          title: `Remove ${t.name}?`,
          message:
            'If no session or booking ever used it, it is deleted with its prices. Otherwise it is turned off: staff can no longer pick it, and past bills keep it.',
          confirm: 'Remove',
          danger: true,
        };
    this.dialog
      .open<ConfirmDialog, ConfirmDialogData, boolean>(ConfirmDialog, {
        data,
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe(async (yes) => {
        if (!yes) return;
        this.busy.set(true);
        try {
          const outcome = await this.store.removeType(t.id);
          this.say(
            outcome === 'deleted'
              ? `${t.name} deleted`
              : `${t.name} turned off · past bills keep it`,
          );
        } catch (e) {
          this.say(toAppError(e).message);
        } finally {
          this.busy.set(false);
        }
      });
  }

  private open(data: TypeDialogData): void {
    this.dialog
      .open<TypeDialog, TypeDialogData, TypeDialogResult>(TypeDialog, {
        data,
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((result) => {
        if (result) this.say(result.snack);
      });
  }

  private say(message: string): void {
    this.snack.open(message, undefined, { duration: 3200 });
  }
}
