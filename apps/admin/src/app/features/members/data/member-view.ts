import { Customer, Play, Visit, playMinutes } from '../../../core/floor/floor.models';
import { istDayStart } from '../../../shared/time/ist';

export interface MemberSummary {
  readonly customer: Customer;
  /** Bills (not voided) in the history window. */
  readonly visits: number;
  readonly minutes: number;
  /** Billed over the last 30 days (finished, not voided bills). */
  readonly spent30Paise: number;
  /** Latest visit: the customer record's, or the newest bill's start. */
  readonly lastVisit: string | null;
  /** Game id → minutes. */
  readonly games: ReadonlyMap<string, number>;
}

export function summarizeMembers(
  customers: readonly Customer[],
  visits: readonly Visit[],
  plays: readonly Play[],
  now: Date,
): MemberSummary[] {
  const since30 = istDayStart(now, 29).getTime();
  const byCustomer = new Map<string, Visit[]>();
  for (const v of visits) {
    if (v.status === 'voided') continue;
    const list = byCustomer.get(v.customerId) ?? [];
    list.push(v);
    byCustomer.set(v.customerId, list);
  }
  const playsBy = new Map<string, Play[]>();
  for (const p of plays) {
    if (p.billStatus === 'voided') continue;
    const list = playsBy.get(p.customerId) ?? [];
    list.push(p);
    playsBy.set(p.customerId, list);
  }
  return customers
    .map((customer) => {
      const vs = byCustomer.get(customer.id) ?? [];
      const ps = playsBy.get(customer.id) ?? [];
      const games = new Map<string, number>();
      for (const p of ps) {
        if (p.gameId) games.set(p.gameId, (games.get(p.gameId) ?? 0) + playMinutes(p, now));
      }
      const newest =
        vs
          .map((v) => v.startedAt)
          .sort()
          .at(-1) ?? null;
      const lastVisit =
        [customer.lastVisitAt, newest]
          .filter((x): x is string => !!x)
          .sort()
          .at(-1) ?? null;
      return {
        customer,
        visits: vs.length,
        minutes: ps.reduce((n, p) => n + playMinutes(p, now), 0),
        spent30Paise: vs
          .filter((v) => Date.parse(v.startedAt) >= since30)
          .reduce((n, v) => n + (v.billedPaise ?? 0), 0),
        lastVisit,
        games,
      };
    })
    .sort((a, b) => (b.lastVisit ?? '').localeCompare(a.lastVisit ?? ''));
}

/** "98••• ••873": enough to recognise a number, not to copy it. */
export function maskPhone(phone: string | null): string {
  if (!phone) return 'No phone';
  const digits = phone.replace(/\D/g, '');
  if (digits.length < 6) return '•••••';
  return `${digits.slice(0, 2)}••• ••${digits.slice(-3)}`;
}

/** "Today", "Yesterday", "12 days ago" (IST calendar days), or "—". */
export function daysAgo(at: string | null, now: Date): string {
  if (!at) return '—';
  const d = Math.round(
    (istDayStart(now).getTime() - istDayStart(new Date(at)).getTime()) / 86_400_000,
  );
  return d <= 0 ? 'Today' : d === 1 ? 'Yesterday' : `${d} days ago`;
}

export function matchesMember(c: Customer, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  const digits = q.replace(/\D/g, '');
  return (
    c.name.toLowerCase().includes(q) ||
    (!!digits && !!c.phone && c.phone.replace(/\D/g, '').includes(digits))
  );
}
