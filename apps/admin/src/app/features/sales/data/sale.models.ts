import { PillTone } from '../../../shared/status-pill/status-pill';
import { formatRupees } from '../../../shared/money/rupees.pipe';
import { istDayStart } from '../../../shared/time/ist';

export type BillKind = 'single' | 'group';
export type PayMethod = 'cash' | 'upi' | 'card' | 'other';
export type PaymentStatus = 'unpaid' | 'partial' | 'paid' | 'waived';

/** A closed bill (arena_sales): one single session or one group, completed or voided. */
export interface Bill {
  readonly kind: BillKind;
  readonly id: string;
  /** Short display reference (`S-3F9A2C`, `G-71B0E4`); bills have no invoice number yet. */
  readonly ref: string;
  /** When it closed (ended, or voided while it ran). UTC ISO. */
  readonly at: string;
  readonly startedAt: string;
  readonly endedAt: string | null;
  readonly voided: boolean;
  readonly paymentStatus: PaymentStatus;
  readonly customer: string;
  readonly guest: boolean;
  readonly stations: readonly string[];
  readonly activities: readonly string[];
  readonly games: readonly string[];
  readonly players: number;
  /** The final bill after cash rounding; null for a bill voided before it ended. */
  readonly billedPaise: number | null;
  /** Net collected (payments minus refunds). */
  readonly paidPaise: number;
  readonly refundedPaise: number;
  /** Net collected per payment method. */
  readonly methods: Readonly<Partial<Record<PayMethod, number>>>;
  readonly startedBy: string | null;
  readonly voidReason: string | null;
}

export interface BillLine {
  /** Group player number; null on a single session. */
  readonly player: number | null;
  readonly station: string;
  readonly activity: string;
  readonly band: string;
  readonly controllers: number | null;
  readonly billedMinutes: number;
  readonly amountPaise: number;
}

export interface BillPayment {
  readonly id: string;
  readonly at: string;
  /** Refunds are negative. */
  readonly amountPaise: number;
  readonly method: PayMethod;
  readonly refund: boolean;
  readonly reason: string | null;
  readonly by: string | null;
}

/** A bill in full (arena_sale). */
export interface BillDetail extends Bill {
  readonly lines: readonly BillLine[];
  readonly payments: readonly BillPayment[];
  readonly voidRecord: { readonly at: string; readonly by: string | null } | null;
}

export type SalesRange = 'today' | 'yesterday' | '7d' | '30d';

export const SALES_RANGES: readonly { readonly key: SalesRange; readonly label: string }[] = [
  { key: 'today', label: 'Today' },
  { key: 'yesterday', label: 'Yesterday' },
  { key: '7d', label: '7 days' },
  { key: '30d', label: '30 days' },
];

/** The design's method chips (Card and Other bills are still listed and totalled). */
export const METHOD_FILTERS: readonly { readonly key: PayMethod; readonly label: string }[] = [
  { key: 'upi', label: 'UPI' },
  { key: 'cash', label: 'Cash' },
];

export const VOID_REASONS = [
  'Wrong amount',
  'Wrong station',
  'Duplicate bill',
  'Refund to customer',
] as const;

const METHOD_LABELS: Readonly<Record<PayMethod, string>> = {
  upi: 'UPI',
  cash: 'Cash',
  card: 'Card',
  other: 'Other',
};

export function methodName(method: PayMethod): string {
  return METHOD_LABELS[method] ?? method;
}

export function asRange(value: string | undefined): SalesRange {
  return SALES_RANGES.some((r) => r.key === value) ? (value as SalesRange) : 'today';
}

export function asMethod(value: string | undefined): PayMethod | null {
  return METHOD_FILTERS.some((m) => m.key === value) ? (value as PayMethod) : null;
}

