import { BreakpointObserver } from '@angular/cdk/layout';
import { TestBed } from '@angular/core/testing';
import { MATERIAL_ANIMATIONS } from '@angular/material/core';
import { Router, provideRouter, withComponentInputBinding } from '@angular/router';
import { RouterTestingHarness } from '@angular/router/testing';
import { of } from 'rxjs';
import { routes } from '../../app.routes';
import { ArenaApi } from '../../core/arena/arena-api';
import { SampleArenaApi } from '../../core/arena/arena-api.sample';
import { AuthApi } from '../../core/auth/auth-api';
import { SampleAuthApi } from '../../core/auth/auth-api.sample';
import { PricingApi, parseRates, rateOps, typeOps } from './data/pricing-api';
import { SamplePricingApi } from './data/pricing-api.sample';
import { PricingStore } from './data/pricing-store';
import {
  ADJUST_KINDS,
  adjustKindLabel,
  adjustLabel,
  rulePrice,
  summarizeWindows,
  suggestCode,
} from './data/pricing.models';

function breakpoints(width: number) {
  const matches = (query: string) => {
    const min = /min-width:\s*([\d.]+)px/.exec(query);
    const max = /max-width:\s*([\d.]+)px/.exec(query);
    return (!min || width >= +min[1]) && (!max || width <= +max[1]);
  };
  return {
    isMatched: matches,
    observe: (q: string) => of({ matches: matches(q), breakpoints: {} }),
  };
}

