import { Component, computed, effect, inject, linkedSignal, output, signal } from '@angular/core';
import { MatFormField, MatLabel, MatSuffix } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatSlideToggleChange } from '@angular/material/slide-toggle';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { ToggleRow } from '../../../shared/list-detail/toggle-row';
import { UnsavedBar } from '../../../shared/list-detail/unsaved-bar';
import { NotConnected } from '../../../shared/not-connected/not-connected';
import { PricingStore } from '../../pricing/data/pricing-store';
import { DiscountOptions } from '../../pricing/data/pricing.models';
import { PayMethod } from '../../sales/data/sale.models';
import { FloorOptionsStore } from '../data/floor-options';

/**
 * Settings › Billing. Payment methods are the floor options' `payment_methods` (what staff are
 * offered on the floor app); the discount limits are `discount_options` (how much staff may take
 * off a bill by hand, and whether they must say why). GST and invoice numbering await the owner's
 * decision (docs/OWNER_CONFIRMATION.md #22), so those stay disabled.
 */
@Component({
  selector: 'app-billing-settings',
  imports: [
    DetailPane,
    DetailSection,
    ToggleRow,
    NotConnected,
    UnsavedBar,
    MatFormField,
    MatLabel,
    MatSuffix,
    MatInput,
  ],
  template: `
    <app-detail-pane
      crumb="Settings / Billing"
      icon="payments"
      heading="Billing"
      [subtitle]="arena.current().name"
      (closed)="closed.emit()"
    >
      <app-detail-section heading="Tax and invoices">
        <mat-form-field>
          <mat-label>GST %</mat-label>
          <input matInput disabled value="" />
          <span matTextSuffix>%</span>
        </mat-form-field>
        <app-toggle-row
          label="Prices include GST"
          sub="Rates you set are the final price"
          [disabled]="true"
        />
        <mat-form-field>
          <mat-label>Invoice prefix</mat-label>
          <input matInput disabled value="" />
        </mat-form-field>
        <app-not-connected>GST and invoice numbering aren't stored yet.</app-not-connected>
      </app-detail-section>

      <app-detail-section heading="Payment methods">
        @if (store.loadError(); as error) {
          <p role="alert" class="text-[13px] leading-[1.45] text-danger">
            Payment methods couldn't load: {{ error }}
          </p>
        } @else if (!draft()) {
          <p class="text-[13px] leading-[1.45] text-muted">Loading…</p>
        } @else {
          @for (m of methods; track m.key) {
            <app-toggle-row
              [label]="m.label"
              [sub]="m.sub"
              [checked]="offered(m.key)"
              [disabled]="busy()"
              (changed)="toggle(m.key, $event)"
            />
          }
          <p class="text-[13px] leading-[1.45] text-muted">
            Staff see only these when taking money on the floor app. A payment already taken offline
            is still recorded.
          </p>
        }
        @if (error()) {
          <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
        }
      </app-detail-section>

      <app-detail-section
        heading="Manual discounts"
        subtitle="What staff may take off a bill by hand at checkout. Presets and coupons are set in Pricing."
      >
        @if (pricing.loadError(); as error) {
          <p role="alert" class="text-[13px] leading-[1.45] text-danger">
            Discount limits couldn't load: {{ error }}
          </p>
        } @else if (!pricing.data()) {
          <p class="text-[13px] leading-[1.45] text-muted">Loading…</p>
        } @else {
          <mat-form-field>
            <mat-label>Max staff discount %</mat-label>
            <input
              matInput
              type="number"
              inputmode="numeric"
              min="0"
              max="100"
              [value]="discountDraft().manualMaxPercent"
              (input)="setMax($any($event.target).value)"
            />
            <span matTextSuffix>%</span>
          </mat-form-field>
          <p class="-mt-2 text-[13px] leading-[1.45] text-muted">
            0 = staff can't discount by hand. Owners (Settings permission) are not limited.
            The same limit caps how much of a bill staff may waive; only owners (Money or
            Reports) waive more.
          </p>
          <app-toggle-row
            label="Discount needs a reason"
            sub="Staff say why before a manual discount is applied"
            [checked]="discountDraft().reasonRequired"
            [disabled]="busy()"
            (changed)="setReason($event.checked)"
          />
        }
      </app-detail-section>
      @if (dirty()) {
        <app-unsaved-bar footer [busy]="busy()" (discard)="discard()" (save)="save()" />
      }
    </app-detail-pane>
  `,
})
export class BillingSettings {
  protected readonly arena = inject(ArenaContext);
  protected readonly store = inject(FloorOptionsStore);
  protected readonly pricing = inject(PricingStore);
  private readonly snack = inject(MatSnackBar);
  readonly closed = output<void>();

