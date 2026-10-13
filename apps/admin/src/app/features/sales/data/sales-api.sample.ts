import { AppError } from '../../../core/auth/auth-api';
import { istDayStart } from '../../../shared/time/ist';
import { SalesApi } from './sales-api';
import { Bill, BillDetail, BillKind, PayMethod, PaymentStatus, billRef } from './sale.models';

interface Spec {
  readonly id: string;
  readonly kind?: BillKind;
  /** IST day (0 = today) and hh:mm the bill closed. */
  readonly day: number;
  readonly close: string;
  readonly minutes: number;
  readonly customer: string;
  readonly station: string;
  readonly game?: string;
  readonly players?: number;
  readonly billed: number;
  readonly payments: readonly (readonly [PayMethod, number])[];
  readonly status?: PaymentStatus;
  readonly voidReason?: string;
}

/** Sample bills in rupees, closing at fixed IST times relative to `now` (today first). */
const SPECS: readonly Spec[] = [
  {
    id: '3f9a2c10-0000-4000-8000-000000000001',
    day: 0,
    close: '18:40',
    minutes: 60,
    customer: 'Kiran Rao',
    station: 'HEX',
    game: 'EA SPORTS FC 25',
    players: 2,
    billed: 240,
    payments: [['upi', 240]],
  },
  {
    id: '71b0e4aa-0000-4000-8000-000000000002',
    kind: 'group',
    day: 0,
    close: '17:15',
    minutes: 90,
    customer: 'Aditya Shah',
    station: 'VOID',
    game: 'Tekken 8',
    players: 4,
    billed: 720,
    payments: [
      ['upi', 500],
      ['cash', 220],
    ],
  },
  {
    id: 'c41d7e22-0000-4000-8000-000000000003',
    day: 0,
    close: '15:05',
    minutes: 30,
    customer: 'Guest',
    station: 'GHOST',
    billed: 60,
    payments: [['cash', 60]],
  },
  {
    id: '0e55b981-0000-4000-8000-000000000004',
    day: 0,
    close: '13:30',
    minutes: 120,
    customer: 'Meera Pillai',
    station: 'RIFT',
    game: 'Gran Turismo 7',
    billed: 360,
    payments: [['upi', 200]],
    status: 'partial',
  },
  {
    id: 'a8c3f017-0000-4000-8000-000000000005',
    day: 1,
    close: '21:10',
    minutes: 60,
    customer: 'Kiran Rao',
    station: 'HEX',
    game: 'Mortal Kombat 1',
    billed: 120,
    payments: [['cash', 120]],
    voidReason: 'Duplicate bill',
  },
  {
    id: '5d2e9b44-0000-4000-8000-000000000006',
    day: 1,
    close: '19:00',
    minutes: 60,
    customer: 'Rahul Verma',
    station: 'VOID',
    game: 'EA SPORTS FC 25',
    billed: 120,
    payments: [['upi', 120]],
  },
  {
    id: 'e7f61c03-0000-4000-8000-000000000007',
    day: 4,
    close: '16:20',
    minutes: 60,
    customer: 'Sana Khan',
    station: 'VR Bay',
    billed: 300,
    payments: [],
    status: 'waived',
  },
  {
    id: '9b8a7c6d-0000-4000-8000-000000000008',
    day: 12,
    close: '20:45',
    minutes: 90,
    customer: 'Aditya Shah',
    station: 'Pool Table 1',
    billed: 270,
    payments: [['card', 270]],
  },
];

function build(spec: Spec, now: Date, n: number): BillDetail {
  const [h, m] = spec.close.split(':').map(Number);
  const at = new Date(istDayStart(now, spec.day).getTime() + (h * 60 + m) * 60_000);
  const startedAt = new Date(at.getTime() - spec.minutes * 60_000);
  const kind = spec.kind ?? 'single';
  const methods: Partial<Record<PayMethod, number>> = {};
  for (const [method, rupees] of spec.payments) {
    methods[method] = (methods[method] ?? 0) + rupees * 100;
  }
  const paid = spec.payments.reduce((sum, [, rupees]) => sum + rupees * 100, 0);
  const bill: Bill = {
    kind,
    id: spec.id,
    ref: billRef(kind, spec.id),
    at: at.toISOString(),
    startedAt: startedAt.toISOString(),
    endedAt: at.toISOString(),
    voided: !!spec.voidReason,
    paymentStatus: spec.status ?? 'paid',
    customer: spec.customer,
    guest: spec.customer === 'Guest',
    stations: [spec.station],
    activities: [spec.station.startsWith('Pool') ? 'Pool' : 'PlayStation 5'],
    games: spec.game ? [spec.game] : [],
    players: spec.players ?? 1,
    billedPaise: spec.billed * 100,
    paidPaise: paid,
    refundedPaise: 0,
    methods,
    startedBy: 'Priya Nair',
    voidReason: spec.voidReason ?? null,
  };
  return {
    ...bill,
    lines: [
      {
        player: kind === 'group' ? 1 : null,
        station: spec.station,
        activity: bill.activities[0],
        band: 'standard',
        controllers: spec.players ?? 1,
        billedMinutes: spec.minutes,
        amountPaise: spec.billed * 100,
      },
    ],
    payments: spec.payments.map(([method, rupees], i) => ({
      id: `${spec.id}-p${i}`,
      at: at.toISOString(),
      amountPaise: rupees * 100,
      method,
      refund: false,
      reason: null,
      by: n % 2 ? 'Rohan Das' : 'Priya Nair',
    })),
    voidRecord: spec.voidReason ? { at: at.toISOString(), by: 'Arjun Mehra' } : null,
  };
}

/** Deterministic bills for tests and offline previews; voids change them in memory. */
export class SampleSalesApi extends SalesApi {
  readonly bills: BillDetail[];
  /** Set to make the next call fail with this code. */
  failNext: string | null = null;

  constructor(now: Date) {
    super();
    this.bills = SPECS.map((spec, i) => build(spec, now, i));
  }

  async list(_arenaId: string, from: Date, to: Date): Promise<Bill[]> {
    this.fail();
    return this.bills
      .filter((b) => Date.parse(b.at) >= from.getTime() && Date.parse(b.at) < to.getTime())
      .sort((a, b) => Date.parse(b.at) - Date.parse(a.at));
  }

  async get(_arenaId: string, id: string): Promise<BillDetail> {
    this.fail();
    const bill = this.bills.find((b) => b.id === id);
    if (!bill) throw new AppError('not_found', 'That bill is not in the records. Refresh');
    return bill;
  }

  async void(_arenaId: string, bill: Bill, reason: string): Promise<void> {
    this.fail();
    const i = this.bills.findIndex((b) => b.id === bill.id);
    if (i < 0) throw new AppError('not_found', 'That bill is not in the records. Refresh');
    if (this.bills[i].voided) return;
    this.bills[i] = {
      ...this.bills[i],
      voided: true,
      voidReason: reason,
      voidRecord: { at: new Date().toISOString(), by: 'Arjun Mehra' },
    };
  }

  private fail(): void {
    const code = this.failNext;
    if (!code) return;
    this.failNext = null;
    throw new AppError(code, code === 'forbidden' ? 'Only an owner can do that' : code);
  }
}
