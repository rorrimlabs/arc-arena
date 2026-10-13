import { TestBed } from '@angular/core/testing';
import { describe, expect, it } from 'vitest';
import { AuthApi } from '../app/core/auth/auth-api';
import { FloorApi } from '../app/core/floor/floor-api';
import { SalesApi } from '../app/features/sales/data/sales-api';
import { IT_RUN, handoff, need } from './it-env';

/**
 * Dashboard phase 2 (tool/sync_it.sh step 5): the session the staff device ran with the
 * dashboard's game (floor.json, written by test/sync/cross_app_test.dart) is on the owner's Sales
 * list with the bill the server priced and exactly one payment; the owner of another arena sees
 * none of it.
 */
describe.skipIf(!IT_RUN)('integration · dashboard phase 2 (owner sees the floor)', () => {
  it('shows the staff’s bill with one payment, and nothing to another arena', async () => {
    const arenaId = need('AO_IT_ARENA');
    const password = need('AO_IT_PASSWORD');
    const floorRun = handoff.read<{ session_id: string; billed_paise: number; paid_paise: number }>(
      'floor.json',
    );
    const auth = TestBed.inject(AuthApi);
    const sales = TestBed.inject(SalesApi);
    // The floor phase plays its session yesterday 13:00–13:30 IST (inside opening hours).
    const from = new Date(Date.now() - 48 * 3_600_000);
    const to = new Date(Date.now() + 3_600_000);

    await auth.signIn(need('AO_IT_OWNER_EMAIL'), password);
    const bills = await sales.list(arenaId, from, to);
    const bill = bills.find((b) => b.id === floorRun.session_id);
    if (!bill) {
      throw new Error(
        `session ${floorRun.session_id} not on the Sales list (${bills.length} bills in range; ` +
          `newest: ${bills.slice(0, 3).map((b) => `${b.id} ${b.at}`).join(', ')})`,
      );
    }
    expect(bill).toMatchObject({
      billedPaise: floorRun.billed_paise,
      paidPaise: floorRun.paid_paise,
      voided: false,
    });
    const detail = await sales.get(arenaId, floorRun.session_id);
    expect(detail.payments).toHaveLength(1);
    expect(detail.payments[0]).toMatchObject({ amountPaise: floorRun.paid_paise, refund: false });
    await auth.signOut();

    // Another arena's owner: the owner-only RPC refuses, direct reads return nothing (RLS).
    await auth.signIn(need('AO_IT_OUTSIDER_EMAIL'), password);
    await expect(sales.list(arenaId, from, to)).rejects.toMatchObject({ code: 'forbidden' });
    const floor = TestBed.inject(FloorApi);
    expect(await floor.plays(arenaId, from)).toEqual([]);
    expect(await floor.customers(arenaId)).toEqual([]);
    await auth.signOut();
  }, 120_000);
});
