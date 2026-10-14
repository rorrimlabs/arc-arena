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
import { PricingApi } from './data/pricing-api';
import { SamplePricingApi } from './data/pricing-api.sample';
import { summarizeWindows, suggestCode } from './data/pricing.models';

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
    doc().querySelector('app-type-detail, app-happy-hour-detail') as HTMLElement | null;
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

  it('lists station types with their price, and happy hour', async () => {
    await start('/pricing');
    expect(rows('pricing-types').map(rowText)).toEqual([
      'PlayStation 5 | 4 stations · up to 2 players | ₹150 | per hour',
      'VR | 1 station | ₹200 | per 30 min',
      'Pool | Off | No price',
    ]);
    expect(rowText(rows('pricing-rules')[0])).toBe('Happy hour | Tue–Fri · 2:00 pm–5:00 pm | On');
  });

  it('a type shows its base rate with the Enabled switch, and the happy-hour price', async () => {
    await start('/pricing?id=t-ps5');
    const sections = [...detail()!.querySelectorAll('app-detail-section h3')].map((h) =>
      h.textContent?.trim(),
    );
    expect(sections).toEqual(['Base rate', 'With rules applied']);
    const applied = [...detail()!.querySelectorAll('app-detail-row')].map((r) =>
      [...r.querySelectorAll('span')].map((x) => x.textContent?.trim()).join(' | '),
    );
    expect(applied).toEqual([
      'Base | ₹150 per hour',
      'Happy hour · Tue–Fri · 2:00 pm–5:00 pm | ₹120 per hour',
    ]);
  });

  it('a load failure keeps the layout and shows the server error', async () => {
    await start('/pricing', false, 'function_missing');
    expect(doc().querySelector('[role="alert"]')?.textContent).toContain('function_missing');
    expect(section('pricing-types')?.textContent).toContain('Not loaded.');
    expect(section('pricing-rules')?.textContent).toContain('Not loaded.');
    expect(detail()).toBeNull();
    const pane = doc().querySelector('app-detail-pane');
    expect(
      [...(pane?.querySelectorAll('app-detail-section h3') ?? [])].map((h) =>
        h.textContent?.trim(),
      ),
    ).toEqual(['Base rate', 'With rules applied']);
    expect(pane?.textContent).toContain("Prices couldn't load: function_missing");
  });

  it('a new arena starts with no types and says what to do', async () => {
    await start('/pricing', true);
    expect(section('pricing-types')?.textContent).toContain('No station types yet.');
  });

  it('adds a type with a code that follows its name, then opens it', async () => {
    await start('/pricing', true);
    button('Type')?.click();
    await settle();
    type(field('Name'), 'PlayStation 5');
    await settle();
    expect(field('Code').value).toBe('PLAYSTATION5');
    type(field('Code'), 'ps5');
    button('Add type', dialog()!)?.click();
    await settle();
    await settle();
    expect(dialog()).toBeNull();
    expect(snack()).toBe('PlayStation 5 added · set its prices');
    expect(api.types.at(-1)?.code).toBe('PS5');
    expect(TestBed.inject(Router).url).toBe(`/pricing?id=${api.types.at(-1)?.id}`);
    expect(detail()?.textContent).toContain("No standard price yet: staff can't bill");
  });

  it('a taken code is refused in the dialog', async () => {
    await start('/pricing');
    button('Type')?.click();
    await settle();
    type(field('Name'), 'Another');
    type(field('Code'), 'PS5');
    button('Add type', dialog()!)?.click();
    await settle();
    expect(dialog()?.querySelector('[role="alert"]')?.textContent?.trim()).toBe(
      'Another type already uses that code',
    );
  });

  it('edits prices in a draft and saves only what changed', async () => {
    await start('/pricing?id=t-ps5');
    expect(priceInput('Standard, 1 controller').value).toBe('150');
    expect(doc().querySelector('app-unsaved-bar')).toBeNull();

    type(priceInput('Standard, 1 controller'), '160');
    type(priceInput('Standard, 3 controllers'), '300');
    type(priceInput('Happy hour, 2 controllers'), '');
    await settle();
    expect(doc().querySelector('app-unsaved-bar')).not.toBeNull();

    button('Save', doc().querySelector('app-unsaved-bar')!)?.click();
    await settle();
    await settle();
    expect(snack()).toBe('PlayStation 5 prices saved · new sessions use them');
    const ps5 = api.rates.filter((r) => r.activityCode === 'PS5');
    expect(ps5.find((r) => r.band === 'standard' && r.controllerCount === 1)?.pricePaise).toBe(
      16000,
    );
    expect(ps5.find((r) => r.band === 'standard' && r.controllerCount === 3)?.pricePaise).toBe(
      30000,
    );
    expect(ps5.some((r) => r.band === 'happy' && r.controllerCount === 2)).toBe(false);
    expect(doc().querySelector('app-unsaved-bar')).toBeNull();
  });

  it('discard puts the saved prices back', async () => {
    await start('/pricing?id=t-ps5');
    type(priceInput('Standard, 1 controller'), '999');
    await settle();
    button('Discard', doc().querySelector('app-unsaved-bar')!)?.click();
    await settle();
    expect(priceInput('Standard, 1 controller').value).toBe('150');
  });

  it('a type with stations cannot be turned off', async () => {
    await start('/pricing?id=t-ps5');
    (detail()!.querySelector('mat-slide-toggle button') as HTMLButtonElement).click();
    await settle();
    expect(snack()).toBe('Remove its 4 stations first');
    expect(api.types.find((t) => t.id === 't-ps5')?.active).toBe(true);
  });

  it('a type stations still offer explains instead of removing', async () => {
    await start('/pricing?id=t-ps5');
    button('Remove', detail()!)?.click();
    await settle();
    expect(dialog()?.textContent).toContain('4 stations offer it');
    expect(button('Remove', dialog()!.querySelector('mat-dialog-actions')!)).toBeUndefined();
    expect(api.types.find((t) => t.id === 't-ps5')).toBeDefined();
  });

  it('removes a type no station offers: never used → deleted', async () => {
    await start('/pricing?id=t-pool');
    button('Remove', detail()!)?.click();
    await settle();
    expect(dialog()?.textContent).toContain('Remove Pool?');
    button('Remove', dialog()!.querySelector('mat-dialog-actions')!)?.click();
    await settle();
    expect(api.types.some((t) => t.id === 't-pool')).toBe(false);
    expect(snack()).toBe('Pool deleted');
  });

  it('happy hour previews each enabled type', async () => {
    await start('/pricing?id=happy');
    const preview = [...detail()!.querySelectorAll('app-detail-row')].map((r) =>
      [...r.querySelectorAll('span')].map((s) => s.textContent?.trim()).join(' | '),
    );
    expect(preview).toEqual(['PlayStation 5 | ₹150 → ₹120/h', 'VR | Not included']);
  });

  it('happy hour saves the weekly windows and keeps opening hours', async () => {
    await start('/pricing?id=happy');
    const toggles = [
      ...detail()!.querySelectorAll('mat-slide-toggle button'),
    ] as HTMLButtonElement[];
    toggles[6].click(); // Saturday on (after the Active switch)
    await settle();
    button('Save', doc().querySelector('app-unsaved-bar')!)?.click();
    await settle();
    await settle();
    expect(snack()).toBe('Happy hour saved · new sessions use it');
    expect(api.hours.happy['6']).toEqual({ start: 840, end: 1020 });
    expect(api.hours.open['1']).toBeNull();
  });
});

describe('pricing helpers', () => {
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
