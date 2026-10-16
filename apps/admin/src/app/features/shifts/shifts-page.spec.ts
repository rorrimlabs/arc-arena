import { NAV_ITEMS } from '../../core/layout/nav';
import { PageTest, startPage } from '../../testing/page-test';

describe('Staff › Shifts & holidays', () => {
  let t: PageTest;

  afterEach(() => t?.cleanup());

  const navLabels = () =>
    [...t.doc().querySelectorAll('nav[aria-label="Main"] a')].map((a) => a.getAttribute('title'));
  const shiftRows = () =>
    [...t.doc().querySelectorAll('ul[aria-label="Shifts"] app-list-row a')] as HTMLElement[];
  const detail = () => t.doc().querySelector('app-shift-detail') as HTMLElement;
  const holidays = () => t.doc().querySelector('app-staff-holidays') as HTMLElement;
  const addShift = () =>
    t.doc().querySelector('app-list-pane-header button') as HTMLButtonElement;
  const dialogInput = (selector: string) =>
    t.dialog()!.querySelector(selector) as HTMLInputElement;
  function set(input: HTMLInputElement, value: string) {
    input.value = value;
    input.dispatchEvent(new Event('input'));
  }

  it('is in the Staff group for everyone; lists shifts with times and days', async () => {
    t = await startPage('/staff/shifts');
    expect(NAV_ITEMS.find((i) => i.path === 'staff/shifts')?.perm).toBeUndefined();
    expect(navLabels()).toContain('Shifts & holidays');
    expect(shiftRows().map(t.rowText)).toEqual([
      ['Morning', '9:00 AM – 6:00 PM · Mon–Sat'],
      ['Night', '6:00 PM → 2:00 AM next day · Fri–Sun'],
      ['Old split', '10:00 AM – 2:00 PM · Mon, Tue', 'Not in use'],
    ]);
    // Wide, nothing picked: the weekly roster.
    expect(t.doc().querySelector('app-roster-view')).not.toBeNull();
  });

  it('a shift shows its length after the break and who works it', async () => {
    t = await startPage('/staff/shifts?id=sh2');
    expect(t.text(detail().querySelector('h2'))).toBe('Night');
    const text = t.text(detail())!;
    expect(text).toContain('6:00 PM → 2:00 AM next day');
    expect(text).toContain('Ends next day 2:00 AM');
    expect(text).toContain('Paid length 7h 30m');
    expect(text).toContain('Unpaid break 30m');
    expect(text).toContain('Rohan Das 1 Sept 2026 – 31 Dec 2026');
  });

  it('adds a shift that crosses midnight (client uuid, contract payload)', async () => {
    t = await startPage('/staff/shifts');
    addShift().click();
    await t.settle();
    t.type('Name', 'Late', t.dialog()!);
    const [start, end] = [...t.dialog()!.querySelectorAll('input[type="time"]')] as HTMLInputElement[];
    set(start, '20:00');
    set(end, '03:30');
    t.type('Unpaid break', '30', t.dialog()!);
    await t.settle();
    expect(t.text(t.dialog()!.querySelector('p[aria-live]'))).toBe(
      '8:00 PM → 3:30 AM next day · 7h paid after a 30m break',
    );
    t.button('Add shift', t.dialog()!)!.click();
    await t.settle();
    const op = t.shifts.ops[0];
    expect(op.kind).toBe('shift.upsert');
    expect(op.payload['id']).toMatch(/^[0-9a-f-]{36}$/);
    expect({ ...op.payload, id: 'x' }).toEqual({
      id: 'x',
      name: 'Late',
      start_min: 1200,
      end_min: 210,
      days: [1, 2, 3, 4, 5, 6],
      break_min: 30,
      active: true,
    });
    expect(t.snack()).toBe('Late added');
    expect(t.url()).toBe(`/staff/shifts?id=${op.payload['id']}`);
  });

  it('a taken shift name is refused in the dialog', async () => {
    t = await startPage('/staff/shifts?id=sh2');
    t.button('Edit', detail())!.click();
    await t.settle();
    t.type('Name', 'MORNING', t.dialog()!);
    await t.settle();
    t.button('Save', t.dialog()!)!.click();
    await t.settle();
    expect(t.text(t.dialog()!)).toContain('Another shift already has that name');
    expect(t.shifts.ops).toEqual([]);
  });

  it('assigns staff with dates (open-ended → null) and changes the dates by the same id', async () => {
    t = await startPage('/staff/shifts?id=sh2');
    t.button('Assign staff', detail())!.click();
    await t.settle();
    (t.dialog()!.querySelector('mat-select') as HTMLElement).click();
    await t.settle();
    const kavya = [...t.doc().querySelectorAll('mat-option')].find((o) =>
      o.textContent?.includes('Kavya'),
    ) as HTMLElement;
    kavya.click();
    await t.settle();
    const [from] = [...t.dialog()!.querySelectorAll('input[type="date"]')] as HTMLInputElement[];
    set(from, '2026-10-16');
    await t.settle();
    t.button('Assign', t.dialog()!)!.click();
    await t.settle();
    const op = t.shifts.ops[0];
    expect(op.kind).toBe('shift.assign');
    expect({ ...op.payload, id: 'x' }).toEqual({
      id: 'x',
      staff_id: 's3',
      shift_id: 'sh2',
      effective_from: '2026-10-16',
      effective_to: null,
    });
    expect(t.snack()).toBe('Kavya Iyer assigned to Night');
    expect(t.text(detail())).toContain('Kavya Iyer From 16 Oct 2026 · no end date');

    (detail().querySelector('button[aria-label="Change dates for Rohan Das"]') as HTMLElement).click();
    await t.settle();
    const [, to] = [...t.dialog()!.querySelectorAll('input[type="date"]')] as HTMLInputElement[];
    set(to, '2026-11-30');
    await t.settle();
    t.button('Save', t.dialog()!)!.click();
    await t.settle();
    expect(t.shifts.ops[1]).toEqual({
      kind: 'shift.assign',
      payload: {
        id: 'as2',
        staff_id: 's2',
        shift_id: 'sh2',
        effective_from: '2026-09-01',
        effective_to: '2026-11-30',
      },
    });
  });

  it('an overlapping assignment of the same shift is explained in words', async () => {
    t = await startPage('/staff/shifts?id=sh1');
    t.button('Assign staff', detail())!.click();
    await t.settle();
    (t.dialog()!.querySelector('mat-select') as HTMLElement).click();
    await t.settle();
    (
      [...t.doc().querySelectorAll('mat-option')].find((o) =>
        o.textContent?.includes('Priya'),
      ) as HTMLElement
    ).click();
    await t.settle();
    const [from] = [...t.dialog()!.querySelectorAll('input[type="date"]')] as HTMLInputElement[];
    set(from, '2026-11-01');
    await t.settle();
    t.button('Assign', t.dialog()!)!.click();
    await t.settle();
    expect(t.text(t.dialog()!)).toContain(
      'They already have this shift for some of those dates. Change the dates, or edit the other assignment (From 1 Oct 2026 · no end date)',
    );
    expect(t.shifts.ops).toEqual([]);
  });

  it('the server refusing an overlap is worded the same way', async () => {
    t = await startPage('/staff/shifts?id=sh1');
    await expect(
      t.shifts.push('a1', [
        {
          kind: 'shift.assign',
          payload: {
            id: 'z',
            staff_id: 's1',
            shift_id: 'sh1',
            effective_from: '2026-12-01',
            effective_to: null,
          },
        },
      ]),
    ).rejects.toThrow(
      'They already have this shift for some of those dates. Change the dates, or edit the other assignment',
    );
  });

  it('removes an assignment after confirming', async () => {
    t = await startPage('/staff/shifts?id=sh1');
    (detail().querySelector('button[aria-label="Remove Priya Nair from Morning"]') as HTMLElement).click();
    await t.settle();
    t.button('Remove', t.dialog()!)!.click();
    await t.settle();
    expect(t.shifts.ops).toEqual([{ kind: 'shift.unassign', payload: { id: 'as1' } }]);
    expect(t.text(detail())).not.toContain('Priya Nair');
  });

  it('the weekly roster shows each day’s shifts and week offs', async () => {
    t = await startPage('/staff/shifts?id=roster&week=2026-10-15');
    const roster = t.doc().querySelector('app-roster-view') as HTMLElement;
    const heads = [...roster.querySelectorAll('thead th')].map((th) => t.text(th));
    expect(heads[1]).toBe('Mon, 12 Oct');
    expect(heads[7]).toBe('Sun, 18 Oct');
    const rohan = [...roster.querySelectorAll('tbody tr')].find((r) =>
      r.textContent?.includes('Rohan'),
    )!;
    expect([...rohan.querySelectorAll('td')].map((td) => t.text(td))).toEqual([
      'Week off',
      'Week off',
      'Week off',
      'Week off',
      'Night',
      'Night',
      'Night',
    ]);
    (roster.querySelector('button[aria-label="Next week"]') as HTMLElement).click();
    await t.settle();
    expect(t.url()).toContain('week=2026-10-22');
  });

  it('staff holidays: add (paid by default), and copy only the arena holidays missing', async () => {
    t = await startPage('/staff/shifts?id=holidays');
    expect(t.text(holidays())).toContain('Diwali 20 Oct 2026 Paid');
    t.button('Copy from arena holidays', holidays())!.click();
    await t.settle();
    expect(t.shifts.holidayReads).toEqual([['2026-10-01', '2027-10-31']]);
    const offered = [...t.dialog()!.querySelectorAll('mat-checkbox')].map((c) => t.text(c));
    expect(offered).toEqual(['Guru Nanak Jayanti · 5 Nov 2026', 'Christmas · 25 Dec 2026']);
    t.button('Add 2 holidays', t.dialog()!)!.click();
    await t.settle();
    expect(t.shifts.pushes).toEqual([
      [
        {
          kind: 'staff_holiday.upsert',
          payload: { day: '2026-11-05', name: 'Guru Nanak Jayanti', paid: true },
        },
        { kind: 'staff_holiday.upsert', payload: { day: '2026-12-25', name: 'Christmas', paid: true } },
      ],
    ]);
    expect(t.snack()).toBe('2 staff holidays added');

    // Nothing left to copy.
    t.button('Copy from arena holidays', holidays())!.click();
    await t.settle();
    expect(t.dialog()).toBeNull();
    expect(t.snack()).toBe('Every arena holiday in the next 12 months is already a staff holiday');
  });

  it('staff holidays: edit moves the day (upsert + delete in one call); delete confirms', async () => {
    t = await startPage('/staff/shifts?id=holidays');
    (holidays().querySelector('button[aria-label="Edit Diwali"]') as HTMLElement).click();
    await t.settle();
    set(dialogInput('input[type="date"]'), '2026-10-21');
    (t.dialog()!.querySelector('mat-slide-toggle button') as HTMLElement).click();
    await t.settle();
    t.button('Save', t.dialog()!)!.click();
    await t.settle();
    expect(t.shifts.pushes[0]).toEqual([
      { kind: 'staff_holiday.upsert', payload: { day: '2026-10-21', name: 'Diwali', paid: false } },
      { kind: 'staff_holiday.delete', payload: { day: '2026-10-20' } },
    ]);
    expect(t.text(holidays())).toContain('Diwali 21 Oct 2026 Unpaid');
    (holidays().querySelector('button[aria-label="Delete Diwali"]') as HTMLElement).click();
    await t.settle();
    t.button('Delete', t.dialog()!)!.click();
    await t.settle();
    expect(t.shifts.pushes[1]).toEqual([
      { kind: 'staff_holiday.delete', payload: { day: '2026-10-21' } },
    ]);
  });

  it('read-only without the Settings permission', async () => {
    t = await startPage('/staff/shifts?id=sh1', 1440, ({ arena }) => {
      arena.memberships = arena.memberships.map((m) => ({
        ...m,
        role: 'staff' as const,
        perms: ['money', 'reports'],
      }));
    });
    expect(t.url()).toBe('/staff/shifts?id=sh1');
    expect(navLabels()).toContain('Shifts & holidays');
    expect(t.text(detail())).toContain('Viewing only: changing shifts needs the Settings permission.');
    expect(t.button('Edit', detail())!.disabled).toBe(true);
    expect(t.button('Assign staff', detail())!.disabled).toBe(true);
    expect(
      (detail().querySelector('button[aria-label="Remove Priya Nair from Morning"]') as HTMLButtonElement)
        .disabled,
    ).toBe(true);
    expect(addShift().disabled).toBe(true);
  });
});
