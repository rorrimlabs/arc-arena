import { formatRupees } from '../../shared/money/rupees.pipe';
import { istDayStart } from '../../shared/time/ist';
import { NOW, PageTest, startPage } from '../../testing/page-test';
import { summarize } from '../sales/data/sale.models';

describe('Overview', () => {
  let t: PageTest;
  const kpis = () =>
    [...t.doc().querySelectorAll('app-overview-page mat-card')].slice(0, 4).map((c) => ({
      label: t.text(c.querySelector('span')),
      value: t.text(c.querySelector('.font-display')),
    }));
  const live = () => t.doc().querySelector('app-live-pane') as HTMLElement;

  afterEach(() => t?.cleanup());

  it("shows today's takings and bills from the closed bills", async () => {
    t = await startPage('/overview');
    const today = await t.sales.list('a1', istDayStart(NOW), istDayStart(NOW, -1));
    const s = summarize(today);
    expect(kpis().map((k) => k.label)).toEqual([
      'Takings',
      'Bills',
      'Hours played',
      'Average bill',
    ]);
    expect(kpis()[0].value).toBe(formatRupees(s.takingsPaise));
    expect(kpis()[1].value).toBe(String(s.count));
    expect(t.text(t.doc().querySelector('app-overview-page p'))).toBe(
      'Today so far · 404 Arena Koramangala',
    );
    expect(t.text(t.doc().querySelector('app-overview-page'))).toContain('vs yesterday');
  });

  it('switches period through the URL', async () => {
    t = await startPage('/overview');
    const toggle = [...t.doc().querySelectorAll('mat-button-toggle button')].find(
      (b) => t.text(b) === '7d',
    ) as HTMLButtonElement;
    toggle.click();
    await t.settle();
    expect(t.url()).toBe('/overview?period=7d');
    expect(t.text(t.doc().querySelector('app-overview-page p'))).toContain('Last 7 days');
    // One bar per day, today last.
    const labels = [...t.doc().querySelectorAll('.font-mono.flex-1')].map((e) => t.text(e));
    expect(labels).toHaveLength(7);
    expect(labels.at(-1)).toBe('Today');
  });

  it('the live pane shows stations in use, sessions ending soon and latest bills', async () => {
    t = await startPage('/overview');
    expect(t.text(live())).toContain('2 of 6 stations in use');
    const ending = [...live().querySelectorAll('section')[0].querySelectorAll('a')];
    expect(ending.map((a) => t.text(a))).toEqual([
      'sports_esports VOID Tekken 8 8m',
      'sports_esports HEX EA SPORTS FC 25 25m',
    ]);
    expect(ending[0].getAttribute('href')).toBe('/stations?id=s-void');
    const latest = [...live().querySelectorAll('section')[1].querySelectorAll('a')];
    expect(latest.length).toBeGreaterThan(0);
    expect(latest[0].getAttribute('href')).toMatch(/^\/sales\?id=/);
  });
});
