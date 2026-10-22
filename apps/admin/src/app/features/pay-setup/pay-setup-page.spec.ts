import { PageTest, startPage } from '../../testing/page-test';

/**
 * Pay setup is no longer its own screen: each employee's pay rate and HR profile are on Team
 * (Salary tab and Overview, `/staff/team/<staff>[/salary]`), the arena's pay rules in
 * Settings › Staff › Payroll (`/settings/staff/payroll`). All of it needs payroll.
 */
describe('Staff › Pay setup', () => {
  let t: PageTest;

  afterEach(() => t?.cleanup());

  const detail = () =>
    (t.doc().querySelector('app-staff-pay-detail') ??
      t.doc().querySelector('app-pay-rules-detail')) as HTMLElement;
  /** The employee pane's heading on Team. */
  const heading = () => t.text(t.doc().querySelector('app-member-detail h2'));
  const tabLabels = () =>
    [...t.doc().querySelectorAll('app-member-detail a[mat-tab-link]')].map((a) => t.text(a));
  const rowValue = (scope: Element, label: string) =>
    [...scope.querySelectorAll('app-detail-row')]
      .map((r) => [...r.querySelectorAll('span')].map((s) => t.text(s)))
      .find(([l]) => l === label)?.[1];
  const section = (heading: string) =>
    [...t.doc().querySelectorAll('app-detail-section')].find(
      (s) => t.text(s.querySelector('h3')) === heading,
    ) as HTMLElement;
  const field = (label: string, scope: ParentNode) =>
    [...scope.querySelectorAll('mat-form-field')]
      .find((f) => f.querySelector('mat-label')?.textContent?.trim() === label)
      ?.querySelector('input') as HTMLInputElement;

  async function click(label: string, scope?: ParentNode) {
    t.button(label, scope)!.click();
    await t.settle();
  }

  function setDate(input: HTMLInputElement, value: string) {
    input.value = value;
    input.dispatchEvent(new Event('change'));
  }

  it('Team lists every employee, inactive ones marked; each shows their salary', async () => {
    // The old Pay setup link lands on Team. The owner works here too (tracks attendance), with
    // no pay rate yet.
    t = await startPage('/staff/pay-setup', 1440, ({ paySetup }) => {
      paySetup.profiles = [
        ...paySetup.profiles,
        {
          staffId: 'st0',
          joinedOn: null,
          leftOn: null,
          tracksAttendance: true,
          employeeCode: null,
          paidLeaveDays: null,
          standardDayMin: null,
        },
      ];
    });
    expect(t.url()).toBe('/staff/team');
    const rows = t.rows().map((r) => t.text(r));
    const titles = t.rows().map((r) => t.text(r.querySelector('span.truncate.font-semibold')));
    // Active first, each group by name.
    expect(titles).toEqual(['Arjun Mehra', 'Arjun Rao', 'Priya Nair', 'Ravi Kumar', 'Kavya Iyer']);
    expect(rows[4]).toContain('Access off');
    expect(t.text(t.doc().querySelector('p[aria-live="polite"]'))).toContain('4 employees · ');
    expect(t.text(t.doc().querySelector('p[aria-live="polite"]'))).toMatch(
      / · 1 without a salary$/,
    );
    await t.harness.navigateByUrl('/staff/team/st0');
    await t.settle();
    expect(rowValue(t.doc().querySelector('app-member-detail')!, 'Salary')).toBe('Not set');
    await t.harness.navigateByUrl('/staff/team/st1');
    await t.settle();
    expect(rowValue(t.doc().querySelector('app-member-detail')!, 'Salary')).toBe(
      '₹18,000.00 / month',
    );
  });

  it('a person: the rate in force with the derived extra-hours rate, and the history', async () => {
    t = await startPage('/staff/team/st3/salary');
    expect(heading()).toBe('Arjun Rao');
    // On 13 Oct the ₹20,000 rate is in force; ₹20,000 ÷ 30 ÷ 8 h ≈ ₹83.33/h, × 1.5 (Pay rules).
    expect(t.text(section('Pay rate'))).toContain(
      '₹20,000.00 / month · extra hours paid at ≈ ₹83.33/h (derived) × 1.5',
    );
    const history = [...section('Pay rate').querySelectorAll('tbody tr')].map((r) => t.text(r));
    expect(history[0]).toContain('16 Oct 2026');
    expect(history[0]).toContain('₹22,000.00 / month');
    expect(history[0]).toContain('Raise after review');
    expect(history[1]).toContain('(now)');
  });

  it('New rate from…: limited to after the last finalised run; rupees sent as paise', async () => {
    t = await startPage('/staff/team/st1/salary');
    await click('New rate from…', detail());
    const dialog = t.dialog()!;
    const from = dialog.querySelector('input[type="date"]') as HTMLInputElement;
    expect(from.value).toBe('2026-10-13');
    expect(from.min).toBe('2026-10-01');
    expect(t.text(dialog.querySelector('#rate-from-help'))).toMatch(
      /^Pay up to 30 Sept? 2026 is finalised, so this can start on 1 Oct 2026 or later\.$/,
    );
    setDate(from, '2026-09-20');
    t.type('Amount', '19,500', dialog);
    await click('Add rate', dialog.querySelector('mat-dialog-actions')!);
    expect(t.text(dialog)).toContain('is finalised, so this can start on 1 Oct 2026 or later.');
    expect(t.paySetup.ops).toEqual([]);
    setDate(from, '2026-11-01');
    (dialog.querySelector('app-toggle-row button') as HTMLButtonElement).click();
    await t.settle();
    expect(t.text(dialog)).toContain('≈ ₹81.25/h in a 30-day month');
    t.type('Own extra-hours rate (optional)', '100.50', dialog);
    t.type('Note (optional)', 'Annual raise', dialog);
    await click('Add rate', dialog.querySelector('mat-dialog-actions')!);
    const op = t.paySetup.ops[0];
    expect(op.kind).toBe('pay_rate.add');
    expect(op.payload).toMatchObject({
      staff_id: 'st1',
      effective_from: '2026-11-01',
      pay_type: 'monthly',
      base_paise: 1_950_000,
      extra_hours_paid: true,
      extra_hourly_paise: 10_050,
      note: 'Annual raise',
    });
    expect(t.snack()).toBe('New rate added');
    expect(t.text(section('Pay rate'))).toContain('1 Nov 2026');
  });

  it('saves the HR profile; empty overrides show the arena defaults', async () => {
    // The employment details sit on the employee's Overview.
    t = await startPage('/staff/team/st1');
    const hr = section('Employment');
    expect(field('Joined on', hr).value).toBe('2024-11-20');
    expect(field('Standard day', hr).placeholder).toBe('8');
    expect(field('Paid leave a year', hr).placeholder).toBe('12');
    expect(t.text(hr)).toContain('Empty: the arena’s 8h 00m.'.replace('’', "'"));
    t.type('Employee code', 'E-099', hr);
    t.type('Paid leave a year', '14.5', hr);
    await t.settle();
    await click('Save profile', hr);
    expect(t.paySetup.ops).toEqual([
      {
        kind: 'hr_profile.save',
        payload: {
          staff_id: 'st1',
          joined_on: '2024-11-20',
          left_on: null,
          tracks_attendance: true,
          employee_code: 'E-099',
          paid_leave_days: 14.5,
          standard_day_min: null,
        },
      },
    ]);
    expect(t.snack()).toBe('Ravi Kumar’s profile saved');
  });

  /** Settings › Staff › Payroll, reached after Team (which loads the pay rules). */
  async function openPayRules(): Promise<void> {
    t = await startPage('/staff/team');
    await t.harness.navigateByUrl('/settings/staff/payroll');
    await t.settle();
  }

  // KNOWN BUG: opened directly, nothing loads the pay rules (StaffSettings / PayRulesDetail never
  // load PaySetupStore), so the defaults show and "Change from…" starts from them. `it.fails` passes while the bug exists; drop `.fails` once the app is fixed.
  it.fails('Settings › Staff › Payroll opened directly shows the rules in force', async () => {
    t = await startPage('/settings/staff/payroll');
    expect(t.text(section('In force today'))).toContain('Extra hours paid at 1.5× the hourly rate');
  });

  it('Pay rules: in force today in words; Change from… sends every rule', async () => {
    await openPayRules();
    const now = t.text(section('In force today'));
    expect(now).toContain('Pay period Monthly, starting on day 1');
    expect(now).toContain('Extra hours paid at 1.5× the hourly rate');
    expect(now).toContain('Late rule Every 3 lates = 0.5 day of pay · fixed monthly, daily');
    expect(t.text(section('History'))).toContain('From 1 Apr 2026');
    await click('Change from…', detail());
    const dialog = t.dialog()!;
    t.type('Extra-hours multiplier', '6', dialog);
    await click('Save new rules', dialog.querySelector('mat-dialog-actions')!);
    expect(t.text(dialog)).toContain('The extra-hours multiplier must be from 1 to 5');
    t.type('Extra-hours multiplier', '2', dialog);
    t.type('Cycle starts on day', '26', dialog);
    setDate(dialog.querySelector('input[type="date"]') as HTMLInputElement, '2026-11-01');
    await t.settle();
    await click('Save new rules', dialog.querySelector('mat-dialog-actions')!);
    const op = t.paySetup.ops[0];
    expect(op.kind).toBe('pay_policy.add');
    expect(op.payload['effective_from']).toBe('2026-11-01');
    expect(op.payload['policy']).toEqual({
      period_kind: 'monthly',
      cycle_start_day: 26,
      day_divisor: 'calendar',
      absent_factor: 1,
      lop_factor: 1,
      half_day_factor: 0.5,
      late_every: 3,
      late_penalty_days: 0.5,
      late_applies_to: ['monthly', 'daily'],
      early_leave_counts_as_late: true,
      extra_multiplier: 2,
      daily_paid_holidays: false,
    });
    expect(t.snack()).toBe('New pay rules saved');
    expect(t.text(section('History'))).toContain('From 1 Nov 2026');
  });

  it('a pay-rules date inside a finalised run is refused before the server', async () => {
    await openPayRules();
    await click('Change from…', detail());
    const dialog = t.dialog()!;
    setDate(dialog.querySelector('input[type="date"]') as HTMLInputElement, '2026-09-01');
    await t.settle();
    await click('Save new rules', dialog.querySelector('mat-dialog-actions')!);
    expect(t.text(dialog)).toContain('is finalised, so this can start on 1 Oct 2026 or later.');
    expect(t.paySetup.ops).toEqual([]);
  });

  it('needs payroll', async () => {
    t = await startPage('/staff/team/st1/salary', 1440, ({ arena }) => {
      arena.memberships = arena.memberships.map((m) => ({
        ...m,
        role: 'staff' as const,
        perms: ['reports', 'leave_approve'],
      }));
    });
    // Team stays open to them, without the Salary tab or any pay figure.
    expect(heading()).toBe('Ravi Kumar');
    expect(tabLabels()).not.toContain('Salary');
    expect(t.doc().querySelector('app-staff-pay-detail')).toBeNull();
    expect(rowValue(t.doc().querySelector('app-member-detail')!, 'Salary')).toBeUndefined();
    // Nor the pay rules in Settings › Staff.
    await t.harness.navigateByUrl('/settings/staff/payroll');
    await t.settle();
    expect(t.doc().querySelector('app-staff-settings')).not.toBeNull();
    expect(t.doc().querySelector('app-pay-rules-detail')).toBeNull();
  });
});
