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
import { PayMethod } from '../../sales/data/sale.models';
import { FloorOptionsStore } from '../data/floor-options';

/**
 * Design: settings `billing`. Payment methods are the floor options' `payment_methods` (what
 * staff are offered on the floor app). GST, invoice numbering and discount rules await the
 * owner's decisions (docs/OWNER_CONFIRMATION.md #21, #22), so those stay disabled.
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

      <app-detail-section heading="Discounts">
        <mat-form-field>
          <mat-label>Max staff discount %</mat-label>
          <input matInput disabled value="" />
          <span matTextSuffix>%</span>
        </mat-form-field>
        <app-toggle-row
          label="Discount needs a reason"
          sub="Staff pick a reason before applying"
          [disabled]="true"
        />
        <app-not-connected>Discount limits and reasons aren't stored yet.</app-not-connected>
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
  protected readonly dirty = computed(() => {
    const now = this.draft();
    const saved = this.store.options()?.paymentMethods;
    return !!now && !!saved && [...now].sort().join() !== [...saved].sort().join();
  });
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

  protected discard(): void {
    this.draft.set(this.store.options()?.paymentMethods ?? null);
    this.error.set('');
  }

  protected async save(): Promise<void> {
    const options = this.store.options();
    const methods = this.draft();
    if (!options || !methods) return;
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.save({ ...options, paymentMethods: methods });
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
