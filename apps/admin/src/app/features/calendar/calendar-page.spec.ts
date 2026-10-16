import { NAV_ITEMS } from '../../core/layout/nav';
import { PageTest, startPage } from '../../testing/page-test';

describe('Staff › Calendar', () => {
  let t: PageTest;

  afterEach(() => t?.cleanup());

  const navLabels = () =>
    [...t.doc().querySelectorAll('nav[aria-label="Main"] a')].map((a) => a.getAttribute('title'));
  const row = (name: string) =>
    [...t.doc().querySelectorAll('tbody tr')].find((r) =>
      r.querySelector('th')?.textContent?.includes(name),
    ) as HTMLElement;
  const cell = (name: string, day: number) =>
    row(name).querySelectorAll('td a')[day - 1] as HTMLAnchorElement;
  const panel = () => t.doc().querySelector('aside[aria-label="Day details"]') as HTMLElement;

  it('shows this month (IST) with one row per tracked person and the totals', async () => {
    t = await startPage('/staff/calendar');
    expect(NAV_ITEMS.find((i) => i.path === 'staff/calendar')?.perm).toBe('attendance_review');
    expect(navLabels()).toContain('Calendar');
    expect(t.calendar.reads).toEqual([['2026-10-01', '2026-10-31']]);
    expect(t.text(t.doc().querySelector('app-list-pane-header span[aria-live]'))).toBe('October 2026');
    expect([...t.doc().querySelectorAll('tbody th')].map((th) => t.text(th))).toEqual([
      'Priya Nair',
      'Rohan Das',
    ]);
    expect(row('Priya').querySelectorAll('td a')).toHaveLength(31);
    expect(t.text(cell('Priya', 1))).toBe('✓');
    expect(t.text(cell('Priya', 5))).toBe('L');
    expect(t.text(cell('Priya', 6))).toBe('½');
    expect(t.text(cell('Priya', 7))).toBe('A');
    expect(t.text(cell('Priya', 8))).toBe('✓ +1.1h');
    expect(t.text(cell('Priya', 4))).toBe('–');
    expect(t.text(cell('Priya', 20))).toBe('·');
    expect(t.text(cell('Rohan', 2))).toBe('H');
    // Before Rohan joined: a blank, greyed cell.
    expect(t.text(cell('Rohan', 1))).toBe('');
    expect(cell('Rohan', 1).classList).toContain('bg-surface');
    expect(cell('Rohan', 1).getAttribute('aria-label')).toBe('Rohan Das, Thu 1 Oct: not employed');
    expect(t.text(cell('Rohan', 9))).toBe('Lv');
    expect(t.text(cell('Rohan', 12))).toBe('½Lv');
    expect(cell('Priya', 8).getAttribute('aria-label')).toBe(
      'Priya Nair, Thu 8 Oct: present, 9 h 05 m, 1 h 05 m extra',
    );
    const totals = [...row('Priya').querySelectorAll('td')].slice(31).map((td) => t.text(td));
    expect(totals).toEqual(['9½', '1', '1', '1½', '0', '78 h 55 m', '3 h 05 m']);
    expect(t.text(t.doc().querySelector('ul[aria-label="Legend"]'))).toContain('half-day leave');
  });

  it('a cell opens that day’s figures with a link to its entries in the log', async () => {
    t = await startPage('/staff/calendar');
    cell('Priya', 8).click();
    await t.settle();
    expect(t.url()).toBe('/staff/calendar?staff=s1&day=2026-10-08');
    expect(cell('Priya', 8).getAttribute('aria-current')).toBe('true');
    const text = t.text(panel())!;
    expect(text).toContain('Priya Nair');
    expect(text).toContain('Present Thu 8 Oct');
    expect(text).toContain('Worked 9 h 05 m');
    expect(text).toContain('Extra 1 h 05 m');
    expect(text).toContain('Clock-ins 2 entries');
    const link = [...panel().querySelectorAll('a')].find((a) =>
      a.textContent?.includes('Open in the attendance log'),
    )!;
    expect(link.getAttribute('href')).toBe(
      '/staff/attendance?range=custom&from=2026-10-08&to=2026-10-08&staff=s1',
    );
    (panel().querySelector('button[aria-label="Close"]') as HTMLElement).click();
    await t.settle();
    expect(panel()).toBeNull();
  });

  it('a day before someone joined says so', async () => {
    t = await startPage('/staff/calendar?staff=s2&day=2026-10-01');
    expect(t.text(panel())).toContain('Not employed on this day');
    expect(t.text(panel())).not.toContain('Worked');
  });

  it('moves between months', async () => {
    t = await startPage('/staff/calendar?month=2026-09');
    expect(t.calendar.reads).toEqual([['2026-09-01', '2026-09-30']]);
    (t.doc().querySelector('button[aria-label="Next month"]') as HTMLElement).click();
    await t.settle();
    expect(t.url()).toBe('/staff/calendar?month=2026-10');
    expect(t.calendar.reads.at(-1)).toEqual(['2026-10-01', '2026-10-31']);
  });

  it('needs attendance_review', async () => {
    t = await startPage('/staff/calendar', 1440, ({ arena }) => {
      arena.memberships = arena.memberships.map((m) => ({
        ...m,
        role: 'staff' as const,
        perms: ['money', 'reports', 'settings'],
      }));
    });
    expect(t.url()).toBe('/overview');
    expect(navLabels()).not.toContain('Calendar');
    expect(t.calendar.reads).toEqual([]);
  });
});
