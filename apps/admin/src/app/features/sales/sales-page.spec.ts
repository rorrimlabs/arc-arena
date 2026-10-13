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
import { Clock } from '../../core/time/clock';
import { salesCsv } from './components/sales-csv';
import { SalesApi } from './data/sales-api';
import { SampleSalesApi } from './data/sales-api.sample';
import { rangeBounds } from './data/sale.models';

/** Tue 13 Oct 2026, 7:30 pm IST. */
const NOW = new Date('2026-10-13T14:00:00Z');

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

describe('Sales', () => {
  let harness: RouterTestingHarness;
  let api: SampleSalesApi;

  async function start(url: string, width = 1440) {
    api = new SampleSalesApi(NOW);
    TestBed.configureTestingModule({
      providers: [
        provideRouter(routes, withComponentInputBinding()),
        { provide: AuthApi, useValue: new SampleAuthApi() },
        { provide: ArenaApi, useValue: new SampleArenaApi() },
        { provide: SalesApi, useValue: api },
        { provide: Clock, useValue: { now: () => NOW } },
        { provide: BreakpointObserver, useValue: breakpoints(width) },
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
  const rows = () => [...doc().querySelectorAll('app-list-row a')] as HTMLElement[];
  const titles = () =>
    rows().map((r) => r.querySelector('span.truncate.font-semibold')?.textContent?.trim());
  const trailing = (r: HTMLElement) =>
    [...r.querySelectorAll(':scope > span:last-child > *')].map((e) => e.textContent?.trim());
  const summary = () => doc().querySelector('p[aria-live]')?.textContent?.trim();
  const detail = () => doc().querySelector('app-bill-detail') as HTMLElement | null;
  const button = (label: string, scope: ParentNode = doc()) =>
    [...scope.querySelectorAll('button')].find((b) => b.textContent?.includes(label)) as
      HTMLButtonElement | undefined;
  const snack = () => doc().querySelector('mat-snack-bar-container')?.textContent?.trim();
  const dialog = () => doc().querySelector('mat-dialog-container') as HTMLElement | null;

  afterEach(() =>
    doc()
      ?.querySelectorAll('.cdk-overlay-container')
      .forEach((c) => c.remove()),
  );

  it("lists today's bills, newest first, with the takings summary", async () => {
    await start('/sales');
    expect(titles()).toEqual(['Kiran Rao', 'Aditya Shah', 'Guest', 'Meera Pillai']);
    expect(trailing(rows()[0])).toEqual(['₹240', 'UPI']);
    expect(trailing(rows()[1])).toEqual(['₹720', 'Split']);
    expect(trailing(rows()[3])).toEqual(['₹360', 'Part paid']);
    expect(rows()[0].textContent).toContain('S-3F9A2C · HEX · 6:40 pm');
    expect(summary()).toBe('₹1,220 · 4 bills · UPI ₹940 · Cash ₹280 · Due ₹160');
  });

  it('the method chip keeps bills paid that way; the choice is in the URL', async () => {
    await start('/sales');
    const cash = [...doc().querySelectorAll('mat-chip-option')].find((c) =>
      c.textContent?.includes('Cash'),
    ) as HTMLElement;
    (cash.querySelector('button') as HTMLButtonElement).click();
    await settle();
    expect(TestBed.inject(Router).url).toBe('/sales?method=cash');
    expect(titles()).toEqual(['Aditya Shah', 'Guest']);
    expect(summary()).toBe('₹780 · 2 bills · UPI ₹500 · Cash ₹280');
  });

  it('a voided bill is listed as Void and drops out of takings', async () => {
    await start('/sales?range=yesterday');
    expect(titles()).toEqual(['Kiran Rao', 'Rahul Verma']);
    expect(trailing(rows()[0])).toEqual(['—', 'Void']);
    expect(rows()[0].textContent).toContain('12 Oct, 9:10 pm');
    expect(summary()).toBe('₹120 · 1 bill · UPI ₹120 · Cash ₹0');
  });

  it('search matches the bill, member, station or staff', async () => {
    await start('/sales?range=30d');
    const input = doc().querySelector('input[type="search"]') as HTMLInputElement;
    input.value = 'rift';
    input.dispatchEvent(new Event('input'));
    await settle();
    expect(titles()).toEqual(['Meera Pillai']);
    input.value = 'nobody';
    input.dispatchEvent(new Event('input'));
    await settle();
    expect(doc().body.textContent).toContain('No bills match these filters.');
  });

  it('wide: shows the first bill with its lines and payments', async () => {
    await start('/sales');
    expect(detail()?.querySelector('h2')?.textContent?.trim()).toBe('S-3F9A2C');
    expect(detail()?.textContent).toContain('Paid · UPI');
    expect(detail()?.textContent).toContain('HEX · 1h');
    expect(detail()?.textContent).toContain('UPI · 6:40 pm · Priya Nair');
    expect(detail()?.textContent).toContain('Started by');
  });

  it('voiding asks for a reason, then marks the bill void', async () => {
    await start('/sales?id=71b0e4aa-0000-4000-8000-000000000002');
    button('Void', detail()!)?.click();
    await settle();
    expect(dialog()?.querySelector('h2')?.textContent).toContain('Void G-71B0E4?');
    expect(dialog()?.textContent).toContain(
      '₹720 was collected on it; voiding does not refund it.',
    );
    button('Void bill', dialog()!)?.click();
    await settle();
    expect(dialog()).toBeNull();
    expect(snack()).toBe('G-71B0E4 voided');
    expect(api.bills.find((b) => b.ref === 'G-71B0E4')?.voidReason).toBe('Wrong amount');
    expect(trailing(rows()[1])).toEqual(['—', 'Void']);
    expect(summary()).toBe('₹500 · 3 bills · UPI ₹440 · Cash ₹60 · Due ₹160');
    expect(detail()?.textContent).toContain('Voided · Wrong amount · by Arjun Mehra');
    expect(button('Void', detail()!)).toBeUndefined();
  });

  it('a refused void stays in the dialog', async () => {
    await start('/sales?id=3f9a2c10-0000-4000-8000-000000000001');
    button('Void', detail()!)?.click();
    await settle();
    api.failNext = 'forbidden';
    button('Void bill', dialog()!)?.click();
    await settle();
    expect(dialog()?.querySelector('[role="alert"]')?.textContent?.trim()).toBe(
      'Only an owner can do that',
    );
  });

  it('a linked bill outside the range still opens', async () => {
    await start('/sales?id=9b8a7c6d-0000-4000-8000-000000000008');
    expect(detail()?.querySelector('h2')?.textContent?.trim()).toBe('S-9B8A7C');
    expect(detail()?.textContent).toContain('Paid · Card');
  });
});

describe('sales helpers', () => {
  it('ranges are IST calendar days', () => {
    const today = rangeBounds('today', NOW);
    expect(today.from.toISOString()).toBe('2026-10-12T18:30:00.000Z');
    expect(today.to.toISOString()).toBe('2026-10-13T18:30:00.000Z');
    expect(rangeBounds('yesterday', NOW).from.toISOString()).toBe('2026-10-11T18:30:00.000Z');
    expect(rangeBounds('7d', NOW).from.toISOString()).toBe('2026-10-06T18:30:00.000Z');
    // Just after midnight IST it is already the next day.
    const late = rangeBounds('today', new Date('2026-10-13T18:45:00Z'));
    expect(late.from.toISOString()).toBe('2026-10-13T18:30:00.000Z');
  });

  it('CSV has one quoted-safe row per bill', () => {
    const bills = new SampleSalesApi(NOW).bills;
    const csv = salesCsv(bills.slice(0, 2)).trim().split('\n');
    expect(csv[0]).toBe(
      'Bill,Date,Time,Station,Member,Game,Minutes,Method,Started by,Billed,Collected,Status,Void reason',
    );
    expect(csv[1]).toBe(
      'S-3F9A2C,2026-10-13,6:40 pm,HEX,Kiran Rao,EA SPORTS FC 25,60,UPI,Priya Nair,240.00,240.00,paid,',
    );
    expect(csv[2]).toContain('G-71B0E4,2026-10-13,5:15 pm,VOID,Aditya Shah,Tekken 8,90,Split,');
  });
});
