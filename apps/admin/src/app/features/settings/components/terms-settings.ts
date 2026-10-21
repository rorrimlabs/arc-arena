import { DecimalPipe } from '@angular/common';
import { Component, computed, effect, inject, linkedSignal, output, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatFormField, MatHint, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatSnackBar } from '@angular/material/snack-bar';
import { isOwnerLevel } from '../../../core/arena/arena-api';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { Attempt } from '../../../core/sync/push-ops';
import { ConfirmDialog, ConfirmDialogData } from '../../../shared/confirm/confirm-dialog';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { formatDayYear } from '../../../shared/staff/staff-format';
import { formatIsoDate, formatTime } from '../../../shared/time/ist';
import {
  TERMS_LIMITS,
  TermsDraft,
  TermsStore,
  exemptFromTerms,
  termsParagraphs,
  termsProblems,
} from '../data/staff-terms';

/** "5 Oct 2026, 9:42 pm" (IST). */
function dateTime(at: string): string {
  return `${formatDayYear(formatIsoDate(at))}, ${formatTime(at)}`;
}

/**
 * Settings › Staff › Terms: the staff terms in force (title, version, text), who has accepted
 * them, and an editor to publish the next version (terms.publish, owner level). A published
 * version is never edited: publishing again adds version N+1, which everyone except owner level
 * must accept on the floor app before they continue working.
 */
