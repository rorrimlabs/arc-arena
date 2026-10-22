import { PageTest, startPage } from '../../testing/page-test';

describe('Staff › Attendance: corrections', () => {
  let t: PageTest;

  afterEach(() => t?.cleanup());

  const detail = () => t.doc().querySelector('app-entry-detail') as HTMLElement;
  const names = () =>
    [...t.doc().querySelectorAll('app-entry-row a')].map((a) =>
      t.text(a.querySelector('span.truncate')),
    );
  function set(el: HTMLInputElement | HTMLTextAreaElement, value: string) {
    el.value = value;
    el.dispatchEvent(new Event('input'));
  }
  const field = (label: string) =>
    t.dialog()!.querySelector(`input[aria-label="${label}"]`) as HTMLInputElement;
  const reason = () => t.dialog()!.querySelector('textarea') as HTMLTextAreaElement;
  async function pick(name: string) {
    (t.dialog()!.querySelector('mat-select') as HTMLElement).click();
    await t.settle();
    (
      [...t.doc().querySelectorAll('mat-option')].find((o) =>
        o.textContent?.includes(name),
      ) as HTMLElement
    ).click();
    await t.settle();
  }

  it('accepts a pending entry with an optional note', async () => {
    t = await startPage('/staff/attendance/records?id=e2');
    t.button('Accept', detail())!.click();
    await t.settle();
    set(reason(), 'Went out for stock');
    t.button('Accept', t.dialog()!)!.click();
    await t.settle();
    expect(t.attendance.ops).toEqual([
      { kind: 'attendance.review', payload: { entry_id: 'e2', note: 'Went out for stock' } },
    ]);
    expect(t.snack()).toBe('Entry accepted');
    expect(t.text(detail())).toContain('Accepted');
    expect(t.button('Accept', detail())).toBeUndefined();
  });

  it('corrects times in IST (reason required), then shows the new row and where it came from', async () => {
    t = await startPage('/staff/attendance/records?id=e2');
    t.button('Correct times', detail())!.click();
    await t.settle();
    expect(field('Clock-in date').value).toBe('2026-10-13');
    expect(field('Clock-in time').value).toBe('10:00');
    expect(field('Clock-out time').value).toBe('18:10');
    set(field('Clock-out time'), '18:00');
    await t.settle();
    t.button('Save correction', t.dialog()!)!.click();
    await t.settle();
    expect(t.text(t.dialog()!)).toContain('Give a reason for the change');
    expect(t.attendance.ops).toEqual([]);

    set(reason(), 'Left at 6, phone was off');
    await t.settle();
    t.button('Save correction', t.dialog()!)!.click();
    await t.settle();
    expect(t.attendance.ops).toEqual([
      {
        kind: 'attendance.correct',
        payload: {
          action: 'edit',
          entry_id: 'e2',
          in_at: '2026-10-13T04:30:00.000Z',
          out_at: '2026-10-13T12:30:00.000Z',
          reason: 'Left at 6, phone was off',
        },
      },
    ]);
    expect(t.snack()).toBe("Rohan Das's entry corrected");
    expect(t.url()).toBe('/staff/attendance/records?id=c1');
    await t.settle();
    const text = t.text(detail())!;
    expect(text).toContain('Corrected');
    expect(text).toContain(
      'Corrected from 10:00 am–6:10 pm by Arjun Mehra · Left at 6, phone was off',
    );
    // The superseded row is not listed by default…
    expect(names().filter((n) => n === 'Rohan Das')).toHaveLength(1);
  });

  it('an open entry can be corrected without a clock-out', async () => {
    t = await startPage('/staff/attendance/records?id=e1');
    t.button('Correct times', detail())!.click();
    await t.settle();
    expect(field('Clock-out time').value).toBe('');
    set(field('Clock-in time'), '09:00');
    set(reason(), 'Clocked in late by mistake');
    await t.settle();
    t.button('Save correction', t.dialog()!)!.click();
    await t.settle();
    expect(t.attendance.ops[0].payload).toEqual({
      action: 'edit',
      entry_id: 'e1',
      in_at: '2026-10-13T03:30:00.000Z',
      out_at: null,
      reason: 'Clocked in late by mistake',
    });
  });

  it('times are checked first: out after in, not in the future', async () => {
    t = await startPage('/staff/attendance/records?id=e2');
    t.button('Correct times', detail())!.click();
    await t.settle();
    set(reason(), 'Fix');
    set(field('Clock-out time'), '09:00');
    await t.settle();
    t.button('Save correction', t.dialog()!)!.click();
    await t.settle();
    expect(t.text(t.dialog()!)).toContain('The clock-out must be after the clock-in');
    set(field('Clock-out time'), '23:00');
    await t.settle();
    t.button('Save correction', t.dialog()!)!.click();
    await t.settle();
    expect(t.text(t.dialog()!)).toContain('The clock-out can’t be in the future');
    expect(t.attendance.ops).toEqual([]);
  });

  it('voids with a reason after confirming; voided rows show only on request', async () => {
    t = await startPage('/staff/attendance/records?id=e3');
    t.button('Void', detail())!.click();
    await t.settle();
    t.button('Void entry', t.dialog()!)!.click();
    await t.settle();
    expect(t.text(t.dialog()!)).toContain('Give a reason for the change');
    set(reason(), 'Duplicate of a paper record');
    t.button('Void entry', t.dialog()!)!.click();
    await t.settle();
    expect(t.attendance.ops).toEqual([
      {
        kind: 'attendance.correct',
        payload: { action: 'void', entry_id: 'e3', reason: 'Duplicate of a paper record' },
      },
    ]);
    expect(t.snack()).toBe('Entry voided');
    expect(t.url()).toBe('/staff/attendance/records');
    expect(names()).toEqual(['Rohan Das', 'Priya Nair', 'Priya Nair', 'Kavya Iyer']);

    await t.harness.navigateByUrl('/staff/attendance/records?all=1&id=e3');
    await t.settle();
    expect(t.attendance.inactiveLoads.at(-1)).toBe(true);
    expect(names()).toHaveLength(5);
    expect(t.text(detail())).toContain('Voided');
    // A row that no longer counts cannot be changed.
    expect(t.button('Correct times', detail())).toBeUndefined();
  });

  it('adds a missing entry: staff, in, out and a reason', async () => {
    t = await startPage('/staff/attendance/records');
    t.button('Add missing entry')!.click();
    await t.settle();
    await pick('Kavya');
    set(field('Clock-in date'), '2026-10-11');
    set(field('Clock-in time'), '10:00');
    set(field('Clock-out date'), '2026-10-11');
    await t.settle();
    t.button('Add entry', t.dialog()!)!.click();
    await t.settle();
    expect(t.text(t.dialog()!)).toContain('Pick the clock-out date and time');
    set(field('Clock-out time'), '18:00');
    set(reason(), 'Forgot her phone');
    await t.settle();
    t.button('Add entry', t.dialog()!)!.click();
    await t.settle();
    expect(t.attendance.ops).toEqual([
      {
        kind: 'attendance.correct',
        payload: {
          action: 'add',
          staff_id: 's3',
          in_at: '2026-10-11T04:30:00.000Z',
          out_at: '2026-10-11T12:30:00.000Z',
          reason: 'Forgot her phone',
        },
      },
    ]);
    expect(t.snack()).toBe('Entry added for Kavya Iyer');
    expect(t.url()).toBe('/staff/attendance/records?id=m1');
    expect(t.text(detail())).toContain('Added by hand by Arjun Mehra: Forgot her phone');
  });

  it('a refusal is put in words in the dialog', async () => {
    t = await startPage('/staff/attendance/records?id=e4');
    t.attendance.refuseNext = 'period_finalised';
    t.button('Correct times', detail())!.click();
    await t.settle();
    set(reason(), 'Closed at 11 pm');
    set(field('Clock-out time'), '23:00');
    await t.settle();
    t.button('Save correction', t.dialog()!)!.click();
    await t.settle();
    expect(t.text(t.dialog()!)).toContain(
      'That day is in a finalised salary run, so it can’t change. Make the fix as an adjustment in the next run',
    );
  });

  it('a reviewer who is not the owner cannot change their own entries', async () => {
    t = await startPage('/staff/attendance/records?id=e1', 1440, ({ arena, attendance }) => {
      arena.memberships = arena.memberships.map((m) => ({
        ...m,
        role: 'staff' as const,
        perms: ['reports', 'attendance_review'],
      }));
      attendance.staff = attendance.staff.map((s) =>
        s.id === 's1' ? { ...s, userId: 'u0' } : s.id === 's0' ? { ...s, userId: null } : s,
      );
    });
    expect(t.text(detail())).toContain(
      'This is your own entry: someone else with Review attendance corrects or accepts it.',
    );
    expect(t.button('Correct times', detail())).toBeUndefined();
    expect(t.button('Void', detail())).toBeUndefined();
    // Their own name is not offered for a missing entry either.
    t.button('Add missing entry')!.click();
    await t.settle();
    (t.dialog()!.querySelector('mat-select') as HTMLElement).click();
    await t.settle();
    const options = [...t.doc().querySelectorAll('mat-option')].map((o) => t.text(o));
    expect(options).not.toContain('Priya Nair');
    expect(options).toContain('Rohan Das');
    // Someone else's entry is theirs to review.
    await t.harness.navigateByUrl('/staff/attendance/records?id=e2');
    await t.settle();
    expect(t.button('Accept', detail())).toBeDefined();
  });

  it('the owner may correct their own entries', async () => {
    t = await startPage('/staff/attendance/records?id=e1', 1440, ({ attendance }) => {
      attendance.staff = asReviewerFor(attendance.staff, 's1');
    });
    expect(t.button('Correct times', detail())).toBeDefined();
    expect(t.text(detail())).not.toContain('This is your own entry');
  });
});

function asReviewerFor<T extends { id: string; userId: string | null }>(staff: T[], id: string): T[] {
  return staff.map((s) => (s.id === id ? { ...s, userId: 'u0' } : s));
}
