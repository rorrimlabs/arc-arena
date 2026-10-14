import { PageTest, startPage } from '../../testing/page-test';
import { formatHolidayDay, isCalendarDay } from './data/pricing.models';

describe('Pricing · Holidays', () => {
  let t: PageTest;
  const detail = () => t.doc().querySelector('app-holidays-detail') as HTMLElement | null;
  const sections = () =>
    [...detail()!.querySelectorAll('app-detail-section')].map((s) => ({
      heading: t.text(s.querySelector('h3')),
      rows: [...s.querySelectorAll('app-holiday-row')].map((r) =>
        [...r.querySelectorAll('span.truncate, span.text-muted, app-status-pill')].map((e) =>
          t.text(e),
        ),
      ),
    }));
  const rowButton = (name: string, action: 'Edit' | 'Delete') =>
    detail()!.querySelector(`button[aria-label="${action} ${name}"]`) as HTMLButtonElement;
  const field = (label: string) =>
    [...t.dialog()!.querySelectorAll('mat-form-field')]
      .find((f) => t.text(f.querySelector('mat-label')) === label)
      ?.querySelector('input') as HTMLInputElement;

  afterEach(() => t?.cleanup());

  it('lists holidays under the pricing rules with the next one', async () => {
    t = await startPage('/pricing');
    const row = t.rows().find((r) => t.rowText(r)[0] === 'Holidays')!;
    expect(t.rowText(row)).toEqual(['Holidays', 'Next: Diwali · Sun, 8 Nov 2026', '2 coming up']);
  });

  it('shows coming-up holidays, then past ones', async () => {
    t = await startPage('/pricing?id=holidays');
    expect(t.text(detail()!.querySelector('h2 + div'))).toBe('Next: Diwali · Sun, 8 Nov 2026');
    expect(sections()).toEqual([
      {
        heading: 'Coming up',
        rows: [
          ['Diwali', 'Sun, 8 Nov 2026', 'Open · no happy hour'],
          ['Christmas', 'Fri, 25 Dec 2026', 'Closed'],
        ],
      },
      {
        heading: 'Past',
        rows: [['Independence Day', 'Sat, 15 Aug 2026', 'Open · no happy hour']],
      },
    ]);
  });

  it('adds a closed holiday (holiday.upsert) and the price list reloads', async () => {
    t = await startPage('/pricing?id=holidays');
    t.button('Holiday', detail()!)!.click();
    await t.settle();
    // A new holiday starts on the arena's today.
    expect(field('Date').value).toBe('2026-10-13');
    t.type('Date', '2026-10-20', t.dialog()!);
    t.type('Name', '  Dussehra ', t.dialog()!);
    (t.dialog()!.querySelector('mat-slide-toggle button') as HTMLButtonElement).click();
    await t.settle();
    t.button('Add holiday', t.dialog()!)!.click();
    await t.settle();
    await t.settle();
    expect(t.dialog()).toBeNull();
    expect(t.snack()).toBe('Dussehra added · no happy hour on Tue, 20 Oct 2026');
    expect(t.pricing.ops).toEqual([
      { kind: 'holiday.upsert', payload: { day: '2026-10-20', name: 'Dussehra', closed: true } },
    ]);
    expect(sections()[0].rows[0]).toEqual(['Dussehra', 'Tue, 20 Oct 2026', 'Closed']);
  });

  it('refuses a day another holiday has, and a blank name', async () => {
    t = await startPage('/pricing?id=holidays');
    t.button('Holiday', detail()!)!.click();
    await t.settle();
    t.type('Date', '2026-12-25', t.dialog()!);
    t.type('Name', 'Xmas', t.dialog()!);
    await t.settle();
    t.button('Add holiday', t.dialog()!)!.click();
    await t.settle();
    expect(t.text(t.dialog()!.querySelector('[role="alert"]'))).toBe(
      'Fri, 25 Dec 2026 is already Christmas · edit that one instead',
    );
    t.type('Date', '2026-12-26', t.dialog()!);
    t.type('Name', '   ', t.dialog()!);
    await t.settle();
    t.button('Add holiday', t.dialog()!)!.click();
    await t.settle();
    expect(t.text(t.dialog()!.querySelector('[role="alert"]'))).toBe(
      'Enter a name of up to 60 characters',
    );
    expect(t.pricing.ops).toEqual([]);
  });

  it('moving a holiday to another day saves the new day, then clears the old one', async () => {
    t = await startPage('/pricing?id=holidays');
    rowButton('Diwali', 'Edit').click();
    await t.settle();
    expect(field('Name').value).toBe('Diwali');
    t.type('Date', '2026-11-09', t.dialog()!);
    await t.settle();
    t.button('Save', t.dialog()!)!.click();
    await t.settle();
    await t.settle();
    expect(t.snack()).toBe('Diwali saved');
    expect(t.pricing.ops).toEqual([
      { kind: 'holiday.upsert', payload: { day: '2026-11-09', name: 'Diwali', closed: false } },
      { kind: 'holiday.delete', payload: { day: '2026-11-08' } },
    ]);
    expect(t.pricing.holidays.map((h) => h.day)).toEqual([
      '2026-08-15',
      '2026-11-09',
      '2026-12-25',
    ]);
  });

  it('editing only the closed switch keeps the day (one upsert)', async () => {
    t = await startPage('/pricing?id=holidays');
    rowButton('Christmas', 'Edit').click();
    await t.settle();
    (t.dialog()!.querySelector('mat-slide-toggle button') as HTMLButtonElement).click();
    await t.settle();
    t.button('Save', t.dialog()!)!.click();
    await t.settle();
    expect(t.pricing.ops).toEqual([
      { kind: 'holiday.upsert', payload: { day: '2026-12-25', name: 'Christmas', closed: false } },
    ]);
  });

  it('deletes a holiday after confirming (holiday.delete)', async () => {
    t = await startPage('/pricing?id=holidays');
    rowButton('Christmas', 'Delete').click();
    await t.settle();
    expect(t.text(t.dialog())).toContain(
      'Fri, 25 Dec 2026 becomes a normal day: happy-hour prices apply again and the arena counts as open.',
    );
    t.button('Delete', t.dialog()!.querySelector('mat-dialog-actions')!)!.click();
    await t.settle();
    await t.settle();
    expect(t.snack()).toBe('Christmas deleted');
    expect(t.pricing.ops).toEqual([{ kind: 'holiday.delete', payload: { day: '2026-12-25' } }]);
    expect(sections()[0].rows.map((r) => r[0])).toEqual(['Diwali']);
  });

  it('a refused delete is shown and the holiday stays', async () => {
    t = await startPage('/pricing?id=holidays');
    t.pricing.failNext = 'forbidden';
    rowButton('Diwali', 'Delete').click();
    await t.settle();
    t.button('Delete', t.dialog()!.querySelector('mat-dialog-actions')!)!.click();
    await t.settle();
    expect(t.text(detail()!.querySelector('[role="alert"]'))).toBe(
      'You need the Settings permission for that',
    );
    expect(t.pricing.holidays.some((h) => h.name === 'Diwali')).toBe(true);
  });

  it('a member without the Settings permission sees holidays but cannot change them', async () => {
    t = await startPage('/pricing?id=holidays', 1440, (apis) => {
      apis.arena.memberships = apis.arena.memberships.map((m) => ({
        ...m,
        role: 'staff',
        perms: ['reports'],
      }));
    });
    expect(sections()[0].rows.length).toBe(2);
    expect(t.button('Holiday', detail()!)!.disabled).toBe(true);
    expect(rowButton('Diwali', 'Edit').disabled).toBe(true);
    expect(rowButton('Diwali', 'Delete').disabled).toBe(true);
  });
});

describe('holiday helpers', () => {
  it('formats a calendar day without shifting it', () => {
    expect(formatHolidayDay('2026-01-01')).toBe('Thu, 1 Jan 2026');
  });

  it('accepts only real dates', () => {
    expect(isCalendarDay('2026-02-28')).toBe(true);
    expect(isCalendarDay('2026-02-30')).toBe(false);
    expect(isCalendarDay('26-2-3')).toBe(false);
    expect(isCalendarDay('')).toBe(false);
  });
});
