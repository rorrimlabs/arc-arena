import { Component, computed, effect, inject, linkedSignal, output, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatFormField, MatHint, MatLabel, MatSuffix } from '@angular/material/form-field';
import { MatIcon } from '@angular/material/icon';
import { MatInput } from '@angular/material/input';
import { MatRadioButton, MatRadioGroup } from '@angular/material/radio';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { UnsavedBar } from '../../../shared/list-detail/unsaved-bar';
import { GeoMap, GeoPoint } from '../../../shared/map/geo-map';
import {
  ATTENDANCE_LIMITS,
  AttendanceDraft,
  AttendanceRulesStore,
  DEFAULT_ATTENDANCE_RULES,
  DEFAULT_RADIUS_M,
  MOCK_RULES,
  OUTSIDE_RULES,
  draftHasLocation,
  draftProblems,
  fromDraft,
  rulesSummary,
  sameDraft,
  toDraft,
} from '../data/attendance-rules';

/**
 * Settings › Attendance (docs/STAFF.md §5): where the arena is (a centre and a radius, set on
 * the map or typed), what happens to a clock-in or clock-out outside it or with an unknown
 * position, the minimum GPS accuracy, the fake-location rule and when a forgotten clock-in is
 * closed. Edits collect in a draft with the unsaved-changes bar; Save sends the whole setting
 * (settings.save, key `attendance`), checked here against the server's limits first.
 */