describe('Pricing', () => {
  let harness: RouterTestingHarness;
  let api: SamplePricingApi;

  async function start(url: string, empty = false, failWith: string | null = null) {
    api = new SamplePricingApi(empty);
    api.failNext = failWith;
    TestBed.configureTestingModule({
      providers: [
        provideRouter(routes, withComponentInputBinding()),
        { provide: AuthApi, useValue: new SampleAuthApi() },
        { provide: ArenaApi, useValue: new SampleArenaApi() },
        { provide: PricingApi, useValue: api },
        { provide: BreakpointObserver, useValue: breakpoints(1440) },
        { provide: MATERIAL_ANIMATIONS, useValue: { animationsDisabled: true } },
      ],
    });
    harness = await RouterTestingHarness.create();
    await harness.navigateByUrl(url);
    await settle();
  }

  async function settle() {
    for (let i = 0; i < 3; i++) {
      await harness.fixture.whenStable();
      await new Promise((r) => setTimeout(r));
    }
    await harness.fixture.whenStable();
  }

  const doc = () => harness.routeNativeElement?.ownerDocument as Document;
  const section = (id: string) => doc().querySelector(`section[aria-labelledby="${id}"]`);
  const rows = (id: string) =>
    [...(section(id)?.querySelectorAll('app-list-row a') ?? [])] as HTMLElement[];
  /** The row's visible texts, leaf by leaf (icon glyph names left out). */
  const rowText = (r: HTMLElement) =>
    [...r.querySelectorAll('*')]
      .filter((e) => !e.children.length && !e.classList.contains('icon'))
      .map((e) => e.textContent?.trim())
      .filter(Boolean)
      .join(' | ');
  const detail = () =>
    doc().querySelector('app-type-detail') as HTMLElement | null;
  const ruleDetail = () => doc().querySelector('app-rule-detail') as HTMLElement | null;
  const discountDetail = () => doc().querySelector('app-discount-detail') as HTMLElement | null;
  const chip = (label: string) =>
    [...doc().querySelectorAll('mat-chip-option')].find(
      (c) => c.textContent?.trim() === label,
    )!.querySelector('button, [role="option"], .mdc-evolution-chip__action') as HTMLElement;

  /** Opens the mat-select labelled `label` and picks `option`. */
  async function pick(label: string, option: string) {
    const f = [...doc().querySelectorAll('mat-form-field')].find(
      (x) => x.querySelector('mat-label')?.textContent?.trim() === label,
    );
    (f?.querySelector('.mat-mdc-select-trigger') as HTMLElement).click();
    await settle();
    ([...doc().querySelectorAll('mat-option')] as HTMLElement[])
      .find((o) => o.textContent?.trim() === option)
      ?.click();
    await settle();
  }
  const button = (label: string, scope: ParentNode = doc()) =>
    [...scope.querySelectorAll('button')].find((b) => b.textContent?.trim().endsWith(label)) as
      HTMLButtonElement | undefined;
  const snack = () => doc().querySelector('mat-snack-bar-container')?.textContent?.trim();
  const dialog = () => doc().querySelector('mat-dialog-container') as HTMLElement | null;
  const priceInput = (label: string) =>
    detail()?.querySelector(`input[aria-label="${label}"]`) as HTMLInputElement;

  function type(input: HTMLInputElement, value: string) {
    input.value = value;
    input.dispatchEvent(new Event('input'));
  }

  /** A field by label, inside the open dialog if there is one. */
  function field(label: string): HTMLInputElement {
    const f = [...(dialog() ?? doc()).querySelectorAll('mat-form-field')].find((x) =>
      x.querySelector('mat-label')?.textContent?.includes(label),
    );
    return f?.querySelector('input') as HTMLInputElement;
  }

  afterEach(() =>
    doc()
      ?.querySelectorAll('.cdk-overlay-container')
      .forEach((c) => c.remove()),
  );

  it('lists priced types, time rules, holidays, discounts and coupons', async () => {
    await start('/pricing');
    // Turned-off types (Pool) are managed in Settings, not priced here.
    expect(rows('pricing-types').map(rowText)).toEqual([
      'PlayStation 5 | 4 stations · up to 2 players | ₹150 | per hour',
      'VR | 1 station | ₹200 | per 30 min',
    ]);
    // Happy hours are an ordinary rule: lower by 20%, Tue–Fri afternoons, PS5 only.
    expect(rows('pricing-rules').map(rowText)).toEqual([
      '1. Happy hours | Tue–Fri · 2:00 pm–5:00 pm · PlayStation 5 | 20% lower',
      '2. Weekend evening | Sat–Sun · 6:00 pm–11:00 pm · All types | 20% higher',
    ]);
    expect(section('pricing-rules')?.textContent).toContain(
      'Happy hours: add a rule, e.g. Tue–Fri 2–5 PM, 20% lower.',
    );
    expect(rows('pricing-discounts').map(rowText)).toEqual(['Student | 10% off | Active']);
    expect(rows('pricing-coupons').map(rowText)).toEqual([
      'DIWALI20 | Diwali · 20% off · until 15 Nov | Active',
    ]);
  });

  it('a type leads with its base price, then more controllers and the rules applied', async () => {
    await start('/pricing?id=t-ps5');
    const sections = [...detail()!.querySelectorAll('app-detail-section h3')].map((h) =>
      h.textContent?.trim(),
    );
    expect(sections).toEqual(['Base price', 'Price by controller count', 'With rules applied']);
    const applied = [...detail()!.querySelectorAll('app-detail-row')].map((r) =>
      [...r.querySelectorAll('span')].map((x) => x.textContent?.trim()).join(' | '),
    );
    expect(applied).toEqual([
      'Max players | 2',
      'Base | ₹150 per hour',
      'Happy hours · Tue–Fri · 2:00 pm–5:00 pm | ₹120 per hour',
      'Weekend evening · Sat–Sun · 6:00 pm–11:00 pm | ₹180 per hour',
    ]);
  });

  it('a load failure keeps the layout and shows the server error', async () => {
    await start('/pricing', false, 'function_missing');
    expect(doc().querySelector('[role="alert"]')?.textContent).toContain('function_missing');
    expect(section('pricing-types')?.textContent).toContain('Not loaded.');
    expect(detail()).toBeNull();
    const pane = doc().querySelector('app-detail-pane');
    expect(pane?.textContent).toContain("Prices couldn't load: function_missing");
  });

  it('a new arena starts with no types and says where to add them', async () => {
    await start('/pricing', true);
    expect(section('pricing-types')?.textContent).toContain('No station types yet.');
    expect(section('pricing-rules')?.textContent).toContain('None yet.');
    const link = section('pricing-types')?.querySelector('a') as HTMLAnchorElement;
    expect(link.getAttribute('href')).toBe('/settings?id=types');
  });

  it('one price per row: no happy-hour column', async () => {
    await start('/pricing?id=t-ps5');
    const labels = [...detail()!.querySelectorAll('input[aria-label]')].map((i) =>
      i.getAttribute('aria-label'),
    );
    expect(labels).toEqual([
      'Price, 1 controller',
      'Price, 2 controllers',
      'Price, 3 controllers',
      'Price, 4 controllers',
    ]);
    // No happy-hour price column: only rules (e.g. the "Happy hours" rule) change prices.
    const grids = [...detail()!.querySelectorAll('[role="group"]')].map((g) => g.textContent);
    expect(grids.join(' ')).not.toMatch(/happy|standard/i);
  });

  it('edits prices in a draft and saves only what changed', async () => {
    await start('/pricing?id=t-ps5');
    expect(priceInput('Price, 1 controller').value).toBe('150');
    expect(doc().querySelector('app-unsaved-bar')).toBeNull();

    type(priceInput('Price, 1 controller'), '160');
    type(priceInput('Price, 3 controllers'), '300');
    type(priceInput('Price, 2 controllers'), '');
    await settle();
    expect(doc().querySelector('app-unsaved-bar')).not.toBeNull();

    button('Save', doc().querySelector('app-unsaved-bar')!)?.click();
    await settle();
    await settle();
    expect(snack()).toBe('PlayStation 5 prices saved · new sessions use them');
    const ps5 = api.rates.filter((r) => r.activityCode === 'PS5');
    expect(ps5.find((r) => r.controllerCount === 1)?.pricePaise).toBe(16000);
    expect(ps5.find((r) => r.controllerCount === 3)?.pricePaise).toBe(30000);
    expect(ps5.some((r) => r.controllerCount === 2)).toBe(false);
    expect(doc().querySelector('app-unsaved-bar')).toBeNull();
  });

  it('discard puts the saved prices back', async () => {
    await start('/pricing?id=t-ps5');
    type(priceInput('Price, 1 controller'), '999');
    await settle();
    button('Discard', doc().querySelector('app-unsaved-bar')!)?.click();
    await settle();
    expect(priceInput('Price, 1 controller').value).toBe('150');
  });

  it('the old happy-hour page is gone: ?id=happy shows the first type', async () => {
    await start('/pricing?id=happy');
    expect(doc().querySelector('app-happy-hour-detail')).toBeNull();
    expect(detail()?.textContent).toContain('PlayStation 5');
  });

  it('happy hours is an ordinary rule that lowers the price', async () => {
    await start('/pricing?id=r-happy');
    const examples = [...ruleDetail()!.querySelectorAll('app-detail-row')].map((r) =>
      [...r.querySelectorAll('span')].map((x) => x.textContent?.trim()).join(' | '),
    );
    expect(examples).toEqual(['PlayStation 5 | ₹150 → ₹120 per hour']);
    const selects = [...ruleDetail()!.querySelectorAll('mat-select')].map((x) =>
      x.textContent?.trim(),
    );
    expect(selects).toEqual(['Not on holidays', 'Lower by', 'Percent']);
  });

  it('a rule shows what it does to each type, and edits save as rule.upsert', async () => {
    await start('/pricing?id=r-weekend');
    const examples = [...ruleDetail()!.querySelectorAll('app-detail-row')].map((r) =>
      [...r.querySelectorAll('span')].map((x) => x.textContent?.trim()).join(' | '),
    );
    expect(examples).toEqual([
      'PlayStation 5 | ₹150 → ₹180 per hour',
      'VR | ₹200 → ₹240 per 30 min',
    ]);
    type(field('Amount'), '25');
    await settle();
    button('Save', doc().querySelector('app-unsaved-bar')!)?.click();
    await settle();
    await settle();
    expect(snack()).toBe('Weekend evening saved · new sessions use it');
    expect(api.ops.at(-1)).toEqual({
      kind: 'rule.upsert',
      payload: expect.objectContaining({
        id: 'r-weekend',
        days: [6, 7],
        start_min: 1080,
        end_min: 1380,
        adjust_kind: 'percent',
        adjust_value: 25,
      }),
    });
  });

  it('adds a rule from the Add menu: a decrease in rupees per hour, for one type', async () => {
    await start('/pricing');
    button('Add')?.click();
    await settle();
    ([...doc().querySelectorAll('[mat-menu-item]')] as HTMLElement[])
      .find((b) => b.textContent?.includes('Time rule'))
      ?.click();
    await settle();
    expect(TestBed.inject(Router).url).toBe('/pricing?id=new-rule');
    type(field('Name'), 'Weekday morning');
    await pick('Price', 'Lower by');
    await pick('Change by', 'Flat ₹ per hour');
    type(field('Amount'), '30');
    type(field('From'), '10:00');
    type(field('To'), '14:00');
    chip('Sat').click();
    chip('Sun').click();
    chip('Mon').click();
    chip('PlayStation 5').click();
    await settle();
    button('Save', doc().querySelector('app-unsaved-bar')!)?.click();
    await settle();
    await settle();
    const added = api.rules.find((r) => r.name === 'Weekday morning')!;
    expect(added).toMatchObject({
      days: [1],
      startMin: 600,
      endMin: 840,
      activityCodes: ['PS5'],
      adjustKind: 'per_hour',
      adjustValue: -3000,
      priority: 3,
    });
    expect(TestBed.inject(Router).url).toBe(`/pricing?id=${added.id}`);
  });

  it('a rule whose end is before its start is refused on the screen', async () => {
    await start('/pricing?id=new-rule');
    type(field('Name'), 'Late');
    type(field('From'), '20:00');
    type(field('To'), '18:00');
    await settle();
    button('Save', doc().querySelector('app-unsaved-bar')!)?.click();
    await settle();
    expect(ruleDetail()?.querySelector('[role="alert"]')?.textContent?.trim()).toBe(
      'Pick an end time after the start',
    );
    expect(api.ops.some((o) => o.kind === 'rule.upsert')).toBe(false);
  });

  it('rules move up and down: rule.reorder with every id, first-tried first', async () => {
    await start('/pricing');
    api.rules.push({ ...api.rules[1], id: 'r-two', name: 'Holiday', priority: 3 });
    await harness.navigateByUrl('/pricing?id=r-two');
    TestBed.inject(PricingStore).load(true);
    await settle();
    button('Move up', ruleDetail()!)?.click();
    await settle();
    await settle();
    expect(api.ops.at(-1)).toEqual({
      kind: 'rule.reorder',
      payload: { ids: ['r-happy', 'r-two', 'r-weekend'] },
    });
    expect(rows('pricing-rules').map(rowText)[1]).toContain('2. Holiday');
  });

  it('a coupon shows its use, read only when it is opened', async () => {
    await start('/pricing');
    expect(api.usageReads).toEqual([]);
    await harness.navigateByUrl('/pricing?id=d-diwali');
    await settle();
    expect(api.usageReads).toEqual(['d-diwali']);
    const tiles = [...discountDetail()!.querySelectorAll('app-stat-tile')].map((e) =>
      [...e.querySelectorAll('span')].map((x) => x.textContent?.trim()).join(' '),
    );
    expect(tiles).toEqual(['Used on bills 1 of 50', 'Value 20% off', 'Expires 15 Nov']);
    const used = discountDetail()!.querySelector('app-line-row a') as HTMLAnchorElement;
    expect(used.getAttribute('href')).toBe('/sales?id=3f9a2c10-0000-4000-8000-000000000001');
    expect(used.textContent).toContain('−₹30');
  });

  it('adds a coupon: upper-case code, expiry at the end of the IST day', async () => {
    await start('/pricing?id=new-coupon');
    type(field('Name'), 'New year');
    type(field('Code'), 'ny2027');
    type(field('Amount'), '15');
    type(field('Expires after'), '2027-01-01');
    await settle();
    button('Save', doc().querySelector('app-unsaved-bar')!)?.click();
    await settle();
    await settle();
    expect(api.ops.at(-1)).toEqual({
      kind: 'discount.upsert',
      payload: expect.objectContaining({
        kind: 'coupon',
        code: 'NY2027',
        value_kind: 'percent',
        value: 15,
        valid_until: '2027-01-01T18:29:59.000Z',
        max_uses: 100,
      }),
    });
    expect(snack()).toBe('NY2027 saved');
  });

  it('a used coupon cannot be deleted: it explains and offers to turn it off', async () => {
    await start('/pricing?id=d-diwali');
    button('Delete', discountDetail()!)?.click();
    await settle();
    expect(dialog()?.textContent).toContain('1 bill used it');
    expect(api.ops.some((o) => o.kind === 'discount.delete')).toBe(false);
  });
});

