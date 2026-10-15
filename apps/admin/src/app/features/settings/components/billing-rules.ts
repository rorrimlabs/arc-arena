import { Component, computed, effect, inject, linkedSignal, output, signal } from '@angular/core';
import { FormField, form } from '@angular/forms/signals';
import { MatFormField, MatHint, MatLabel } from '@angular/material/form-field';
import { MatOption, MatSelect } from '@angular/material/select';
import { MatSlideToggle } from '@angular/material/slide-toggle';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { UnsavedBar } from '../../../shared/list-detail/unsaved-bar';
import {
  BILLING_UNITS,
  BLOCK_ROUNDINGS,
  BillingPolicy,
  DEFAULT_POLICY,
  EARLY_EXITS,
  GROUP_MODES,
  MONEY_DIRS,
  ROUNDING_SCOPES,
  VR_ROUNDINGS,
  minuteChoices,
  moneyRoundingChoices,
  policySummary,
  samePolicy,
} from '../../pricing/data/billing-policy';
import { PricingStore } from '../../pricing/data/pricing-store';

/**
 * Billing rules (server: billing_policies, op policy.save): the rules the price list does not
 * state, as the floor app's Settings → Billing rules offers them. Edits collect in a draft with
 * the unsaved-changes bar; Save sends the whole policy. Every session captures the rules it
 * started under, so a change applies to new sessions only. Late arrival and payment timing are
 * not offered (as on the floor app) and are saved as they are.
 */
@Component({
  selector: 'app-billing-rules',
  imports: [
    DetailPane,
    DetailSection,
    UnsavedBar,
    FormField,
    MatFormField,
    MatLabel,
    MatHint,
    MatSelect,
    MatOption,
    MatSlideToggle,
  ],
  template: `
    <app-detail-pane
      crumb="Settings / Billing rules"
      icon="rule"
      heading="Billing rules"
      [subtitle]="summary()"
      (closed)="closed.emit()"
    >
      @if (store.loadError(); as error) {
        <app-detail-section>
          <p role="alert" class="text-[13px] leading-[1.45] text-danger">
            Billing rules couldn't load: {{ error }}
          </p>
        </app-detail-section>
      } @else if (!store.policy()) {
        <app-detail-section>
          <p class="text-[13px] leading-[1.45] text-muted">Loading…</p>
        </app-detail-section>
      } @else {
        <p class="text-[13px] leading-[1.45] text-muted">
          The rules the price list doesn't state. Each session keeps the rules it started under: a
          change applies to sessions started after you save.
        </p>

        <app-detail-section heading="Time" subtitle="How played time becomes billed time.">
          <mat-form-field>
            <mat-label>Charge partial time</mat-label>
            <mat-select [formField]="f.billingUnit">
              @for (c of units; track c.value) {
                <mat-option [value]="c.value">{{ c.label }}</mat-option>
              }
            </mat-select>
            <mat-hint>How a part-hour becomes money</mat-hint>
          </mat-form-field>
          @if (draft().billingUnit !== 'per_minute') {
            <mat-form-field>
              <mat-label>Block rounding</mat-label>
              <mat-select [formField]="f.blockRounding">
                @for (c of blockRoundings; track c.value) {
                  <mat-option [value]="c.value">{{ c.label }}</mat-option>
                }
              </mat-select>
              <mat-hint>When time falls mid-block</mat-hint>
            </mat-form-field>
          }
          <mat-form-field>
            <mat-label>Grace period</mat-label>
            <mat-select [formField]="f.graceMinutes">
              @for (c of graceChoices(); track c.value) {
                <mat-option [value]="c.value">{{ c.label }}</mat-option>
              }
            </mat-select>
            <mat-hint>Under this, the session is free</mat-hint>
          </mat-form-field>
          <mat-form-field>
            <mat-label>Overtime grace</mat-label>
            <mat-select [formField]="f.overtimeGraceMinutes">
              @for (c of overtimeChoices(); track c.value) {
                <mat-option [value]="c.value">{{ c.label }}</mat-option>
              }
            </mat-select>
            <mat-hint
              >Past the booked end: within this, only the booked time is billed; beyond it, the
              whole time is. None = every extra minute is billed.</mat-hint
            >
          </mat-form-field>
          <mat-form-field>
            <mat-label>Minimum charge</mat-label>
            <mat-select [formField]="f.minimumChargeMinutes">
              @for (c of minimumChoices(); track c.value) {
                <mat-option [value]="c.value">{{ c.label }}</mat-option>
              }
            </mat-select>
            <mat-hint>Shortest billable session</mat-hint>
          </mat-form-field>
          <mat-form-field>
            <mat-label>If they leave early</mat-label>
            <mat-select [formField]="f.earlyExit">
              @for (c of earlyExits; track c.value) {
                <mat-option [value]="c.value">{{ c.label }}</mat-option>
              }
            </mat-select>
          </mat-form-field>
        </app-detail-section>

        <app-detail-section heading="Money" subtitle="How the final bill is rounded.">
          <mat-form-field>
            <mat-label>Round the final bill to</mat-label>
            <mat-select [formField]="f.moneyRoundingPaise">
              @for (c of roundingChoices(); track c.value) {
                <mat-option [value]="c.value">{{ c.label }}</mat-option>
              }
            </mat-select>
          </mat-form-field>
          <mat-form-field>
            <mat-label>Rounding direction</mat-label>
            <mat-select [formField]="f.moneyRoundingDir">
              @for (c of moneyDirs; track c.value) {
                <mat-option [value]="c.value">{{ c.label }}</mat-option>
              }
            </mat-select>
          </mat-form-field>
          <mat-form-field>
            <mat-label>Round once or per segment</mat-label>
            <mat-select [formField]="f.roundingScope">
              @for (c of roundingScopes; track c.value) {
                <mat-option [value]="c.value">{{ c.label }}</mat-option>
              }
            </mat-select>
            <mat-hint>A session that switched station has several segments</mat-hint>
          </mat-form-field>
        </app-detail-section>

        <app-detail-section
          heading="Fixed-block types"
          subtitle="Types sold in blocks, e.g. VR or a turf hour."
        >
          <mat-form-field>
            <mat-label>Part-used block</mat-label>
            <mat-select [formField]="f.vrUnitRounding">
              @for (c of vrRoundings; track c.value) {
                <mat-option [value]="c.value">{{ c.label }}</mat-option>
              }
            </mat-select>
          </mat-form-field>
        </app-detail-section>

        <app-detail-section heading="Groups">
          <mat-form-field>
            <mat-label>Group across several systems</mat-label>
            <mat-select [formField]="f.groupBillingMode">
              @for (c of groupModes; track c.value) {
                <mat-option [value]="c.value">{{ c.label }}</mat-option>
              }
            </mat-select>
            <mat-hint>Three controllers does not automatically buy three systems</mat-hint>
          </mat-form-field>
        </app-detail-section>

        <app-detail-section heading="Floor">
          <div class="flex items-center justify-between gap-4">
            <span class="flex flex-col gap-1">
              <span class="text-[15px] leading-[1.3]" id="rules-extend"
                >Allow extending past closing time</span
              >
              <span class="text-[13px] leading-[1.3] text-muted" id="rules-extend-sub"
                >Off: an extension stops at closing</span
              >
            </span>
            <mat-slide-toggle
              hideIcon
              aria-labelledby="rules-extend"
              aria-describedby="rules-extend-sub"
              [formField]="f.allowExtendPastClose"
            />
          </div>
          <mat-form-field>
            <mat-label>Cleaning gap between sessions</mat-label>
            <mat-select [formField]="f.cleaningGapMinutes">
              @for (c of gapChoices(); track c.value) {
                <mat-option [value]="c.value">{{ c.label }}</mat-option>
              }
            </mat-select>
            <mat-hint>Held free after a session ends</mat-hint>
          </mat-form-field>
          @if (error()) {
            <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
          }
        </app-detail-section>
      }

      @if (dirty()) {
        <app-unsaved-bar footer [busy]="busy()" (discard)="discard()" (save)="save()" />
      }
    </app-detail-pane>
  `,
})
export class BillingRules {
  protected readonly arena = inject(ArenaContext);
  protected readonly store = inject(PricingStore);
  private readonly snack = inject(MatSnackBar);
  readonly closed = output<void>();

