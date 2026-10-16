import { PageTest, startPage } from '../../../testing/page-test';
import { DEFAULT_LEAVE_RULES, leaveRulesJson, parseLeaveRules } from '../data/leave-rules';

describe('Settings › Leave rules', () => {
  let t: PageTest;

  afterEach(() => t?.cleanup());

  const pane = () => t.doc().querySelector('app-leave-settings') as HTMLElement;

  it('the whole object goes to settings.save (key leave_rules)', () => {
    expect(leaveRulesJson(DEFAULT_LEAVE_RULES)).toEqual({
      paid_leave_days: 12,
      half_day_allowed: true,
      unplanned_backdate_days: 7,
    });
    expect(
      parseLeaveRules({
        paid_leave_days: 10.5,
        half_day_allowed: false,
        unplanned_backdate_days: 40,
      }),
    ).toEqual({
      paidLeaveDays: 10.5,
      halfDayAllowed: false,
      unplannedBackdateDays: 7,
    });
  });

  it('shows the defaults with the leave-year help, and saves the whole setting', async () => {
    t = await startPage('/settings?id=leave');
    const rows = t.rows().map((r) => t.text(r));
    expect(rows.some((r) => r?.includes('Leave rules'))).toBe(true);
    expect(t.text(pane().querySelector('h2'))).toBe('Leave rules');
    expect(t.text(pane())).toContain(
      "The leave year starts on each person's joining date. Unused days don't carry over.",
    );
    t.type('Paid leave days per year', '1.3', pane());
    await t.settle();
    t.button('Save', pane())!.click();
    await t.settle();
    expect(t.text(pane())).toContain('Paid leave must be 0 to 366 days, in whole or half days');
    expect(t.leaveRules.writes).toEqual([]);
    t.type('Paid leave days per year', '15', pane());
    t.type('Can be applied up to', '3', pane());
    (pane().querySelector('app-toggle-row button') as HTMLButtonElement).click();
    await t.settle();
    t.button('Save', pane())!.click();
    await t.settle();
    expect(t.leaveRules.writes).toEqual([
      { paid_leave_days: 15, half_day_allowed: false, unplanned_backdate_days: 3 },
    ]);
    expect(t.snack()).toBe('Leave rules saved');
  });

  it('read-only without the Settings permission', async () => {
    t = await startPage('/settings?id=leave', 1440, ({ arena }) => {
      arena.memberships = arena.memberships.map((m) => ({
        ...m,
        role: 'staff' as const,
        perms: ['reports', 'leave_approve'],
      }));
    });
    const input = pane().querySelector('input') as HTMLInputElement;
    expect(input.disabled).toBe(true);
  });
});
