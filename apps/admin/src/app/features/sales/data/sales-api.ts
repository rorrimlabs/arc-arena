import { Service, inject } from '@angular/core';
import { dbError } from '../../../core/arena/arena-api';
import { AppError } from '../../../core/auth/auth-api';
import { Supabase } from '../../../core/supabase/supabase';
import { pushOps } from '../../../core/sync/push-ops';
import {
  Bill,
  BillDetail,
  BillKind,
  BillLine,
  BillPayment,
  PayMethod,
  PaymentStatus,
  billRef,
} from './sale.models';

/**
 * The arena's closed bills: read through arena_sales() / arena_sale() (owner level), voided as a
 * `session.void` / `group.void` op through sync_push — the same path, permission check and audit
 * record as the floor app. Tests provide SampleSalesApi.
 */
@Service({ factory: () => new SupabaseSalesApi() })
export abstract class SalesApi {
  /** Bills that closed in [from, to), newest first. */
  abstract list(arenaId: string, from: Date, to: Date): Promise<Bill[]>;
  abstract get(arenaId: string, id: string): Promise<BillDetail>;
  abstract void(arenaId: string, bill: Bill, reason: string): Promise<void>;
}

const SALES_MESSAGES: Readonly<Record<string, string>> = {
  not_found: 'That bill is not in the records. Refresh',
  invalid_range: 'Pick a shorter date range',
  forbidden: 'Only an owner can do that',
};

type Row = Record<string, unknown>;

export function toBill(r: Row): Bill {
  const kind: BillKind = r['kind'] === 'group' ? 'group' : 'single';
  const id = String(r['id']);
  const strings = (v: unknown) => ((v as string[] | null) ?? []).map(String);
  return {
    kind,
    id,
    ref: billRef(kind, id),
    at: String(r['at']),
    startedAt: String(r['started_at']),
    endedAt: (r['ended_at'] as string | null) ?? null,
    voided: r['status'] === 'voided',
    paymentStatus: (r['payment_status'] as PaymentStatus) ?? 'unpaid',
    customer: String(r['customer'] ?? 'Guest'),
    guest: r['guest'] === true,
    stations: strings(r['stations']),
    activities: strings(r['activities']),
    games: strings(r['games']),
    players: Number(r['players'] ?? 1),
    billedPaise: r['billed_paise'] == null ? null : Number(r['billed_paise']),
    paidPaise: Number(r['paid_paise'] ?? 0),
    refundedPaise: Number(r['refunded_paise'] ?? 0),
    methods: Object.fromEntries(
      Object.entries((r['methods'] as Record<string, number> | null) ?? {}).map(([m, v]) => [
        m,
        Number(v),
      ]),
    ) as Partial<Record<PayMethod, number>>,
    startedBy: (r['started_by'] as string | null) ?? null,
    voidReason: (r['void_reason'] as string | null) ?? null,
  };
}

function toDetail(r: Row): BillDetail {
  const voided = r['voided'] as Row | null;
  return {
    ...toBill(r),
    lines: ((r['lines'] as Row[] | null) ?? []).map((l): BillLine => ({
      player: l['player'] == null ? null : Number(l['player']),
      station: String(l['station'] ?? ''),
      activity: String(l['activity'] ?? ''),
      band: String(l['band'] ?? 'standard'),
      controllers: l['controllers'] == null ? null : Number(l['controllers']),
      billedMinutes: Number(l['billed_minutes'] ?? 0),
      amountPaise: Number(l['amount_paise'] ?? 0),
    })),
    payments: ((r['payments'] as Row[] | null) ?? []).map((p): BillPayment => ({
      id: String(p['id']),
      at: String(p['at']),
      amountPaise: Number(p['amount_paise']),
      method: p['method'] as PayMethod,
      refund: p['refund'] === true,
      reason: (p['reason'] as string | null) ?? null,
      by: (p['by'] as string | null) ?? null,
    })),
    voidRecord: voided
      ? { at: String(voided['at']), by: (voided['by'] as string | null) ?? null }
      : null,
  };
}

class SupabaseSalesApi extends SalesApi {
  private readonly supabase = inject(Supabase);

  async list(arenaId: string, from: Date, to: Date): Promise<Bill[]> {
    const client = await this.supabase.client();
    const { data, error } = await client.rpc('arena_sales', {
      p_arena: arenaId,
      p_from: from.toISOString(),
      p_to: to.toISOString(),
    });
    if (error) throw salesError(error);
    return (data as Row[]).map(toBill);
  }

  async get(arenaId: string, id: string): Promise<BillDetail> {
    const client = await this.supabase.client();
    const { data, error } = await client.rpc('arena_sale', { p_arena: arenaId, p_id: id });
    if (error) throw salesError(error);
    return toDetail(data as Row);
  }

  async void(arenaId: string, bill: Bill, reason: string): Promise<void> {
    const client = await this.supabase.client();
    try {
      // Through pushOps: the other devices hear of the void only once it is recorded.
      await pushOps(
        client,
        arenaId,
        [
          {
            kind: bill.kind === 'group' ? 'group.void' : 'session.void',
            payload:
              bill.kind === 'group'
                ? { group_id: bill.id, reason }
                : { session_id: bill.id, reason },
          },
        ],
        SALES_MESSAGES,
      );
    } catch (e) {
      throw e instanceof AppError && SALES_MESSAGES[e.code]
        ? new AppError(e.code, SALES_MESSAGES[e.code])
        : e;
    }
  }
}

function salesError(e: Parameters<typeof dbError>[0]): AppError {
  const error = dbError(e);
  return SALES_MESSAGES[error.code] ? new AppError(error.code, SALES_MESSAGES[error.code]) : error;
}