describe('pricing helpers', () => {
  it('prices a rule like the server (half up, never below ₹0)', () => {
    expect(rulePrice(15000, 60, { adjustKind: 'percent', adjustValue: 20 })).toBe(18000);
    expect(rulePrice(15000, 60, { adjustKind: 'percent', adjustValue: -33 })).toBe(10050);
    expect(rulePrice(20000, 30, { adjustKind: 'per_hour', adjustValue: -3031 })).toBe(18485);
    expect(rulePrice(20000, 30, { adjustKind: 'per_hour', adjustValue: -3033 })).toBe(18484);
    expect(rulePrice(1000, 60, { adjustKind: 'per_hour', adjustValue: -5000 })).toBe(0);
  });

  it('names the two kinds of price change in owner words, with the direction spelled out', () => {
    expect(ADJUST_KINDS.map((k) => k.label)).toEqual(['Percent', 'Flat ₹ per hour']);
    expect(adjustKindLabel('percent')).toBe('Percent');
    expect(adjustKindLabel('per_hour')).toBe('Flat ₹ per hour');
    expect(adjustLabel({ adjustKind: 'percent', adjustValue: -20 })).toBe('20% lower');
    expect(adjustLabel({ adjustKind: 'percent', adjustValue: 15 })).toBe('15% higher');
    expect(adjustLabel({ adjustKind: 'per_hour', adjustValue: -3000 })).toBe('₹30/hr lower');
    expect(adjustLabel({ adjustKind: 'per_hour', adjustValue: 1250 })).toBe('₹12.50/hr higher');
  });

  it('writes only standard-band rates and no happy-hour flag; reads drop other bands', () => {
    const ops = rateOps([
      { activityCode: 'PS5', controllerCount: 1, unitMinutes: 60, pricePaise: 15000 },
      { activityCode: 'PS5', controllerCount: 2, unitMinutes: 60, pricePaise: null },
    ]);
    expect(ops.map((o) => [o.kind, o.payload['band']])).toEqual([
      ['rate.upsert', 'standard'],
      ['rate.delete', 'standard'],
    ]);
    const [upsert] = typeOps({
      id: 't1',
      code: 'PS5',
      name: 'PS5',
      usesControllers: true,
      usesGames: true,
      durationModel: 'hourly',
      sortOrder: 0,
      active: true,
    });
    expect(Object.keys(upsert.payload)).not.toContain('happy_hour_eligible');
    expect(
      parseRates([
        { activity_code: 'PS5', band: 'standard', controller_count: 1, price_paise: 15000 },
        { activity_code: 'PS5', band: 'happy', controller_count: 1, price_paise: 12000 },
      ]),
    ).toEqual([{ activityCode: 'PS5', controllerCount: 1, unitMinutes: 60, pricePaise: 15000 }]);
  });

  it('suggests a code from a name', () => {
    expect(suggestCode('Pool table')).toBe('POOLTABLE');
    expect(suggestCode('VR — Quest 3 bay')).toBe('VRQUEST3BAY');
  });

  it('summarises windows, grouping equal consecutive days', () => {
    const w = { start: 840, end: 1020 };
    expect(summarizeWindows({ '1': null, '2': w, '3': w, '4': null, '5': w })).toBe(
      'Tue–Wed · 2:00 pm–5:00 pm, Fri · 2:00 pm–5:00 pm',
    );
  });
});
