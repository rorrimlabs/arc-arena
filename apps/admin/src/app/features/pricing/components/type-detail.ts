import { Component, computed, inject, input, linkedSignal, output, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatFormField, MatHint, MatLabel, MatSuffix } from '@angular/material/form-field';
import { MatIcon } from '@angular/material/icon';
import { MatInput } from '@angular/material/input';
import { MatSlideToggle, MatSlideToggleChange } from '@angular/material/slide-toggle';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { ConfirmDialog, ConfirmDialogData } from '../../../shared/confirm/confirm-dialog';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailRow } from '../../../shared/list-detail/detail-row';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { UnsavedBar } from '../../../shared/list-detail/unsaved-bar';
import { formatRupees } from '../../../shared/money/rupees.pipe';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { PricingStore } from '../data/pricing-store';
import {
  Band,
  RateChange,
  StationType,
  maxPlayers,
  ratesFor,
  summarizeWindows,
  findRate,
  rateRows,
  typeIcon,
  unitMinutesOf,
} from '../data/pricing.models';
import { TypeDialog, TypeDialogData, TypeDialogResult } from '../dialogs/type-dialog';

const MAX_RUPEES = 100_000;

type Draft = Readonly<Record<string, string>>;

const cell = (band: Band, controllers: number | null) => `${band}:${controllers ?? 'any'}`;

/**
 * Design: `if (p === 'pricing')` station-type detail, on the engine's model: a rate per
 * controller count (or one for any group), standard and happy hour, in whole rupees per hour or
 * per block. Edits collect in a draft with the design's unsaved-changes bar; Save sends only the
 * prices that changed (a cleared price is removed).
 */
@Component({
  selector: 'app-type-detail',
  imports: [
    DetailPane,
    DetailSection,
    DetailRow,
    StatusPill,
    UnsavedBar,
    MatButton,
    MatIcon,
    MatFormField,
    MatHint,
    MatLabel,
    MatSuffix,
    MatInput,
    MatSlideToggle,
  ],
  template: `
    @let t = type();
    <app-detail-pane
      [crumb]="'Pricing / ' + t.name"
      [icon]="icon()"
      [heading]="t.name"
      [subtitle]="t.stations + (t.stations === 1 ? ' station' : ' stations')"
      (closed)="closed.emit()"
    >
      <div actions class="arena-compact flex gap-2">
        <button mat-stroked-button type="button" [disabled]="!canEdit()" (click)="edit()">
          <mat-icon aria-hidden="true">edit</mat-icon>Edit
        </button>
        <button
          mat-button
          type="button"
          class="danger-action"
          [disabled]="busy() || !canEdit()"
          (click)="remove()"
        >
          <mat-icon aria-hidden="true">delete</mat-icon>Remove
        </button>
      </div>
      <app-status-pill chip [tone]="t.active ? 'primary' : 'info'">{{
        t.active ? 'Enabled' : 'Off'
      }}</app-status-pill>

      <app-detail-section heading="Base rate" [subtitle]="priceHelp()">
        @if (t.durationModel === 'unit') {
          <mat-form-field class="max-w-56">
            <mat-label>Block length</mat-label>
            <input
              matInput
              type="number"
              inputmode="numeric"
              min="5"
              max="240"
              [value]="unitDraft()"
              (input)="unitDraft.set($any($event.target).value)"
            />
            <span matTextSuffix>min</span>
          </mat-form-field>
        }
        <div
          class="grid items-center gap-x-3 gap-y-2"
          [class.grid-cols-[minmax(0,1fr)_minmax(0,9rem)_minmax(0,9rem)]]="t.happyEligible"
          [class.grid-cols-[minmax(0,1fr)_minmax(0,9rem)]]="!t.happyEligible"
          role="group"
          aria-label="Prices"
        >
          <span></span>
          <span class="text-[12.5px] font-medium text-muted">Standard</span>
          @if (t.happyEligible) {
            <span class="text-[12.5px] font-medium text-muted">Happy hour</span>
          }
          @for (row of rows(); track row) {
            <span class="text-sm">{{ rowLabel(row) }}</span>
            @for (band of bands(); track band) {
              <mat-form-field class="arena-dense">
                <span matTextPrefix>₹&nbsp;</span>
                <input
                  matInput
                  type="number"
                  inputmode="numeric"
                  min="0"
                  [attr.aria-label]="
                    (band === 'happy' ? 'Happy hour, ' : 'Standard, ') + rowLabel(row)
                  "
                  [value]="draft()[key(band, row)] ?? ''"
                  (input)="setCell(band, row, $any($event.target).value)"
                />
              </mat-form-field>
            }
          }
        </div>
        <mat-form-field class="max-w-56">
          <mat-label>Max players</mat-label>
          <input matInput readonly [value]="players()" aria-describedby="max-players-hint" />
          <mat-hint id="max-players-hint">{{
            t.usesControllers ? 'Set by the controller rows above' : 'Any number can play'
          }}</mat-hint>
        </mat-form-field>
        @if (!hasStandard()) {
          <p class="text-[13px] leading-[1.45] text-warning">
            No standard price yet: staff can't bill {{ t.name }} until it has one.
          </p>
        }
        @if (error()) {
          <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
        }
        <div class="flex items-center justify-between gap-4">
          <span class="flex flex-col gap-1">
            <span class="text-[15px] leading-[1.3]" id="type-enabled">Enabled</span>
            <span class="text-[13px] leading-[1.3] text-muted"
              >Turn off to hide this type everywhere</span
            >
          </span>
          <mat-slide-toggle
            hideIcon
            aria-labelledby="type-enabled"
            [checked]="t.active"
            [disabled]="busy() || !canEdit()"
            (change)="setActive($event)"
          />
        </div>
      </app-detail-section>

      <app-detail-section
        heading="With rules applied"
        subtitle="What staff are charged in each pricing window, from the saved prices."
      >
        @if (applied(); as a) {
          <app-detail-row label="Base" [value]="a.base" />
          @if (a.happy) {
            <app-detail-row [label]="'Happy hour · ' + a.happy.when" [value]="a.happy.value" />
          } @else {
            <p class="text-[13px] leading-[1.45] text-muted">No active rules cover this type.</p>
          }
        } @else {
          <p class="text-[13px] leading-[1.45] text-muted">No standard price yet.</p>
        }
      </app-detail-section>

      @if (dirty()) {
        <app-unsaved-bar footer [busy]="busy()" (discard)="discard()" (save)="save()" />
      }
    </app-detail-pane>
  `,
})
export class TypeDetail {
  /** Without the Settings permission the server refuses every change here. */
  protected readonly canEdit = inject(ArenaContext).canEdit;
  private readonly store = inject(PricingStore);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  readonly type = input.required<StationType>();
  readonly closed = output<void>();

