import { Component, computed, inject, input, linkedSignal, output, signal } from '@angular/core';
import { MatFormField, MatLabel, MatSuffix } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatSnackBar } from '@angular/material/snack-bar';
import { toAppError } from '../../../core/auth/auth-api';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailRow } from '../../../shared/list-detail/detail-row';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { UnsavedBar } from '../../../shared/list-detail/unsaved-bar';
import { formatRupees } from '../../../shared/money/rupees.pipe';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { PricingStore } from '../data/pricing-store';
import {
  RateChange,
  StationType,
  cheapestRate,
  findRate,
  maxPlayers,
  perLabel,
  rateRows,
  rulePrice,
  ruleWhen,
  typeIcon,
  unitMinutesOf,
} from '../data/pricing.models';

const MAX_RUPEES = 100_000;

type Draft = Readonly<Record<string, string>>;

const cell = (controllers: number | null) => String(controllers ?? 'any');

/**
 * A station type's prices: the base price (one controller, or any group), then optionally the
 * price for more controllers, in whole rupees per hour or per block, and what the time rules
 * (happy hours included) make of it. Edits collect in a draft with the unsaved-changes
 * bar; Save sends only the prices that changed (a cleared price is removed). The type itself is
 * edited in Settings › Station types.
 */
@Component({
  selector: 'app-type-detail',
  imports: [
    DetailPane,
    DetailSection,
    DetailRow,
    StatusPill,
    UnsavedBar,
    MatFormField,
    MatLabel,
    MatSuffix,
    MatInput,
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
      <app-status-pill chip [tone]="hasStandard() ? 'primary' : 'warning'">{{
        hasStandard() ? 'Priced' : 'No price'
      }}</app-status-pill>

      <app-detail-section heading="Base price" [subtitle]="priceHelp()">
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
          class="grid grid-cols-[minmax(0,1fr)_minmax(0,9rem)] items-center gap-x-3 gap-y-2"
          role="group"
          aria-label="Prices"
        >
          @for (row of baseRows(); track row) {
            <span class="text-sm">{{ rowLabel(row) }}</span>
            <mat-form-field class="arena-dense">
              <span matTextPrefix>₹&nbsp;</span>
              <input
                matInput
                type="number"
                inputmode="numeric"
                min="0"
                [attr.aria-label]="'Price, ' + rowLabel(row)"
                [value]="draft()[key(row)] ?? ''"
                (input)="setCell(row, $any($event.target).value)"
              />
            </mat-form-field>
          }
        </div>
        @if (!hasStandard()) {
          <p class="text-[13px] leading-[1.45] text-warning">
            No price set: staff can't start {{ t.name }} until it has one.
          </p>
        }
        @if (error()) {
          <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
        }
      </app-detail-section>

      @if (moreRows().length) {
        <app-detail-section
          heading="Price by controller count"
          subtitle="Per station, when more controllers are in use. Leave a row blank if a station never takes that many."
        >
          <div
            class="grid grid-cols-[minmax(0,1fr)_minmax(0,9rem)] items-center gap-x-3 gap-y-2"
            role="group"
            aria-label="Prices by controller count"
          >
            @for (row of moreRows(); track row) {
              <span class="text-sm">{{ rowLabel(row) }}</span>
              <mat-form-field class="arena-dense">
                <span matTextPrefix>₹&nbsp;</span>
                <input
                  matInput
                  type="number"
                  inputmode="numeric"
                  min="0"
                  [attr.aria-label]="'Price, ' + rowLabel(row)"
                  [value]="draft()[key(row)] ?? ''"
                  (input)="setCell(row, $any($event.target).value)"
                />
              </mat-form-field>
            }
          </div>
          <app-detail-row label="Max players" [value]="players()" />
        </app-detail-section>
      }

      <app-detail-section
        heading="With rules applied"
        subtitle="What staff are charged in each pricing window, from the saved prices."
      >
        @if (base(); as b) {
          <app-detail-row label="Base" [value]="b" />
          @for (r of ruleRows(); track r.label) {
            <app-detail-row [label]="r.label" [value]="r.value" />
          } @empty {
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
  private readonly store = inject(PricingStore);
  private readonly snack = inject(MatSnackBar);

  readonly type = input.required<StationType>();
  readonly closed = output<void>();

  protected readonly icon = computed(() => typeIcon(this.type()));
  protected readonly players = computed(() => {
    const n = maxPlayers(this.type(), this.store.rates());
    return n ? String(n) : 'Any';
  });
  private readonly cheapest = computed(() => cheapestRate(this.type(), this.store.rates()));
  /** The design's "With rules applied": the headline price, before any rule. */
  protected readonly base = computed(() => {
    const c = this.cheapest();
    return c ? `${formatRupees(c.pricePaise)} ${perLabel(c.unitMinutes)}` : null;
  });
  protected readonly rows = computed(() => rateRows(this.type()));
  /** The base price: 1 controller, or any number of players. */
  protected readonly baseRows = computed(() => this.rows().slice(0, 1));
  /** 2 controllers and up. */
  protected readonly moreRows = computed(() => this.rows().slice(1));
  /** Each enabled time rule covering this type, applied to the headline price. */
  protected readonly ruleRows = computed(() => {
    const t = this.type();
    const cheapest = this.cheapest();
    if (!cheapest) return [];
    const per = perLabel(cheapest.unitMinutes);
    return this.store
      .rules()
      .filter((r) => r.active && (!r.activityCodes.length || r.activityCodes.includes(t.code)))
      .map((r) => ({
        label: `${r.name} · ${ruleWhen(r)}`,
        value: `${formatRupees(rulePrice(cheapest.pricePaise, cheapest.unitMinutes, r))} ${per}`,
      }));
  });
  protected readonly priceHelp = computed(() => {
    const t = this.type();
    const per = t.durationModel === 'unit' ? 'per block' : 'per hour';
    if (t.usesControllers) return `What one station charges ${per} with one controller in use.`;
    return `What one station charges ${per}, however many play.`;
  });

  /** The saved prices as the draft starts them (whole rupees). */
  private readonly saved = computed<Draft>(() => {
    const t = this.type();
    const out: Record<string, string> = {};
    for (const row of rateRows(t)) {
      const r = findRate(this.store.rates(), t.code, row);
      if (r) out[cell(row)] = String(r.pricePaise / 100);
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
    rateRows(this.type()).some((row) => (this.saved()[cell(row)] ?? '') !== ''),
  );
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected key = cell;

  protected rowLabel(row: number | null): string {
    if (row == null) return 'Any number of players';
    return row === 1 ? '1 controller' : `${row} controllers`;
  }

  protected setCell(row: number | null, value: string): void {
    this.draft.update((d) => ({ ...d, [cell(row)]: value }));
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
    for (const row of this.rows()) {
      const k = cell(row);
      const now = (this.draft()[k] ?? '').trim();
      const before = (this.saved()[k] ?? '').trim();
      if (now === before && !(unitChanged && now !== '')) continue;
      if (now === '') {
        changes.push({
          activityCode: t.code,
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
        controllerCount: row,
        unitMinutes: unit,
        pricePaise: rupees * 100,
      });
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

  private say(message: string): void {
    this.snack.open(message, undefined, { duration: 3200 });
  }
}