  /** The design's Cash and UPI first; Card and Other are what the floor app also offers. */
  protected readonly methods: readonly { key: PayMethod; label: string; sub: string }[] = [
    { key: 'cash', label: 'Cash', sub: 'Staff can take cash' },
    { key: 'upi', label: 'UPI', sub: 'Staff can take UPI' },
    { key: 'card', label: 'Card', sub: 'Staff can take card payments' },
    { key: 'other', label: 'Other', sub: 'Any other method staff record' },
  ];
  protected readonly draft = linkedSignal(() => this.store.options()?.paymentMethods ?? null);
  protected readonly discountDraft = linkedSignal<DiscountOptions>(() =>
    this.pricing.discountOptions(),
  );
  private readonly methodsDirty = computed(() => {
    const now = this.draft();
    const saved = this.store.options()?.paymentMethods;
    return !!now && !!saved && [...now].sort().join() !== [...saved].sort().join();
  });
  private readonly discountDirty = computed(() => {
    const a = this.discountDraft();
    const b = this.pricing.discountOptions();
    return a.manualMaxPercent !== b.manualMaxPercent || a.reasonRequired !== b.reasonRequired;
  });
  protected readonly dirty = computed(() => this.methodsDirty() || this.discountDirty());
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  constructor() {
    effect(() => {
      if (this.arena.current().id) void this.store.load();
    });
  }

  protected offered(m: PayMethod): boolean {
    return this.draft()?.includes(m) ?? false;
  }

  protected toggle(m: PayMethod, event: MatSlideToggleChange): void {
    const now = this.draft() ?? [];
    const next = event.checked ? [...now, m] : now.filter((x) => x !== m);
    if (!next.length) {
      event.source.checked = true;
      this.snack.open('Keep at least one payment method on', undefined, { duration: 3200 });
      return;
    }
    this.draft.set(next);
  }

  protected setMax(value: string): void {
    this.discountDraft.update((d) => ({ ...d, manualMaxPercent: Number(value) }));
  }

  protected setReason(checked: boolean): void {
    this.discountDraft.update((d) => ({ ...d, reasonRequired: checked }));
  }

  protected discard(): void {
    this.draft.set(this.store.options()?.paymentMethods ?? null);
    this.discountDraft.set(this.pricing.discountOptions());
    this.error.set('');
  }

  protected async save(): Promise<void> {
    const options = this.store.options();
    const methods = this.draft();
    const limits = this.discountDraft();
    if (this.discountDirty()) {
      const max = limits.manualMaxPercent;
      if (!Number.isInteger(max) || max < 0 || max > 100) {
        this.error.set('Max staff discount is a whole percent from 0 to 100');
        return;
      }
    }
    this.busy.set(true);
    this.error.set('');
    try {
      if (this.methodsDirty() && options && methods) {
        await this.store.save({ ...options, paymentMethods: methods });
      }
      if (this.discountDirty()) await this.pricing.saveDiscountOptions(limits);
      this.snack.open('Settings saved · the floor app updates on next refresh', undefined, {
        duration: 3200,
      });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