/** [from, to) of a range in IST calendar days. */
export function rangeBounds(range: SalesRange, now: Date): { from: Date; to: Date } {
  const tomorrow = istDayStart(now, -1);
  switch (range) {
    case 'today':
      return { from: istDayStart(now), to: tomorrow };
    case 'yesterday':
      return { from: istDayStart(now, 1), to: istDayStart(now) };
    case '7d':
      return { from: istDayStart(now, 6), to: tomorrow };
    case '30d':
      return { from: istDayStart(now, 29), to: tomorrow };
  }
}

export function billRef(kind: BillKind, id: string): string {
  return (kind === 'group' ? 'G-' : 'S-') + id.replace(/-/g, '').slice(0, 6).toUpperCase();
}

export function playedMinutes(bill: Bill): number {
  const end = bill.endedAt ?? bill.at;
  return Math.max(0, Math.round((Date.parse(end) - Date.parse(bill.startedAt)) / 60_000));
}

/** Methods money was collected by (net above zero), largest first. */
export function paidMethods(bill: Bill): PayMethod[] {
  return (Object.entries(bill.methods) as [PayMethod, number][])
    .filter(([, net]) => net > 0)
    .sort((a, b) => b[1] - a[1])
    .map(([m]) => m);
}

/** Still owed on a live bill (0 when paid, waived or voided). */
export function duePaise(bill: Bill): number {
  if (bill.voided || bill.paymentStatus === 'waived') return 0;
  return Math.max(0, (bill.billedPaise ?? 0) - bill.paidPaise);
}

/** The bill's state in a list row / detail chip: void, waived, unpaid, part paid, or how it was paid. */
export function billState(bill: Bill): { label: string; tone: PillTone | null } {
  if (bill.voided) return { label: 'Void', tone: 'danger' };
  if (bill.paymentStatus === 'waived') return { label: 'Waived', tone: 'info' };
  if (bill.paymentStatus === 'unpaid') return { label: 'Unpaid', tone: 'warning' };
  if (bill.paymentStatus === 'partial') return { label: 'Part paid', tone: 'warning' };
  const methods = paidMethods(bill);
  return { label: methods.length === 1 ? methodName(methods[0]) : 'Split', tone: null };
}

export interface SalesSummary {
  readonly count: number;
  /** Net collected on the bills that count (not voided). */
  readonly takingsPaise: number;
  readonly byMethod: Readonly<Record<PayMethod, number>>;
  readonly duePaise: number;
}

/** Voided bills drop out of takings; everything else counts what was actually collected. */
export function summarize(bills: readonly Bill[]): SalesSummary {
  const byMethod: Record<PayMethod, number> = { upi: 0, cash: 0, card: 0, other: 0 };
  let count = 0;
  let takings = 0;
  let due = 0;
  for (const b of bills) {
    if (b.voided) continue;
    count++;
    takings += b.paidPaise;
    due += duePaise(b);
    for (const [m, net] of Object.entries(b.methods) as [PayMethod, number][]) byMethod[m] += net;
  }
  return { count, takingsPaise: takings, byMethod, duePaise: due };
}

/** "₹48,120 · 26 bills · UPI ₹30,800 · Cash ₹17,320" (+ Card / Other / Due when present). */
export function summaryLine(s: SalesSummary): string {
  const parts = [
    formatRupees(s.takingsPaise),
    `${s.count} bill${s.count === 1 ? '' : 's'}`,
    `UPI ${formatRupees(s.byMethod.upi)}`,
    `Cash ${formatRupees(s.byMethod.cash)}`,
  ];
  if (s.byMethod.card) parts.push(`Card ${formatRupees(s.byMethod.card)}`);
  if (s.byMethod.other) parts.push(`Other ${formatRupees(s.byMethod.other)}`);
  if (s.duePaise) parts.push(`Due ${formatRupees(s.duePaise)}`);
  return parts.join(' · ');
}

export function matchesSearch(bill: Bill, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  return [bill.ref, bill.customer, bill.startedBy ?? '', ...bill.stations, ...bill.games].some(
    (x) => x.toLowerCase().includes(q),
  );
}