@Component({
  selector: 'app-attendance-settings',
  imports: [
    DetailPane,
    DetailSection,
    UnsavedBar,
    GeoMap,
    MatButton,
    MatIcon,
    MatFormField,
    MatLabel,
    MatHint,
    MatSuffix,
    MatInput,
    MatRadioGroup,
    MatRadioButton,
  ],
  template: `
    <app-detail-pane
      crumb="Settings / Staff / Clock-in and location rules"
      icon="badge"
      heading="Clock-in and location rules"
      [subtitle]="summary()"
      (closed)="closed.emit()"
    >
      @if (store.loadError(); as error) {
        <app-detail-section>
          <p role="alert" class="text-[13px] leading-[1.45] text-danger">
            Attendance settings couldn't load: {{ error }}
          </p>
        </app-detail-section>
      } @else if (!store.rules()) {
        <app-detail-section>
          <p class="text-[13px] leading-[1.45] text-muted">Loading…</p>
        </app-detail-section>
      } @else {
        @let d = draft();
        @let p = shownProblems();
        <p class="text-[13px] leading-[1.45] text-muted">
          Staff clock in and out on the floor app. The server records the time and checks the
          phone's location against these rules; changes apply to the next clock-in or clock-out.
        </p>

        <app-detail-section
          heading="Arena location"
          subtitle="Clock-ins within this circle count as inside. Click the map to move the centre, or drag the pin."
        >
          <app-geo-map
            label="Arena location map"
            height="300px"
            [center]="center()"
            [radius]="center() ? radiusM() : null"
            [editable]="canEdit()"
            (centerChange)="moveTo($event)"
          />
          @if (!located()) {
            <p role="note" class="text-[13px] leading-[1.45] text-muted">
              No location set: every clock-in's position counts as unknown, so the rule below
              applies to all of them.
            </p>
          }
          <div class="grid grid-cols-[repeat(auto-fit,minmax(150px,1fr))] gap-3">
            <mat-form-field>
              <mat-label>Latitude</mat-label>
              <input
                matInput
                inputmode="decimal"
                autocomplete="off"
                aria-describedby="att-location-error"
                [attr.aria-invalid]="!!p.location"
                [disabled]="!canEdit()"
                [value]="d.lat"
                (input)="set({ lat: $any($event.target).value })"
              />
            </mat-form-field>
            <mat-form-field>
              <mat-label>Longitude</mat-label>
              <input
                matInput
                inputmode="decimal"
                autocomplete="off"
                aria-describedby="att-location-error"
                [attr.aria-invalid]="!!p.location"
                [disabled]="!canEdit()"
                [value]="d.lng"
                (input)="set({ lng: $any($event.target).value })"
              />
            </mat-form-field>
            <mat-form-field>
              <mat-label>Radius</mat-label>
              <input
                matInput
                type="number"
                inputmode="numeric"
                [min]="limits.radiusM[0]"
                [max]="limits.radiusM[1]"
                aria-describedby="att-radius-error"
                [attr.aria-invalid]="!!p.radius"
                [disabled]="!canEdit()"
                [value]="d.radius"
                (input)="set({ radius: $any($event.target).value })"
              />
              <span matTextSuffix>m</span>
              <mat-hint>{{ limits.radiusM[0] }}–{{ limits.radiusM[1] }} m</mat-hint>
            </mat-form-field>
          </div>
          @if (p.location) {
            <p id="att-location-error" role="alert" class="text-[13px] leading-[1.4] text-danger">
              {{ p.location }}
            </p>
          }
          @if (p.radius) {
            <p id="att-radius-error" class="text-[13px] leading-[1.4] text-danger" role="alert">
              {{ p.radius }}
            </p>
          }
          <div>
            <button
              mat-stroked-button
              type="button"
              [disabled]="!canEdit() || !located()"
              (click)="clearLocation()"
            >
              <mat-icon aria-hidden="true">location_off</mat-icon>Clear location
            </button>
          </div>
        </app-detail-section>

        <app-detail-section
          heading="Outside the arena"
          subtitle="For a clock-in or clock-out outside the circle, or whose position is unknown: location off, no GPS fix, accuracy worse than the minimum below, or no arena location."
        >
          <mat-radio-group
            class="flex flex-col gap-3"
            aria-label="Outside the arena"
            aria-describedby="att-outside-error"
            [disabled]="!canEdit()"
            [value]="d.outsideRule"
            (change)="set({ outsideRule: $event.value })"
          >
            @for (o of outsideRules; track o.value) {
              <mat-radio-button [value]="o.value">
                <span class="flex flex-col gap-0.5">
                  <span class="text-[15px] leading-[1.3]">{{ o.label }}</span>
                  <span class="text-[13px] leading-[1.3] text-muted">{{ o.sub }}</span>
                </span>
              </mat-radio-button>
            }
          </mat-radio-group>
          @if (p.outsideRule) {
            <p id="att-outside-error" role="alert" class="text-[13px] leading-[1.4] text-danger">
              {{ p.outsideRule }}
            </p>
          }
        </app-detail-section>

        <app-detail-section heading="GPS" subtitle="How much the phone's position is trusted.">
          <mat-form-field class="max-w-72">
            <mat-label>Minimum GPS accuracy</mat-label>
            <input
              matInput
              type="number"
              inputmode="numeric"
              [min]="limits.minAccuracyM[0]"
              [max]="limits.minAccuracyM[1]"
              aria-describedby="att-accuracy-error"
              [attr.aria-invalid]="!!p.minAccuracy"
              [disabled]="!canEdit()"
              [value]="d.minAccuracy"
              (input)="set({ minAccuracy: $any($event.target).value })"
            />
            <span matTextSuffix>m</span>
            <mat-hint>A fix less precise than this counts as unknown</mat-hint>
          </mat-form-field>
          @if (p.minAccuracy) {
            <p id="att-accuracy-error" role="alert" class="text-[13px] leading-[1.4] text-danger">
              {{ p.minAccuracy }}
            </p>
          }
          <span class="text-[15px] leading-[1.3]" id="att-mock-label"
            >When the phone reports a fake (mock) location</span
          >
          <mat-radio-group
            class="flex flex-col gap-3"
            aria-labelledby="att-mock-label"
            [disabled]="!canEdit()"
            [value]="d.mockRule"
            (change)="set({ mockRule: $event.value })"
          >
            @for (o of mockRules; track o.value) {
              <mat-radio-button [value]="o.value">
                <span class="flex flex-col gap-0.5">
                  <span class="text-[15px] leading-[1.3]">{{ o.label }}</span>
                  <span class="text-[13px] leading-[1.3] text-muted">{{ o.sub }}</span>
                </span>
              </mat-radio-button>
            }
          </mat-radio-group>
        </app-detail-section>

        <app-detail-section
          heading="Forgotten clock-outs"
          subtitle="A clock-in left open longer than this is closed at clock-in + these hours and flagged for review."
        >
          <mat-form-field class="max-w-72">
            <mat-label>Close automatically after</mat-label>
            <input
              matInput
              type="number"
              inputmode="numeric"
              [min]="limits.maxOpenHours[0]"
              [max]="limits.maxOpenHours[1]"
              aria-describedby="att-hours-error"
              [attr.aria-invalid]="!!p.maxOpenHours"
              [disabled]="!canEdit()"
              [value]="d.maxOpenHours"
              (input)="set({ maxOpenHours: $any($event.target).value })"
            />
            <span matTextSuffix>hours</span>
            <mat-hint>{{ limits.maxOpenHours[0] }}–{{ limits.maxOpenHours[1] }} hours</mat-hint>
          </mat-form-field>
          @if (p.maxOpenHours) {
            <p id="att-hours-error" role="alert" class="text-[13px] leading-[1.4] text-danger">
              {{ p.maxOpenHours }}
            </p>
          }
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
export class AttendanceSettings {
  private readonly arena = inject(ArenaContext);
  protected readonly store = inject(AttendanceRulesStore);
  private readonly snack = inject(MatSnackBar);
  readonly closed = output<void>();

  protected readonly limits = ATTENDANCE_LIMITS;
  protected readonly outsideRules = OUTSIDE_RULES;
  protected readonly mockRules = MOCK_RULES;
  protected readonly canEdit = this.arena.canEdit;

  private readonly saved = computed(() => toDraft(this.store.rules() ?? DEFAULT_ATTENDANCE_RULES));
  /** The draft starts from (and follows) what the server holds. */
  protected readonly draft = linkedSignal<AttendanceDraft>(() => this.saved());
  protected readonly dirty = computed(
    () => !!this.store.rules() && !sameDraft(this.draft(), this.saved()),
  );
  private readonly problems = computed(() => draftProblems(this.draft()));
  /** A save was tried: every problem shows from then on (until Discard). */
  private readonly tried = signal(false);
  /** Problems on screen: "Block needs the location" at once, the rest after a save attempt. */
  protected readonly shownProblems = computed(() => {
    const all = this.problems();
    return this.tried() ? all : { outsideRule: all.outsideRule };
  });
  protected readonly located = computed(() => draftHasLocation(this.draft()));
  /** The centre on the map: the typed coordinates when they are valid numbers. */
  protected readonly center = computed<GeoPoint | null>(() => {
    const d = this.draft();
    const lat = Number(d.lat);
    const lng = Number(d.lng);
    if (
      d.lat.trim() === '' ||
      d.lng.trim() === '' ||
      !Number.isFinite(lat) ||
      !Number.isFinite(lng)
    ) {
      return null;
    }
    return Math.abs(lat) <= 90 && Math.abs(lng) <= 180 ? { lat, lng } : null;
  });
  protected readonly radiusM = computed(() => {
    const r = Number(this.draft().radius);
    return Number.isFinite(r) && r > 0 ? r : DEFAULT_RADIUS_M;
  });
  protected readonly summary = computed(() => {
    const r = this.store.rules();
    return r ? rulesSummary(r) : this.arena.current().name;
  });
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  constructor() {
    effect(() => {
      if (this.arena.current().id) void this.store.load();
    });
  }

  protected set(change: Partial<AttendanceDraft>): void {
    this.draft.update((d) => ({ ...d, ...change }));
    this.error.set('');
  }

  /** A click on the map or a drag of the pin. */
  protected moveTo(point: GeoPoint): void {
    if (!this.canEdit()) return;
    this.set({ lat: String(point.lat), lng: String(point.lng) });
  }

  /** No arena location (with Block chosen, the screen says to pick another rule first). */
  protected clearLocation(): void {
    this.set({ lat: '', lng: '' });
  }

  protected discard(): void {
    this.draft.set(this.saved());
    this.tried.set(false);
    this.error.set('');
  }

  protected async save(): Promise<void> {
    this.tried.set(true);
    const rules = fromDraft(this.draft());
    if (!rules) {
      this.error.set('Fix the values marked above, then save again');
      return;
    }
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.save(rules);
      this.tried.set(false);
      this.snack.open('Attendance settings saved · the next clock-in uses them', undefined, {
        duration: 3200,
      });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
