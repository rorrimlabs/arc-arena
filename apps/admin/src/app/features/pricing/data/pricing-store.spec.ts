import { TestBed } from '@angular/core/testing';
import { describe, expect, it, vi } from 'vitest';
import { ArenaContext } from '../../../core/arena/arena-context';
import { PushRefusal } from '../../../core/sync/push-ops';
import { PricingApi } from './pricing-api';
import { SamplePricingApi } from './pricing-api.sample';
import { PricingStore } from './pricing-store';
import { RateChange } from './pricing.models';

describe('PricingStore', () => {
  function setup() {
    const api = new SamplePricingApi();
    TestBed.configureTestingModule({
      providers: [
        { provide: PricingApi, useValue: api },
        { provide: ArenaContext, useValue: { current: () => ({ id: 'a1', name: '404 Arena' }) } },
      ],
    });
    return { api, store: TestBed.inject(PricingStore) };
  }

  const change: RateChange = {
    activityCode: 'PS5',
    band: 'standard',
    controllerCount: 1,
    unitMinutes: 60,
    pricePaise: 25_000,
  };

  it('reloads what the server holds when a multi-op save is refused part-way', async () => {
    const { api, store } = setup();
    await store.load();
    const load = vi.spyOn(api, 'load');
    vi.spyOn(api, 'saveRates').mockRejectedValueOnce(
      new PushRefusal('invalid', 'Check the values and try again', ['rate.upsert']),
    );

    await expect(
      store.saveRates([change, { ...change, controllerCount: 2 }]),
    ).rejects.toMatchObject({ code: 'invalid' });
    expect(load).toHaveBeenCalledTimes(1);
  });

  it('a refusal that applied nothing leaves the screen as it was', async () => {
    const { api, store } = setup();
    await store.load();
    const load = vi.spyOn(api, 'load');
    vi.spyOn(api, 'saveRates').mockRejectedValueOnce(
      new PushRefusal('forbidden', 'You need the Settings permission for that', []),
    );

    await expect(store.saveRates([change])).rejects.toMatchObject({ code: 'forbidden' });
    expect(load).not.toHaveBeenCalled();
  });
});