  protected readonly units = BILLING_UNITS;
  protected readonly blockRoundings = BLOCK_ROUNDINGS;
  protected readonly earlyExits = EARLY_EXITS;
  protected readonly moneyDirs = MONEY_DIRS;
  protected readonly roundingScopes = ROUNDING_SCOPES;
  protected readonly vrRoundings = VR_ROUNDINGS;
  protected readonly groupModes = GROUP_MODES;

  private readonly saved = computed(() => this.store.policy() ?? DEFAULT_POLICY);
  /** The draft starts from (and follows) what the server holds. */
  protected readonly draft = linkedSignal<BillingPolicy>(() => this.saved());
  protected readonly f = form(this.draft);
  protected readonly dirty = computed(
    () => !!this.store.policy() && !samePolicy(this.draft(), this.saved()),
  );
  /** What is saved, in short (the arena's name until the rules load). */
  protected readonly summary = computed(() => {
    const p = this.store.policy();
    return p ? policySummary(p) : this.arena.current().name;
  });
  /** Each list offers the floor app's choices plus the saved value, so it always shows. */
  protected readonly graceChoices = computed(() => minuteChoices(this.saved().graceMinutes));
  protected readonly overtimeChoices = computed(() =>
    minuteChoices(this.saved().overtimeGraceMinutes),
  );
  protected readonly minimumChoices = computed(() =>
    minuteChoices(this.saved().minimumChargeMinutes),
  );
  protected readonly gapChoices = computed(() => minuteChoices(this.saved().cleaningGapMinutes));
  protected readonly roundingChoices = computed(() =>
    moneyRoundingChoices(this.saved().moneyRoundingPaise),
  );
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  constructor() {
    effect(() => {
      if (this.arena.current().id) void this.store.load();
    });
  }

  protected discard(): void {
    this.draft.set(this.saved());
    this.error.set('');
  }

  protected async save(): Promise<void> {
    if (!this.store.policy()) return;
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.savePolicy(this.draft());
      this.snack.open('Billing rules saved · new sessions use them', undefined, {
        duration: 3200,
      });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
