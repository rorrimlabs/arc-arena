import { NAV_ITEMS } from '../../core/layout/nav';
import { PageTest, startPage } from '../../testing/page-test';

/**
 * The calendar now lives on Staff › Attendance (`?view=calendar`): everyone's month grid beside
 * the list on a wide screen, a person's month and their day in the detail pane. The old
 * /staff/calendar link redirects there.
 */
describe('Staff › Calendar', () => {
  let t: PageTest;

  afterEach(() => t?.cleanup());

  const CALENDAR = '/staff/attendance?view=calendar';
  const navLabels = () =>
    [...t.doc().querySelectorAll('nav[aria-label="Main"] a')].map((a) => a.getAttribute('title'));
  const grid = () => t.doc().querySelector('app-month-grid') as HTMLElement;
  const row = (name: string) =>
    [...grid().querySelectorAll('tbody tr')].find((r) =>
      r.querySelector('th')?.textContent?.includes(name),
    ) as HTMLElement;
  const cell = (name: string, day: number) =>
    row(name).querySelectorAll('td a')[day - 1] as HTMLAnchorElement;
  const panel = () => t.doc().querySelector('app-day-detail') as HTMLElement;

  // KNOWN BUG: the relative redirect 'staff/attendance?view=calendar' (app.routes.ts) loses its
  // query, so the old link opens Today. `it.fails` passes while the bug exists; drop `.fails` once the app is fixed.
  it.fails('the old /staff/calendar link opens the calendar view', async () => {
    t = await startPage('/staff/calendar');
    expect(t.url()).toBe(CALENDAR);
  });

  it('shows this month (IST) with one row per tracked person and the totals', async () => {
    t = await startPage(CALENDAR);
    expect(NAV_ITEMS.find((i) => i.path === 'staff/attendance')?.perm).toBe('attendance_review');
    expect(navLabels()).toContain('Attendance');
    expect(t.calendar.reads).toEqual([['2026-10-01', '2026-10-31']]);
    expect(t.text(t.doc().querySelector('app-list-pane-header span[aria-live]'))).toBe(
      'October 2026',
    );
    expect([...grid().querySelectorAll('tbody th')].map((th) => t.text(th))).toEqual([
      'Priya Nair',
      'Rohan Das',
    ]);
    expect(row('Priya').querySelectorAll('td a')).toHaveLength(31);
    expect(t.text(cell('Priya', 1))).toBe('✓');
    expect(t.text(cell('Priya', 5))).toBe('L');
    expect(t.text(cell('Priya', 6))).toBe('½');
    expect(t.text(cell('Priya', 7))).toBe('A');
    expect(t.text(cell('Priya', 8))).toBe('✓');
    expect(t.text(cell('Priya', 4))).toBe('–');
    expect(t.text(cell('Priya', 20))).toBe('');
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
    expect(totals).toEqual(['9½', '1½', '0', '78h 55m']);
    expect(t.text(grid().querySelector('ul[aria-label="Legend"]'))).toContain('half-day leave');
  });

  it('a cell opens that day’s figures with each of its entries one click away', async () => {
    t = await startPage(CALENDAR, 1440, ({ attendance }) => {
      // Priya's two clock-ins on 8 Oct (the sample log covers only the last week).
      const base = attendance.data.entries[0];
      const stretch = (id: string, inAt: string, outAt: string) => ({
        ...base,
        id,
        staffId: 's1',
        workDate: '2026-10-08',
        inAt,
        outAt,
        inPunchId: null,
        outPunchId: null,
        outSource: 'punch' as const,
        flags: [],
        review: 'none' as const,
      });
      attendance.data.entries.push(
        stretch('e8a', '2026-10-08T03:30:00Z', '2026-10-08T08:00:00Z'),
        stretch('e8b', '2026-10-08T08:30:00Z', '2026-10-08T13:05:00Z'),
      );
    });
    cell('Priya', 8).click();
    await t.settle();
    expect(t.url()).toBe(`${CALENDAR}&staff=s1&day=2026-10-08`);
    const text = t.text(panel())!;
    expect(text).toContain('Priya Nair');
    expect(text).toContain('Thu 8 Oct');
    expect(text).toContain('Completed');
    expect(text).toContain('Clock-in 9:00 am');
    expect(text).toContain('Clock-out 6:35 pm');
    expect(text).toContain('Hours 9h 5m');
    expect(text).toContain('Extra hours 1h 5m');
    const entries = [...panel().querySelectorAll('ul[aria-label="Clock-ins"] > li')];
    expect(entries).toHaveLength(2);
    const link = [...entries[0].querySelectorAll('a')].find((a) =>
      a.textContent?.includes('Details'),
    )!;
    expect(link.getAttribute('href')).toBe(`${CALENDAR}&staff=s1&day=2026-10-08&id=e8a`);
    // On a wide screen the pane has no close button: the person in the list opens their month.
    t.rows()
      .find((r) => t.text(r)?.includes('Priya Nair'))!
      .click();
    await t.settle();
    expect(panel()).toBeNull();
    expect(t.url()).toBe(`${CALENDAR}&staff=s1`);
    expect(t.doc().querySelector('app-person-month')).not.toBeNull();
  });

  it('a day before someone joined says so', async () => {
    t = await startPage(`${CALENDAR}&staff=s2&day=2026-10-01`);
    // Not a working day of theirs: no day opens, their month shows it as not employed.
    expect(panel()).toBeNull();
    const month = t.doc().querySelector('app-person-month') as HTMLElement;
    const first = month.querySelectorAll('button')[0] as HTMLButtonElement;
    expect(first.getAttribute('aria-label')).toBe('Rohan Das, Thu 1 Oct: not employed');
    expect(first.classList).toContain('bg-surface');
    expect(t.text(month.querySelector('[role="group"]'))).not.toContain('Worked');
  });

  it('moves between months', async () => {
    t = await startPage(`${CALENDAR}&month=2026-09`);
    expect(t.calendar.reads).toEqual([['2026-09-01', '2026-09-30']]);
    (t.doc().querySelector('button[aria-label="Next month"]') as HTMLElement).click();
    await t.settle();
    expect(t.url()).toBe(`${CALENDAR}&month=2026-10`);
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
    expect(navLabels()).not.toContain('Attendance');
    expect(t.calendar.reads).toEqual([]);
  });
});
