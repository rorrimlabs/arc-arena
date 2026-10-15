import { Component, computed, inject, linkedSignal, output, resource, signal } from '@angular/core';
import { MatFormField, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatOption, MatSelect } from '@angular/material/select';
import { MatSlideToggle } from '@angular/material/slide-toggle';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ARENA_MESSAGES, ArenaApi, ArenaDetails } from '../../../core/arena/arena-api';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { NOUN_WORDS, RESOURCE_NOUNS, ResourceNoun, VenueStore } from '../../../core/venue/venue';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { UnsavedBar } from '../../../shared/list-detail/unsaved-bar';
import { PricingStore } from '../../pricing/data/pricing-store';
import {
  BusinessHours,
  WEEKDAYS,
  fromTimeInput,
  toTimeInput,
} from '../../pricing/data/pricing.models';

interface DayDraft {
  readonly on: boolean;
  readonly from: string;
  readonly to: string;
}

const LONG = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const DEFAULT_OPEN = 10 * 60;
const DEFAULT_CLOSE = 23 * 60;

/**
 * Design: settings `arena`. Opening hours per weekday are the arena's `business_hours` (shared
 * with every floor device and part of the price list).
 * Name, area and phone are the arena row (arena.update). One unsaved-changes bar covers both;
 * Save sends only what changed.
 */
@Component({
  selector: 'app-arena-settings',
  imports: [
    DetailPane,
    DetailSection,
    UnsavedBar,
    MatFormField,
    MatLabel,
    MatInput,
    MatSelect,
    MatOption,
    MatSlideToggle,
  ],
  template: `
    <app-detail-pane
      crumb="Settings / Arena"
      icon="storefront"
      heading="Arena"
      [subtitle]="subtitle()"
      (closed)="closed.emit()"
    >
      <app-detail-section heading="Details" subtitle="Shown on bills and the floor app.">
        @if (details.error()) {
          <p role="alert" class="text-[13px] leading-[1.45] text-danger">
            Arena details couldn't load: {{ detailsError() }}
          </p>
        } @else if (!details.hasValue()) {
          <p class="text-[13px] leading-[1.45] text-muted">Loading…</p>
        } @else {
          @for (f of fields; track f.key) {
            <mat-form-field>
              <mat-label>{{ f.label }}</mat-label>
              <input
                matInput
                autocomplete="off"
                [attr.inputmode]="f.key === 'phone' ? 'tel' : null"
                [attr.maxlength]="f.max"
                [value]="info()[f.key]"
                (input)="setInfo(f.key, $any($event.target).value)"
              />
            </mat-form-field>
          }
        }
      </app-detail-section>

      <app-detail-section
        heading="What you rent out"
        subtitle="The word staff and you see for your stations, tables or grounds."
      >
        <mat-form-field class="max-w-64">
          <mat-label>Call them</mat-label>
          <mat-select
            [value]="venue.noun()"
            [disabled]="nounBusy() || !arena.canEdit()"
            (selectionChange)="saveNoun($event.value)"
          >
            @for (n of nouns; track n) {
              <mat-option [value]="n">{{ nounWords[n].many }}</mat-option>
            }
          </mat-select>
        </mat-form-field>
      </app-detail-section>

      <app-detail-section
        heading="Opening hours"
        subtitle="Times in IST. Staff can't start sessions outside them. A close of 00:00 is midnight."
      >
        @if (pricing.loadError(); as error) {
          <p role="alert" class="text-[13px] leading-[1.45] text-danger">
            Opening hours couldn't load: {{ error }}
          </p>
        } @else if (!pricing.hours()) {
          <p class="text-[13px] leading-[1.45] text-muted">Loading…</p>
        } @else {
          @for (d of days; track d.key) {
            @let day = draft()[d.key];
            <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
              <div class="flex w-40 items-center gap-3">
                <mat-slide-toggle
                  hideIcon
                  [checked]="day.on"
                  [attr.aria-label]="d.long + ' open'"
                  (change)="set(d.key, { on: $event.checked })"
                />
                <span class="flex flex-col">
                  <span class="text-[15px] leading-[1.3]">{{ d.long }}</span>
                  <span class="text-xs text-muted">{{ day.on ? 'Open' : 'Closed' }}</span>
                </span>
              </div>
              @if (day.on) {
                <mat-form-field class="arena-dense w-36">
                  <mat-label>Opens at</mat-label>
                  <input
                    matInput
                    type="time"
                    [value]="day.from"
                    (input)="set(d.key, { from: $any($event.target).value })"
                  />
                </mat-form-field>
                <mat-form-field class="arena-dense w-36">
                  <mat-label>Closes at</mat-label>
                  <input
                    matInput
                    type="time"
                    [value]="day.to"
                    (input)="set(d.key, { to: $any($event.target).value })"
                  />
                </mat-form-field>
              }
            </div>
          }
        }
        @if (error()) {
          <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
        }
      </app-detail-section>

      @if (dirty()) {
        <app-unsaved-bar footer [busy]="busy()" (discard)="discard()" (save)="save()" />
      }
    </app-detail-pane>
  `,
})
export class ArenaSettings {
  protected readonly arena = inject(ArenaContext);
  protected readonly pricing = inject(PricingStore);
  private readonly arenaApi = inject(ArenaApi);
  private readonly snack = inject(MatSnackBar);
  protected readonly venue = inject(VenueStore);
  protected readonly nouns = RESOURCE_NOUNS;
  protected readonly nounWords = NOUN_WORDS;
  protected readonly nounBusy = signal(false);