@Component({
  selector: 'app-terms-settings',
  imports: [
    DetailPane,
    DetailSection,
    StatusPill,
    DecimalPipe,
    MatButton,
    MatFormField,
    MatLabel,
    MatHint,
    MatInput,
  ],
  template: `
    <app-detail-pane
      crumb="Settings / Staff / Terms"
      icon="gavel"
      heading="Staff terms"
      [subtitle]="summary()"
      (closed)="closed.emit()"
    >
      @if (store.loadError(); as error) {
        <app-detail-section>
          <p role="alert" class="text-[13px] leading-[1.45] text-danger">
            The staff terms couldn't load: {{ error }}
          </p>
        </app-detail-section>
      } @else if (!store.data()) {
        <app-detail-section>
          <p class="text-[13px] leading-[1.45] text-muted">Loading…</p>
        </app-detail-section>
      } @else {
        @if (current(); as t) {
          <app-detail-section
            [heading]="t.title"
            [subtitle]="'Version ' + t.version + ' · published ' + published()"
          >
            <div
              class="flex max-h-[420px] flex-col gap-3 overflow-y-auto rounded-panel border border-border p-4"
              role="region"
              tabindex="0"
              aria-label="Terms in force"
            >
              @for (para of paragraphs(); track $index) {
                <p class="text-sm leading-[1.5] whitespace-pre-line">{{ para }}</p>
              }
            </div>
          </app-detail-section>

          <app-detail-section
            heading="Accepted"
            [subtitle]="acceptedCount() + ' of ' + rows().length + ' staff have accepted version ' + t.version + '. Owners don’t need to.'"
          >
            <div class="-mx-2 overflow-x-auto">
              <table class="w-full border-collapse text-left text-[13px] leading-[1.3]">
                <caption class="sr-only">
                  Acceptance of version {{ t.version }}
                </caption>
                <thead>
                  <tr class="border-b border-border text-xs text-muted">
                    <th scope="col" class="px-2 py-2 font-medium">Staff</th>
                    <th scope="col" class="px-2 py-2 font-medium">Accepted</th>
                  </tr>
                </thead>
                <tbody>
                  @for (r of rows(); track r.id) {
                    <tr class="border-b border-border last:border-b-0">
                      <th scope="row" class="px-2 py-2 font-medium">{{ r.name }}</th>
                      <td class="px-2 py-2 whitespace-nowrap">
                        @if (r.acceptedAt) {
                          {{ r.acceptedAt }}
                        } @else {
                          <app-status-pill tone="warning">Waiting</app-status-pill>
                        }
                      </td>
                    </tr>
                  } @empty {
                    <tr>
                      <td colspan="2" class="px-2 py-6 text-center text-muted">No staff yet.</td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
          </app-detail-section>
        } @else {
          <app-detail-section heading="No terms yet">
            <p class="text-sm leading-[1.45] text-muted">
              Write the venue's terms for staff below. Once you publish them, everyone except
              owners is asked to read and accept them on the floor app before they continue
              working.
            </p>
          </app-detail-section>
        }

        @let d = draft();
        @let p = shownProblems();
        <app-detail-section
          [heading]="current() ? 'Publish a new version' : 'Write the terms'"
          [subtitle]="
            current()
              ? 'Edit the text and publish it as version ' + next() + '. Published versions are kept as they were.'
              : 'Plain text. Leave a blank line between paragraphs.'
          "
        >
          <mat-form-field>
            <mat-label>Title</mat-label>
            <input
              matInput
              autocomplete="off"
              maxlength="120"
              [attr.aria-invalid]="!!p.title"
              [attr.aria-describedby]="p.title ? 'terms-title-error' : null"
              [disabled]="!canPublish()"
              [value]="d.title"
              (input)="set({ title: $any($event.target).value })"
            />
          </mat-form-field>
          @if (p.title) {
            <p id="terms-title-error" role="alert" class="text-[13px] leading-[1.4] text-danger">
              {{ p.title }}
            </p>
          }
          <mat-form-field>
            <mat-label>Text</mat-label>
            <textarea
              matInput
              rows="18"
              [attr.maxlength]="limit"
              [attr.aria-invalid]="!!p.body"
              [attr.aria-describedby]="p.body ? 'terms-body-error' : null"
              [disabled]="!canPublish()"
              [value]="d.body"
              (input)="set({ body: $any($event.target).value })"
            ></textarea>
            <mat-hint align="end">{{ d.body.length | number }} / {{ limit | number }}</mat-hint>
          </mat-form-field>
          @if (p.body) {
            <p id="terms-body-error" role="alert" class="text-[13px] leading-[1.4] text-danger">
              {{ p.body }}
            </p>
          }
          @if (!canPublish()) {
            <p class="text-[13px] leading-[1.4] text-muted">Only an owner can publish the terms.</p>
          }
          @if (error()) {
            <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
          }
          <div class="flex flex-wrap gap-2">
            <button
              mat-flat-button
              type="button"
              [disabled]="!canPublish() || busy() || unchanged() || invalid()"
              (click)="publish()"
            >
              Publish version {{ next() }}
            </button>
            @if (edited()) {
              <button mat-button type="button" [disabled]="busy()" (click)="discard()">
                Discard
              </button>
            }
          </div>
        </app-detail-section>
      }
    </app-detail-pane>
  `,
})
export class TermsSettings {
  protected readonly store = inject(TermsStore);
  private readonly arena = inject(ArenaContext);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);
  readonly closed = output<void>();

  protected readonly limit = TERMS_LIMITS.body;
  /** terms.publish is owner level (role owner, or money / reports). */
  protected readonly canPublish = computed(() => {
    const m = this.arena.currentMembership();
    return !!m && isOwnerLevel(m);
  });

  protected readonly current = this.store.current;
  protected readonly next = computed(() => (this.current()?.version ?? 0) + 1);
  protected readonly published = computed(() => {
    const t = this.current();
    return t ? formatDayYear(formatIsoDate(t.publishedAt)) : '';
  });
  protected readonly paragraphs = computed(() => termsParagraphs(this.current()?.body ?? ''));
  protected readonly summary = computed(() => {
    const t = this.current();
    if (t) return `Version ${t.version} in force since ${this.published()}`;
    return this.store.data() ? 'Not published yet' : this.arena.current().name;
  });

  /** Active members who must accept (not owner level), with when they accepted this version. */
  protected readonly rows = computed(() => {
    const t = this.current();
    const accepted = this.store.acceptedOf();
    return (this.store.data()?.members ?? [])
      .filter((m) => m.active && !exemptFromTerms(m))
      .map((m) => {
        const a = accepted.get(m.id);
        return {
          id: m.id,
          name: m.name,
          acceptedAt: a && t && a.version === t.version ? dateTime(a.acceptedAt) : '',
        };
      });
  });
  protected readonly acceptedCount = computed(() => this.rows().filter((r) => r.acceptedAt).length);

  private readonly start = computed<TermsDraft>(() => ({
    title: this.current()?.title ?? 'Terms and conditions',
    body: this.current()?.body ?? '',
  }));
  protected readonly draft = linkedSignal<TermsDraft>(() => this.start());
  protected readonly edited = computed(
    () => this.draft().title !== this.start().title || this.draft().body !== this.start().body,
  );
  /** The same text as the version in force (trimmed): nothing to publish. */
  protected readonly unchanged = computed(() => {
    const t = this.current();
    const d = this.draft();
    return !!t && d.title.trim() === t.title.trim() && d.body.trim() === t.body.trim();
  });
  protected readonly invalid = computed(() => Object.keys(termsProblems(this.draft())).length > 0);
  private readonly tried = signal(false);
  protected readonly shownProblems = computed(() =>
    this.tried() || this.edited() ? termsProblems(this.draft()) : {},
  );
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  constructor() {
    // Acceptances arrive from the floor app: read again each time the tab opens.
    effect(() => {
      if (this.arena.current().id) void this.store.load(true);
    });
  }

  protected set(change: Partial<TermsDraft>): void {
    this.draft.update((d) => ({ ...d, ...change }));
    this.error.set('');
  }

  protected discard(): void {
    this.draft.set(this.start());
    this.tried.set(false);
    this.error.set('');
  }

  /** One publish's ids: a resend after a lost answer replays instead of adding a version. */
  private attempt = new Attempt();

  protected publish(): void {
    this.tried.set(true);
    if (this.invalid() || this.unchanged()) return;
    const version = this.next();
    this.dialog
      .open<ConfirmDialog, ConfirmDialogData, boolean>(ConfirmDialog, {
        data: {
          title: `Publish version ${version}?`,
          message: `Everyone except owners must read and accept version ${version} on the floor app before they can continue working.`,
          confirm: 'Publish',
        },
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe(async (yes) => {
        if (!yes) return;
        this.busy.set(true);
        this.error.set('');
        try {
          const published = await this.store.publish(this.draft(), this.attempt);
          this.attempt = new Attempt();
          this.tried.set(false);
          this.snack.open(`Version ${published || version} published`, undefined, {
            duration: 3200,
          });
        } catch (e) {
          this.attempt.settle(e);
          this.error.set(toAppError(e).message);
        } finally {
          this.busy.set(false);
        }
      });
  }
}
