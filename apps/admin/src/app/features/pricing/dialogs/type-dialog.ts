import { Component, effect, inject, signal, untracked } from '@angular/core';
import { FormField, form, hidden, validate } from '@angular/forms/signals';
import { MatButton } from '@angular/material/button';
import {
  MAT_DIALOG_DATA,
  MatDialogActions,
  MatDialogContent,
  MatDialogRef,
  MatDialogTitle,
} from '@angular/material/dialog';
import { MatFormField, MatHint, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatOption, MatSelect } from '@angular/material/select';
import { MatSlideToggle } from '@angular/material/slide-toggle';
import { toAppError } from '../../../core/auth/auth-api';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import { PricingStore } from '../data/pricing-store';
import { BILLING_STYLES, DurationModel, StationType, suggestCode } from '../data/pricing.models';

export interface TypeDialogData {
  /** Absent: add a type. Present: edit it (the code stays). */
  readonly type?: StationType;
}

/** Closes with the type's id and the snackbar text; undefined when cancelled. */
export interface TypeDialogResult {
  readonly id: string;
  readonly snack: string;
}

/**
 * Add or edit a station type (activity): name, code, billing style and what it uses. The code
 * is the type's permanent key (rates and sessions refer to it), so it is set once.
 */
@Component({
  selector: 'app-type-dialog',
  providers: [MATERIAL_DEFAULTS],
  imports: [
    FormField,
    MatDialogTitle,
    MatDialogContent,
    MatDialogActions,
    MatFormField,
    MatLabel,
    MatHint,
    MatInput,
    MatSelect,
    MatOption,
    MatSlideToggle,
    MatButton,
  ],
  template: `
    <h2 mat-dialog-title>{{ editing ? 'Edit type' : 'Add station type' }}</h2>
    <form novalidate (submit)="save($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <p class="text-sm leading-[1.4] text-muted">
            {{
              editing
                ? 'Changes apply to sessions started after you save.'
                : 'What staff can start on the floor, e.g. PlayStation 5, VR or Pool. Set its prices after.'
            }}
          </p>
          <mat-form-field>
            <mat-label>Name</mat-label>
            <input matInput autocomplete="off" [formField]="f.name" />
          </mat-form-field>
          @if (!editing) {
            <mat-form-field>
              <mat-label>Code</mat-label>
              <input
                matInput
                autocomplete="off"
                class="uppercase"
                [formField]="f.code"
                (input)="codeTouched = true"
              />
              <mat-hint>Short and permanent, e.g. PS5. Letters, digits or _.</mat-hint>
            </mat-form-field>
          } @else {
            <p class="text-sm text-muted">Code: {{ data.type?.code }}</p>
          }
          <mat-form-field>
            <mat-label>Billing</mat-label>
            <mat-select [value]="billing()" (selectionChange)="billing.set($event.value)">
              @for (b of styles; track b.key) {
                <mat-option [value]="b.key">{{ b.label }}</mat-option>
              }
            </mat-select>
          </mat-form-field>
          <div class="flex flex-col gap-4">
            @for (t of toggles; track t.key) {
              <div class="flex items-center justify-between gap-4">
                <span class="flex flex-col gap-1">
                  <span class="text-[15px] leading-[1.3]" [id]="'tt-' + t.key">{{ t.label }}</span>
                  <span class="text-[13px] leading-[1.3] text-muted">{{ t.sub }}</span>
                </span>
                <mat-slide-toggle
                  hideIcon
                  [checked]="t.value()"
                  [aria-labelledby]="'tt-' + t.key"
                  (change)="t.value.set($event.checked)"
                />
              </div>
            }
          </div>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" [disabled]="busy()">
          {{ editing ? 'Save' : 'Add type' }}
        </button>
      </mat-dialog-actions>
    </form>
  `,
})
export class TypeDialog {
  protected readonly data = inject<TypeDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<TypeDialog, TypeDialogResult>>(MatDialogRef);
  private readonly store = inject(PricingStore);

  protected readonly editing = !!this.data.type;
  protected readonly styles = BILLING_STYLES;
  protected codeTouched = false;

  protected readonly billing = signal<DurationModel>(this.data.type?.durationModel ?? 'hourly');
  private readonly pads = signal(this.data.type?.usesControllers ?? false);
  private readonly games = signal(this.data.type?.usesGames ?? false);
  private readonly happy = signal(this.data.type?.happyEligible ?? true);
  protected readonly toggles = [
    {
      key: 'pads',
      label: 'Uses controllers',
      sub: 'Pads are tracked; price by how many play',
      value: this.pads,
    },
    {
      key: 'games',
      label: 'Uses games',
      sub: 'Staff pick a game when starting',
      value: this.games,
    },
    {
      key: 'happy',
      label: 'Happy-hour pricing',
      sub: 'Charge the happy-hour rate during happy hour',
      value: this.happy,
    },
  ];

  protected readonly model = signal({
    name: this.data.type?.name ?? '',
    code: this.data.type?.code ?? '',
  });
  protected readonly f = form(this.model, (p) => {
    validate(p.name, ({ value }) => {
      const name = value().trim();
      return name.length >= 1 && name.length <= 40
        ? null
        : { kind: 'name', message: 'Enter a name of up to 40 characters' };
    });
    hidden(p.code, { when: () => this.editing });
    validate(p.code, ({ value }) => {
      const code = value().trim().toUpperCase();
      if (!/^[A-Z0-9_]{1,12}$/.test(code)) {
        return { kind: 'code', message: 'Use up to 12 letters, digits or _ for the code' };
      }
      return this.store.types().some((t) => t.code === code)
        ? { kind: 'taken', message: 'Another type already uses that code' }
        : null;
    });
  });
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  constructor() {
    // Until the code is typed by hand, it follows the name.
    effect(() => {
      const code = suggestCode(this.model().name);
      if (this.editing || this.codeTouched) return;
      untracked(() => this.model.update((m) => (m.code === code ? m : { ...m, code })));
    });
  }

  protected async save(event: Event): Promise<void> {
    event.preventDefault();
    const first = this.f().errorSummary()[0];
    if (first) {
      this.error.set(first.message ?? 'Check the form');
      return;
    }
    const existing = this.data.type;
    const name = this.model().name.trim();
    const id = existing?.id ?? crypto.randomUUID();
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.saveType({
        id,
        code: existing?.code ?? this.model().code.trim().toUpperCase(),
        name,
        usesControllers: this.pads(),
        usesGames: this.games(),
        durationModel: this.billing(),
        happyEligible: this.happy(),
        sortOrder: existing?.sortOrder ?? this.store.types().length,
        active: existing?.active ?? true,
      });
      this.ref.close({ id, snack: existing ? 'Type saved' : `${name} added · set its prices` });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