  readonly closed = output<void>();

  protected readonly days = WEEKDAYS.map((d) => ({ ...d, long: LONG[Number(d.key) - 1] }));

  private readonly saved = computed<Record<string, DayDraft>>(() => {
    const open = this.pricing.hours()?.open ?? {};
    const out: Record<string, DayDraft> = {};
    for (const d of WEEKDAYS) {
      const w = open[d.key];
      out[d.key] = {
        on: !!w,
        from: toTimeInput(w?.start ?? DEFAULT_OPEN),
        to: toTimeInput(w?.end ?? DEFAULT_CLOSE),
      };
    }
    return out;
  });
  protected readonly draft = linkedSignal(() => this.saved());
  /** The arena row (name, area, phone); reloaded after a save. */
  private readonly revision = signal(0);
  protected readonly details = resource({
    params: () => ({ id: this.arena.current().id, revision: this.revision() }),
    loader: ({ params }) => this.arenaApi.details(params.id),
  });
  protected readonly detailsError = computed(() => toAppError(this.details.error()).message);
  private readonly savedInfo = computed<ArenaDetails>(() =>
    this.details.hasValue() ? this.details.value() : { name: '', area: '', phone: '' },
  );
  protected readonly info = linkedSignal(() => this.savedInfo());
  protected readonly fields: readonly { key: keyof ArenaDetails; label: string; max: number }[] = [
    { key: 'name', label: 'Arena name', max: 80 },
    { key: 'area', label: 'Area', max: 80 },
    { key: 'phone', label: 'Phone', max: 20 },
  ];
  protected readonly subtitle = computed(() => {
    const d = this.savedInfo();
    return [d.name || this.arena.current().name, d.area].filter(Boolean).join(' · ');
  });
  private readonly infoDirty = computed(() =>
    this.fields.some((f) => this.info()[f.key].trim() !== this.savedInfo()[f.key]),
  );
  protected readonly dirty = computed(() => this.infoDirty() || this.hoursDirty());
  private readonly hoursDirty = computed(() =>
    WEEKDAYS.some((d) => {
      const a = this.draft()[d.key];
      const b = this.saved()[d.key];
      return a.on !== b.on || (a.on && (a.from !== b.from || a.to !== b.to));
    }),
  );
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected set(day: string, change: Partial<DayDraft>): void {
    this.draft.update((d) => ({ ...d, [day]: { ...d[day], ...change } }));
  }

  protected async saveNoun(noun: ResourceNoun): Promise<void> {
    this.nounBusy.set(true);
    try {
      await this.venue.saveNoun(noun);
      this.snack.open(`Now called ${NOUN_WORDS[noun].many.toLowerCase()}`, undefined, {
        duration: 3200,
      });
    } catch (e) {
      this.snack.open(toAppError(e).message, undefined, { duration: 4000 });
    } finally {
      this.nounBusy.set(false);
    }
  }

  protected setInfo(key: keyof ArenaDetails, value: string): void {
    this.info.update((d) => ({ ...d, [key]: value }));
  }

  protected discard(): void {
    this.info.set(this.savedInfo());
    this.draft.set(this.saved());
    this.error.set('');
  }

  protected async save(): Promise<void> {
    const hours = this.pricing.hours();
    let next: BusinessHours | null = null;
    if (this.hoursDirty() && hours) {
      const open: Record<string, { start: number; end: number } | null> = {};
      for (const d of this.days) {
        const day = this.draft()[d.key];
        if (!day.on) {
          open[d.key] = null;
          continue;
        }
        const start = fromTimeInput(day.from);
        const close = fromTimeInput(day.to);
        // 00:00 as a closing time is midnight at the end of the day.
        const end = close === 0 ? 1440 : close;
        if (start == null || end == null || end <= start) {
          this.error.set(`${d.long}: closing time must be after opening time`);
          return;
        }
        open[d.key] = { start, end };
      }
      next = { open };
    }
    const info = this.info();
    const details: ArenaDetails | null = this.infoDirty()
      ? { name: info.name.trim(), area: info.area.trim(), phone: info.phone.trim() }
      : null;
    if (details && !details.name) {
      this.error.set(ARENA_MESSAGES['invalid_name']);
      return;
    }
    this.busy.set(true);
    this.error.set('');
    try {
      if (details) {
        await this.arenaApi.saveDetails(this.arena.current().id, details);
        // The arena list (switcher, page titles) carries the name.
        await this.arena.load(true);
        this.revision.update((n) => n + 1);
      }
      if (next) await this.pricing.saveHours(next);
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
