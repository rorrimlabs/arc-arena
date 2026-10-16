import { NAV_ITEMS } from '../../core/layout/nav';
import { PageTest, startPage } from '../../testing/page-test';

describe('Staff › Payroll', () => {
  let t: PageTest;

  afterEach(() => t?.cleanup());

  const navLabels = () =>
    [...t.doc().querySelectorAll('nav[aria-label="Main"] a')].map((a) => a.getAttribute('title'));
  const run = () => t.doc().querySelector('app-run-detail') as HTMLElement;
  const section = (heading: string) =>
    [...t.doc().querySelectorAll('app-detail-section')].find((s) =>
      t.text(s.querySelector('h3'))?.startsWith(heading),
    ) as HTMLElement;
  /** The timesheet's cells for a person, after the name. */
  const sheetRow = (name: string) => {
    const tr = [...run().querySelectorAll('tbody tr')].find(
      (r) => t.text(r.querySelector('th')) === name,
    )!;
    return [...tr.querySelectorAll('td')].map((td) => t.text(td));
  };
  const rowValue = (scope: Element, label: string) =>
    [...scope.querySelectorAll('app-detail-row')]
      .map((r) => [...r.querySelectorAll('span')].map((s) => t.text(s)))
      .find(([l]) => l === label)?.[1];
  const deduction = (label: string) =>
    [...t.doc().querySelectorAll('app-deduction-row')].find((d) =>
      t.text(d)?.startsWith(label),
    ) as HTMLElement;

  async function click(label: string, scope?: ParentNode) {
    t.button(label, scope)!.click();
    await t.settle();
  }

  function setDate(input: HTMLInputElement, value: string) {
    input.value = value;
    input.dispatchEvent(new Event('change'));
  }

  it('lists the pay runs for payroll holders', async () => {
    t = await startPage('/staff/payroll');
    expect(NAV_ITEMS.find((i) => i.path === 'staff/payroll')?.perm).toBe('payroll');
    expect(NAV_ITEMS.find((i) => i.path === 'staff/pay-setup')?.perm).toBe('payroll');
    expect(navLabels()).toContain('Payroll');
    const rows = t.rows().map((r) => t.text(r));
    expect(rows[0]).toContain('1–31 Oct 2026');
    expect(rows[0]).toContain('Draft');
    expect(rows[0]).toContain('₹37,780.64');
    expect(rows[1]).toContain('Finalised');
    expect(rows[1]).toContain('finalised 2 Oct by Arjun Mehra');
  });

  it('a run opens on the month-end timesheet (docs/STAFF.md §4.3 Examples 1 and 3)', async () => {
    t = await startPage('/staff/payroll?id=r-oct');
    expect(t.text(run().querySelector('h2'))).toBe('1–31 Oct 2026');
    expect(sheetRow('Ravi Kumar')).toEqual([
      'Fixed monthly',
      '26',
      '22',
      '4',
      '1',
      '1',
      '1',
      '1',
      '1',
      '4',
      '180h 00m',
      '0h 00m',
      '₹18,000.00',
      '−₹1,741.94',
      '−₹1,500.00',
      '₹14,758.06',
    ]);
    expect(sheetRow('Arjun Rao')).toEqual([
      'Fixed monthly',
      '26',
      '24',
      '0',
      '0',
      '0',
      '1',
      '1',
      '1',
      '4',
      '216h 00m',
      '24h 00m',
      '₹24,032.26',
      '−₹709.68',
      '−₹300.00',
      '₹23,022.58',
    ]);
  });

  it('Ravi’s breakdown: each suggested deduction with its formula (Example 1)', async () => {
    t = await startPage('/staff/payroll?id=r-oct&staff=st1');
    expect(t.text(run().querySelector('h2'))).toBe('Ravi Kumar');
    const pay = section('Pay');
    expect(rowValue(pay, 'Base pay')).toBe('₹18,000.00');
    expect(rowValue(pay, 'Gross')).toBe('₹18,000.00');
    expect(t.text(deduction('Absent'))).toContain('1 day × ₹580.65 = ₹580.65');
    expect(t.text(deduction('LOP leave'))).toContain('1 day × ₹580.65 = ₹580.65');
    expect(t.text(deduction('Half-day'))).toContain('0.5 day × ₹580.65 = ₹290.32');
    expect(t.text(deduction('Late'))).toContain('0.5 day × ₹580.65 = ₹290.32');
    expect(t.text(section('Adjustments'))).toContain('Advance · Oct 10 advance');
    expect(t.text(section('Adjustments'))).toContain('−₹2,000.00');
    expect(t.text(section('Adjustments'))).toContain('+₹500.00');
    expect(t.text(run())).toContain('Net pay ₹14,758.06');
    // The day-by-day timesheet.
    const days = [...section('Timesheet').querySelectorAll('tbody tr')].map((r) => t.text(r));
    expect(days).toHaveLength(31);
    expect(days[1]).toContain('Holiday');
    expect(days[1]).toContain('Gandhi Jayanti');
    expect(days[5]).toContain('Late 7h 45m');
  });

  it('waiving a deduction sends the decision and the net follows (Example 1: +₹290.32)', async () => {
    t = await startPage('/staff/payroll?id=r-oct&staff=st1');
    const late = deduction('Late');
    const note = late.querySelector('input') as HTMLInputElement;
    note.value = 'First month';
    note.dispatchEvent(new Event('input'));
    await t.settle();
    await click('Waive', late);
    expect(t.payroll.ops).toEqual([
      {
        kind: 'salary_run.set_deduction',
        payload: {
          run_id: 'r-oct',
          staff_id: 'st1',
          code: 'late',
          applied: false,
          note: 'First month',
        },
      },
    ]);
    expect(t.text(run())).toContain('Net pay ₹15,048.38');
    // Keep it again.
    await click('Keep', deduction('Late'));
    expect(t.payroll.ops[1].payload).toMatchObject({ code: 'late', applied: true });
    expect(t.text(run())).toContain('Net pay ₹14,758.06');
  });

  it('Arjun’s breakdown: a mid-period raise, derived extra hours, LOP (Example 3)', async () => {
    t = await startPage('/staff/payroll?id=r-oct&staff=st3');
    const pay = section('Pay');
    expect(rowValue(pay, 'Rate · 1–15 Oct 2026')).toBe(
      '₹20,000.00 / month · extra hours paid (derived rate)',
    );
    expect(rowValue(pay, 'Rate · 16–31 Oct 2026')).toBe(
      '₹22,000.00 / month · extra hours paid (derived rate)',
    );
    expect(rowValue(pay, 'Base pay')).toBe('₹21,032.26');
    expect(rowValue(pay, 'Extra hours pay · 24h 00m')).toBe('₹3,000.00');
    expect(rowValue(pay, 'Gross')).toBe('₹24,032.26');
    expect(t.text(deduction('LOP leave'))).toContain('1 day × ₹709.68 = ₹709.68');
    expect(t.text(section('Adjustments'))).toContain('Deduction · Cracked controller, 20 Oct');
    expect(t.text(run())).toContain('Net pay ₹23,022.58');
    const sunday = [...section('Timesheet').querySelectorAll('tbody tr')].find((r) =>
      t.text(r.querySelector('th'))?.includes('4 Oct'),
    )!;
    expect(t.text(sunday)).toContain('Present 12h 00m 4h 00m');
  });

  it('Priya’s hourly week: regular and extra hours, no late rule (Example 2)', async () => {
    t = await startPage('/staff/payroll?id=r-wk&staff=st2', 1440, ({ payroll }) =>
      payroll.useWeekly(),
    );
    const pay = section('Pay');
    expect(rowValue(pay, 'Rate · 5–11 Oct 2026')).toBe(
      '₹120.00 / h · extra hours paid (derived rate)',
    );
    expect(rowValue(pay, 'Base pay')).toBe('₹4,500.00');
    expect(rowValue(pay, 'Extra hours pay · 1h 45m')).toBe('₹315.00');
    expect(t.text(section('Deductions'))).toContain('No deductions suggested.');
    expect(t.text(run())).toContain('Net pay ₹4,815.00');
    const days = [...section('Timesheet').querySelectorAll('tbody tr')].map((r) => t.text(r));
    expect(days).toHaveLength(7);
    expect(days[2]).toContain('Week off');
    expect(days[4]).toContain('9h 45m 1h 45m');
    expect(days[5]).toContain('Closed automatically');
  });

  it('adds an adjustment: positive paise and the kind (the server signs it)', async () => {
    t = await startPage('/staff/payroll?id=r-oct&staff=st1');
    await click('Add adjustment', section('Adjustments'));
    const dialog = t.dialog()!;
    const advance = [...dialog.querySelectorAll('mat-radio-button')].find((r) =>
      t.text(r)?.startsWith('Advance'),
    )!;
    (advance.querySelector('input') as HTMLInputElement).click();
    t.type('Amount', '1,000.50', dialog);
    await t.settle();
    expect(t.text(dialog)).toContain('Takes ₹1,000.50 off pay');
    await click('Add', dialog.querySelector('mat-dialog-actions')!);
    expect(t.text(dialog.querySelector('[role="alert"]'))).toBe(
      'Write a note saying what this is for',
    );
    t.type('Note', 'Second advance', dialog);
    await click('Add', dialog.querySelector('mat-dialog-actions')!);
    const op = t.payroll.ops[0];
    expect(op.kind).toBe('salary_adjustment.add');
    expect(op.payload).toMatchObject({
      run_id: 'r-oct',
      staff_id: 'st1',
      kind: 'advance',
      amount_paise: 100_050,
      note: 'Second advance',
    });
    expect(typeof op.payload['id']).toBe('string');
    expect(t.snack()).toBe('Adjustment added');
    expect(t.text(run())).toContain('Net pay ₹13,757.56');
  });

  it('reverses an adjustment with a note (append-only)', async () => {
    t = await startPage('/staff/payroll?id=r-oct&staff=st1');
    await click('Reverse', section('Adjustments'));
    const dialog = t.dialog()!;
    expect(t.text(dialog)).toContain('Advance of ₹2,000.00');
    await click('Reverse', dialog.querySelector('mat-dialog-actions')!);
    expect(t.text(dialog.querySelector('[role="alert"]'))).toBe('Write a note saying why');
    t.type('Why', 'Paid back in cash', dialog);
    await click('Reverse', dialog.querySelector('mat-dialog-actions')!);
    expect(t.payroll.ops[0]).toMatchObject({
      kind: 'salary_adjustment.reverse',
      payload: { reverses_id: 'ad1', note: 'Paid back in cash' },
    });
    expect(t.text(section('Adjustments'))).toContain('reversed');
    expect(t.text(run())).toContain('Net pay ₹16,758.06');
  });

  it('recalculate, then finalise (confirmed): the run becomes read-only', async () => {
    t = await startPage('/staff/payroll?id=r-oct');
    await click('Recalculate', run());
    expect(t.payroll.ops[0]).toEqual({ kind: 'salary_run.recalculate', payload: { id: 'r-oct' } });
    await click('Finalise…', run());
    expect(t.text(t.dialog())).toContain(
      'Attendance and leave on these dates can no longer change',
    );
    await click('Finalise', t.dialog()!.querySelector('mat-dialog-actions')!);
    expect(t.payroll.ops[1]).toEqual({ kind: 'salary_run.finalise', payload: { id: 'r-oct' } });
    expect(t.text(run().querySelector('app-status-pill'))).toBe('Finalised');
    expect(t.button('Recalculate', run())).toBeUndefined();
    expect(t.button('Finalise…', run())).toBeUndefined();
    await t.harness.navigateByUrl('/staff/payroll?id=r-oct&staff=st1');
    await t.settle();
    expect(t.button('Add adjustment', run())).toBeUndefined();
    expect(t.button('Reverse', run())).toBeUndefined();
    const toggle = deduction('Late').querySelector('mat-button-toggle-group');
    expect(
      toggle?.getAttribute('aria-disabled') === 'true' ||
        !!toggle?.querySelector('button[disabled]'),
    ).toBe(true);
  });

  it('finalise refused for a net below zero names the person', async () => {
    t = await startPage('/staff/payroll?id=r-oct', 1440, ({ payroll }) => {
      payroll.lines = payroll.lines.map((l) =>
        l.runId === 'r-oct' && l.staffId === 'st3' ? { ...l, netPaise: -5_000 } : l,
      );
    });
    await click('Finalise…', run());
    await click('Finalise', t.dialog()!.querySelector('mat-dialog-actions')!);
    expect(t.text(run().querySelector('[role="alert"]'))).toBe(
      'Net pay would be below zero for Arjun Rao. Waive a deduction or reverse an adjustment first.',
    );
    expect(t.text(run().querySelector('app-status-pill'))).toBe('Draft');
  });

  it('discard a draft (confirmed)', async () => {
    t = await startPage('/staff/payroll?id=r-oct');
    await click('Discard draft…', run());
    await click('Discard draft', t.dialog()!.querySelector('mat-dialog-actions')!);
    expect(t.payroll.ops).toEqual([{ kind: 'salary_run.discard', payload: { id: 'r-oct' } }]);
    expect(t.text(run().querySelector('app-status-pill'))).toBe('Discarded');
  });

  it('new draft: suggests the next period and refuses overlaps before the server', async () => {
    t = await startPage('/staff/payroll');
    await click('New draft');
    const dialog = t.dialog()!;
    const [first, last] = [...dialog.querySelectorAll('input[type="date"]')] as HTMLInputElement[];
    expect([first.value, last.value]).toEqual(['2026-11-01', '2026-11-30']);
    expect(t.text(dialog)).toContain('Draft for 1–30 Nov 2026');
    setDate(first, '2026-10-20');
    await t.settle();
    expect(t.text(dialog.querySelector('#new-run-problem'))).toBe(
      'Overlaps the draft run for 1–31 Oct 2026',
    );
    expect(t.button('Create draft', dialog)!.disabled).toBe(true);
    setDate(first, '2026-11-01');
    await t.settle();
    await click('Create draft', dialog);
    const op = t.payroll.ops[0];
    expect(op.kind).toBe('salary_run.create');
    expect(op.payload).toMatchObject({ period_start: '2026-11-01', period_end: '2026-11-30' });
    expect(t.url()).toBe(`/staff/payroll?id=${op.payload['id']}`);
    expect(t.text(run().querySelector('h2'))).toBe('1–30 Nov 2026');
  });

  it('weekly pay rules suggest the next week from the week start', async () => {
    t = await startPage('/staff/payroll', 1440, ({ payroll }) => payroll.useWeekly());
    await click('New draft');
    const [first, last] = [
      ...t.dialog()!.querySelectorAll('input[type="date"]'),
    ] as HTMLInputElement[];
    expect([first.value, last.value]).toEqual(['2026-10-12', '2026-10-18']);
  });

  it('exports the timesheet and summary CSV, and opens the print view', async () => {
    t = await startPage('/staff/payroll?id=r-oct');
    await click('Timesheet CSV', run());
    expect(t.snack()).toBe('Timesheet exported');
    await click('Summary CSV', run());
    expect(t.snack()).toBe('Summary exported');
    const print = t.button('Print / Save as PDF', run()) as unknown as HTMLAnchorElement;
    expect(print.getAttribute('href')).toBe('/staff/payroll/print?id=r-oct&auto=1');
  });

  it('the print view: summary table, totals and each person’s deductions', async () => {
    t = await startPage('/staff/payroll/print?id=r-oct');
    const page = t.doc().querySelector('app-payroll-print') as HTMLElement;
    expect(t.text(page.querySelector('h1'))).toBe('404 Arena Koramangala — Pay summary');
    expect(t.text(page)).toContain('1–31 Oct 2026 · Draft');
    expect(t.text(page.querySelector('tfoot'))).toContain('₹37,780.64');
    const ravi = t.text(page.querySelector('section[aria-label="Ravi Kumar"]'));
    expect(ravi).toContain('Ravi Kumar · net ₹14,758.06');
    expect(ravi).toContain('Late (4 lates, every 3 = ½ day): 0.5 day × ₹580.65 = ₹290.32 — kept');
    expect(ravi).toContain('Bonus +₹500.00 — Diwali');
  });

  it('payroll without payroll_finalise: drafts and decisions, but no finalise or discard', async () => {
    t = await startPage('/staff/payroll?id=r-oct', 1440, ({ arena }) => {
      arena.memberships = arena.memberships.map((m) => ({
        ...m,
        role: 'staff' as const,
        perms: ['reports', 'payroll'],
      }));
    });
    expect(t.button('Recalculate', run())).toBeDefined();
    expect(t.button('Finalise…', run())).toBeUndefined();
    expect(t.button('Discard draft…', run())).toBeUndefined();
    expect(t.text(run())).toContain('Finalising or discarding needs the Finalise pay permission.');
  });

  it('without payroll the screens and nav entries are gone', async () => {
    t = await startPage('/staff/payroll', 1440, ({ arena }) => {
      arena.memberships = arena.memberships.map((m) => ({
        ...m,
        role: 'staff' as const,
        perms: ['reports', 'leave_approve', 'payroll_finalise'],
      }));
    });
    expect(t.url()).toBe('/overview');
    expect(navLabels()).not.toContain('Payroll');
    expect(navLabels()).not.toContain('Pay setup');
    expect(navLabels()).toContain('Leave');
  });
});
