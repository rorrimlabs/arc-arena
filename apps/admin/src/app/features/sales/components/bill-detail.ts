import { Clipboard } from '@angular/cdk/clipboard';
import { Component, computed, inject, input, output, resource } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatProgressBar } from '@angular/material/progress-bar';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailRow } from '../../../shared/list-detail/detail-row';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { formatRupees } from '../../../shared/money/rupees.pipe';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { formatDate, formatMinutes, formatTime } from '../../../shared/time/ist';
import { SalesStore } from '../data/sales-store';
import {
  Bill,
  BillDetail as Detail,
  BillLine,
  BillPayment,
  SalesRange,
  billState,
  duePaise,
  methodName,
  paidMethods,
  playedMinutes,
} from '../data/sale.models';
import { VoidDialog, VoidDialogData } from '../dialogs/void-dialog';

/**
 * Design: `if (p === 'sales')` detail. The list's summary shows at once; the charge lines,
 * payments and void record load from arena_sale(). Share copies a plain-text receipt; Void asks
 * for a reason (owner level, as the server requires).
 */
@Component({
  selector: 'app-bill-detail',
  imports: [DetailPane, DetailSection, DetailRow, StatusPill, MatButton, MatIcon, MatProgressBar],
  template: `
    @let b = shown();
    <app-detail-pane
      [crumb]="'Sales / ' + b.ref"
      icon="receipt_long"
      [heading]="b.ref"
      [subtitle]="when()"
      (closed)="closed.emit()"
    >
      @if (!b.voided) {
        <div actions class="arena-compact flex gap-2">
          <button mat-stroked-button type="button" (click)="share()">
            <mat-icon aria-hidden="true">share</mat-icon>Share
          </button>
          <button mat-button type="button" class="danger-action" (click)="voidBill()">
            <mat-icon aria-hidden="true">block</mat-icon>Void
          </button>
        </div>
      }
      <app-status-pill chip [tone]="chip().tone">{{ chip().label }}</app-status-pill>
      <span
        big
        class="flex-none font-display text-[32px] leading-none font-bold tabular-nums"
        [class.text-muted]="b.voided"
        >{{ b.voided ? '₹0' : rupees(b.billedPaise ?? 0) }}</span
      >

      <app-detail-section heading="Session">
        <app-detail-row label="Station" [value]="stationLine()" />
        <app-detail-row label="Game" [value]="b.games.join(', ') || '—'" />
        <app-detail-row label="Players" [value]="b.players.toString()" />
        <app-detail-row label="Time played" [value]="minutes(played())" />
        <app-detail-row label="Member" [value]="b.customer" />
        <app-detail-row label="Started by" [value]="b.startedBy ?? '—'" />
      </app-detail-section>

      @if (detail.isLoading() && !detail.hasValue()) {
        <mat-progress-bar mode="indeterminate" aria-label="Loading the bill" />
      }
      @if (detail.error(); as error) {
        <app-detail-section>
          <p role="alert" class="text-sm text-danger">{{ message(error) }}</p>
          <div>
            <button mat-stroked-button type="button" (click)="detail.reload()">Try again</button>
          </div>
        </app-detail-section>
      }
      @if (full(); as d) {
        <app-detail-section heading="Amount">
          @for (line of d.lines; track $index) {
            <app-detail-row [label]="lineLabel(line)" [value]="rupees(line.amountPaise)" />
          }
          @if (rounding(); as r) {
            <app-detail-row label="Rounding" [value]="signed(r)" />
          }
          <div class="h-px bg-border" role="presentation"></div>
          <app-detail-row label="Total" [value]="rupees(d.billedPaise ?? 0)" [strong]="true" />
          @if (d.paymentStatus === 'waived' && !d.voided) {
            <p class="text-[13px] leading-[1.45] text-muted">Waived · no payment due.</p>
          }
          @if (d.voided) {
            <p class="text-[13px] leading-[1.45] text-muted">{{ voidNote() }}</p>
          }
        </app-detail-section>

        <app-detail-section heading="Payments">
          @for (p of d.payments; track p.id) {
            <app-detail-row [label]="paymentLabel(p)" [value]="signed(p.amountPaise)" />
          } @empty {
            <p class="text-[13px] leading-[1.45] text-muted">No payments recorded.</p>
          }
          @if (d.payments.length) {
            <div class="h-px bg-border" role="presentation"></div>
            <app-detail-row label="Collected" [value]="rupees(d.paidPaise)" [strong]="true" />
          }
          @if (due(); as owed) {
            <app-detail-row label="Due" [value]="rupees(owed)" />
          }
          @if (d.voided && d.paidPaise > 0) {
            <p class="text-[13px] leading-[1.45] text-warning">
              {{ rupees(d.paidPaise) }} was collected on this bill. Voiding does not refund it.
            </p>
          }
        </app-detail-section>
      }
    </app-detail-pane>
  `,
})
export class BillDetail {
  private readonly store = inject(SalesStore);
  private readonly arena = inject(ArenaContext);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);
  private readonly clipboard = inject(Clipboard);

  /** The list's summary of the bill (shown until the full bill loads). */
  readonly bill = input.required<Bill>();
  readonly range = input.required<SalesRange>();
  readonly closed = output<void>();

  protected readonly detail = resource({
    params: () => ({
      arena: this.arena.current().id,
      id: this.bill().id,
      revision: this.store.revision(),
    }),
    loader: ({ params }) => this.store.get(params.id),
  });
  /** The loaded bill, once it matches the selected one. */
  protected readonly full = computed<Detail | undefined>(() => {
    const d = this.detail.hasValue() ? this.detail.value() : undefined;
    return d?.id === this.bill().id ? d : undefined;
  });
  protected readonly shown = computed<Bill>(() => this.full() ?? this.bill());

  protected readonly rupees = formatRupees;
  protected readonly minutes = formatMinutes;
  protected readonly chip = computed(() => {
    const b = this.shown();
    const state = billState(b);
    if (state.tone) return { label: state.label, tone: state.tone };
    return { label: `Paid · ${state.label}`, tone: 'primary' as const };
  });
  protected readonly when = computed(
    () => `${formatDate(this.shown().at)}, ${formatTime(this.shown().at)}`,
  );
  protected readonly played = computed(() => playedMinutes(this.shown()));
  protected readonly stationLine = computed(() => {
    const b = this.shown();
    const where = b.stations.join(', ') || '—';
    return b.activities.length ? `${where} · ${b.activities.join(', ')}` : where;
  });
  protected readonly due = computed(() => duePaise(this.shown()));
  /** Bill-level cash rounding: the final bill minus the sum of its lines. */
  protected readonly rounding = computed(() => {
    const d = this.full();
    if (!d || d.billedPaise == null || !d.lines.length) return 0;
    return d.billedPaise - d.lines.reduce((sum, l) => sum + l.amountPaise, 0);
  });
  protected readonly voidNote = computed(() => {
    const d = this.full();
    if (!d) return '';
    const by = d.voidRecord?.by ? ` · by ${d.voidRecord.by}` : '';
    const at = d.voidRecord ? `, ${formatDate(d.voidRecord.at)}` : '';
    return `Voided · ${d.voidReason ?? 'no reason given'}${by}${at}`;
  });

  protected lineLabel(line: BillLine): string {
    const who = line.player != null ? `Player ${line.player} · ` : '';
    const band = line.band === 'happy' ? ' · happy hour' : '';
    return `${who}${line.station} · ${formatMinutes(line.billedMinutes)}${band}`;
  }

  protected paymentLabel(p: BillPayment): string {
    const kind = p.refund ? `${methodName(p.method)} refund` : methodName(p.method);
    const by = p.by ? ` · ${p.by}` : '';
    return `${kind} · ${formatTime(p.at)}${by}`;
  }

  protected signed(paise: number): string {
    return paise < 0 ? '−' + formatRupees(-paise) : formatRupees(paise);
  }

  protected message(error: unknown): string {
    return toAppError(error).message;
  }

  protected share(): void {
    const b = this.shown();
    const paid = paidMethods(b).map(methodName).join(' + ');
    const lines = [
      `${this.arena.current().name} · ${b.ref}`,
      this.when(),
      `${this.stationLine()} · ${formatMinutes(this.played())}`,
      `Total ${formatRupees(b.billedPaise ?? 0)}${paid ? ` · Paid by ${paid}` : ''}`,
    ];
    const copied = this.clipboard.copy(lines.join('\n'));
    this.snack.open(
      copied ? `Receipt for ${b.ref} copied` : 'Could not copy the receipt',
      undefined,
      { duration: 3200 },
    );
  }

  protected voidBill(): void {
    const bill = this.shown();
    this.dialog
      .open<VoidDialog, VoidDialogData, boolean>(VoidDialog, {
        data: { bill, range: this.range() },
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((voided) => {
        if (voided) this.snack.open(`${bill.ref} voided`, undefined, { duration: 3200 });
      });
  }
}