  protected readonly icon = computed(() => typeIcon(this.type()));
  protected readonly players = computed(() => {
    const n = maxPlayers(this.type(), this.store.rates());
    return n ? String(n) : 'Any';
  });
  /**
   * The design's "With rules applied": the headline standard price, and the happy-hour price for
   * the same controller count when this type takes happy hour and a window is set.
   */
  protected readonly applied = computed(() => {
    const t = this.type();
    const rates = this.store.rates();
    const standard = ratesFor(t, rates).filter((r) => r.band === 'standard');
    if (!standard.length) return null;
    const cheapest = standard.reduce((x, y) => (y.pricePaise < x.pricePaise ? y : x));
    const per = cheapest.unitMinutes === 60 ? 'per hour' : `per ${cheapest.unitMinutes} min`;
    const base = `${formatRupees(cheapest.pricePaise)} ${per}`;
    const when = summarizeWindows(this.store.hours()?.happy ?? {});
    if (!t.happyEligible || !when) return { base, happy: null };
    const happy = findRate(rates, t.code, 'happy', cheapest.controllerCount);
    return {
      base,
      happy: { when, value: happy ? `${formatRupees(happy.pricePaise)} ${per}` : 'Standard price' },
    };
  });
  protected readonly rows = computed(() => rateRows(this.type()));
  protected readonly bands = computed<Band[]>(() =>
    this.type().happyEligible ? ['standard', 'happy'] : ['standard'],
  );
  protected readonly priceHelp = computed(() => {
    const t = this.type();
    const happy = t.happyEligible ? ' Leave Happy hour blank to charge the standard price.' : '';
    if (t.usesControllers) {
      return `Per station, by how many controllers are in use. Leave a row blank if a station never takes that many.${happy}`;
    }
    return `Per station, however many play.${happy}`;
  });

  /** The saved prices as the draft starts them (whole rupees). */
  private readonly saved = computed<Draft>(() => {
    const t = this.type();
    const out: Record<string, string> = {};
    for (const band of ['standard', 'happy'] as Band[]) {
      for (const row of rateRows(t)) {
        const r = findRate(this.store.rates(), t.code, band, row);
        if (r) out[cell(band, row)] = String(r.pricePaise / 100);
      }
    }
    return out;
  });
  private readonly savedUnit = computed(() =>
    String(unitMinutesOf(this.type(), this.store.rates())),
  );
  protected readonly draft = linkedSignal<Draft>(() => this.saved());
  protected readonly unitDraft = linkedSignal(() => this.savedUnit());
  protected readonly dirty = computed(() => {
    const a = this.draft();
    const b = this.saved();
    const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
    for (const k of keys) if ((a[k] ?? '').trim() !== (b[k] ?? '').trim()) return true;
    return this.unitDraft().trim() !== this.savedUnit();
  });
  protected readonly hasStandard = computed(() =>
    rateRows(this.type()).some((row) => (this.saved()[cell('standard', row)] ?? '') !== ''),
  );
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected key = cell;

  protected rowLabel(row: number | null): string {
    if (row == null) return 'Any number of players';
    return row === 1 ? '1 controller' : `${row} controllers`;
  }

  protected setCell(band: Band, row: number | null, value: string): void {
    this.draft.update((d) => ({ ...d, [cell(band, row)]: value }));
  }

  protected discard(): void {
    this.draft.set(this.saved());
    this.unitDraft.set(this.savedUnit());
    this.error.set('');
  }

  protected async save(): Promise<void> {
    const t = this.type();
    const unit = t.durationModel === 'unit' ? Number(this.unitDraft()) : 60;
    if (!Number.isInteger(unit) || unit < 5 || unit > 240) {
      this.error.set('Block length must be 5 to 240 minutes');
      return;
    }
    const unitChanged = String(unit) !== this.savedUnit();
    const changes: RateChange[] = [];
    for (const band of this.bands()) {
      for (const row of this.rows()) {
        const k = cell(band, row);
        const now = (this.draft()[k] ?? '').trim();
        const before = (this.saved()[k] ?? '').trim();
        if (now === before && !(unitChanged && now !== '')) continue;
        if (now === '') {
          changes.push({
            activityCode: t.code,
            band,
            controllerCount: row,
            unitMinutes: unit,
            pricePaise: null,
          });
          continue;
        }
        const rupees = Number(now);
        if (!Number.isInteger(rupees) || rupees < 0 || rupees > MAX_RUPEES) {
          this.error.set(`Prices are whole rupees from 0 to ${MAX_RUPEES.toLocaleString('en-IN')}`);
          return;
        }
        changes.push({
          activityCode: t.code,
          band,
          controllerCount: row,
          unitMinutes: unit,
          pricePaise: rupees * 100,
        });
      }
    }
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.saveRates(changes);
      this.say(`${t.name} prices saved · new sessions use them`);
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }

  protected async setActive(event: MatSlideToggleChange): Promise<void> {
    const t = this.type();
    if (!event.checked && t.stations > 0) {
      event.source.checked = true;
      this.say(`Remove its ${t.stations} station${t.stations === 1 ? '' : 's'} first`);
      return;
    }
    this.busy.set(true);
    try {
      await this.store.saveType({ ...t, active: event.checked });
      this.say(event.checked ? `${t.name} enabled` : `${t.name} turned off`);
    } catch (e) {
      event.source.checked = !event.checked;
      this.say(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }

  protected edit(): void {
    this.dialog
      .open<TypeDialog, TypeDialogData, TypeDialogResult>(TypeDialog, {
        data: { type: this.type() },
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((result) => {
        if (result) this.say(result.snack);
      });
  }

  /**
   * activity.remove: a type no session, booking or pad ever used is deleted with its prices;
   * one with history is turned off and kept for past bills. Refused while stations offer it.
   */
  protected remove(): void {
    const t = this.type();
    const data: ConfirmDialogData = t.stations
      ? {
          title: `${t.name} can't be removed yet`,
          message: `${t.stations} station${t.stations === 1 ? ' offers' : 's offer'} it. Remove it from those stations (or remove the stations) first.`,
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
        this.error.set('');
        try {
          const outcome = await this.store.removeType(t.id);
          this.say(
            outcome === 'deleted'
              ? `${t.name} deleted`
              : `${t.name} turned off · past bills keep it`,
          );
          if (outcome === 'deleted') this.closed.emit();
        } catch (e) {
          this.error.set(toAppError(e).message);
        } finally {
          this.busy.set(false);
        }
      });
  }

  private say(message: string): void {
    this.snack.open(message, undefined, { duration: 3200 });
  }
}
