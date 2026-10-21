import { NAV_ITEMS } from '../../core/layout/nav';
import { PageTest, startPage } from '../../testing/page-test';

describe('Staff › Leave', () => {
  let t: PageTest;

  afterEach(() => t?.cleanup());

  const navLabels = () =>
    [...t.doc().querySelectorAll('nav[aria-label="Main"] a')].map((a) => a.getAttribute('title'));
  const titles = () => t.rows().map((r) => t.text(r.querySelector('span.truncate.font-semibold')));
  const summary = () => t.text(t.doc().querySelector('p[aria-live="polite"]'));
  const detail = () => t.doc().querySelector('app-leave-request-detail') as HTMLElement;
  const section = (heading: string) =>
    [...t.doc().querySelectorAll('app-detail-section')].find(
      (s) => t.text(s.querySelector('h3')) === heading,
    ) as HTMLElement;

  async function click(label: string, scope?: ParentNode) {
    t.button(label, scope)!.click();
    await t.settle();
  }

  it('is in the Staff nav for leave approvers; Requests lists what waits, cancellations first', async () => {
    t = await startPage('/staff/leave');
    expect(NAV_ITEMS.find((i) => i.path === 'staff/leave')?.perm).toBe('leave_approve');
    expect(navLabels()).toEqual(expect.arrayContaining(['Leave', 'Pay setup', 'Payroll']));
    expect(summary()).toBe('4 waiting for a decision');
    expect(titles()).toEqual(['Priya Nair', 'Priya Nair', 'Ravi Kumar', 'Arjun Mehra']);
    expect(t.text(t.rows()[0])).toContain('Cancel requested');
    expect(t.text(t.rows()[2])).toContain('21–22 Oct 2026 · 2 days · Planned');
  });

  it('a request shows the days, the balance, its history and who else is off then', async () => {
    t = await startPage('/staff/leave?id=lr1');
    const d = detail();
    expect(t.text(d.querySelector('h2'))).toBe('Ravi Kumar');
    expect(t.text(d)).toContain('Working days counted 2 days');
    expect(t.text(d)).toContain('Reason Sister’s wedding');
    expect(t.text(section('Balance'))).toContain('Allowance 12');
    expect(t.text(section('Balance'))).toContain('Paid days used 11');
    expect(t.text(section('Balance'))).toContain('Balance 1');
    expect(t.text(section('History'))).toContain('Asked by Ravi Kumar');
    expect(t.text(section('Also off then'))).toContain('Arjun Rao');
    expect(t.text(section('Also off then'))).toContain('22 Oct 2026 · approved');
  });

  it('approve: pre-filled with what the balance covers, LOP shown live, paid_days sent', async () => {
    t = await startPage('/staff/leave?id=lr1');
    await click('Approve…', detail());
    const dialog = t.dialog()!;
    const input = dialog.querySelector('input[type="number"]') as HTMLInputElement;
    expect(input.value).toBe('1');
    expect(t.text(dialog.querySelector('#decide-split'))).toBe(
      '1 paid · 1 LOP — LOP is deducted from salary',
    );
    t.type('Paid days', '1.5', dialog);
    await t.settle();
    expect(t.text(dialog.querySelector('#decide-split'))).toBe(
      '1.5 paid · 0.5 LOP — LOP is deducted from salary',
    );
    t.type('Paid days', '3', dialog);
    await t.settle();
    expect(t.text(dialog.querySelector('#decide-split'))).toBe('Paid days must be from 0 to 2');
    t.type('Paid days', '2', dialog);
    await t.settle();
    expect(t.text(dialog.querySelector('#decide-split'))).toBe('2 paid · 0 LOP');
    t.type('Paid days', '1.5', dialog);
    await click('Approve', dialog.querySelector('mat-dialog-actions')!);
    expect(t.leave.ops).toEqual([
      { kind: 'leave.decide', payload: { id: 'lr1', approve: true, paid_days: 1.5 } },
    ]);
    expect(t.snack()).toBe('Leave approved');
    expect(t.text(detail().querySelector('app-status-pill'))).toBe('Approved');
    expect(t.text(detail())).toContain('Paid / LOP 1.5 paid · 0.5 LOP');
  });

  it('reject with a note', async () => {
    t = await startPage('/staff/leave?id=lr2');
    await click('Reject…', detail());
    const dialog = t.dialog()!;
    const note = dialog.querySelector('textarea') as HTMLTextAreaElement;
    note.value = 'Short-staffed';
    note.dispatchEvent(new Event('input'));
    await click('Reject', dialog.querySelector('mat-dialog-actions')!);
    expect(t.leave.ops[0]).toEqual({
      kind: 'leave.decide',
      payload: { id: 'lr2', approve: false, note: 'Short-staffed' },
    });
    expect(t.snack()).toBe('Leave rejected');
  });

  it('a cancellation request: approve it or keep the leave', async () => {
    t = await startPage('/staff/leave?id=lr3');
    expect(t.text(section('Cancellation requested'))).toContain('Keep the leave');
    await click('Approve cancellation', detail());
    expect(t.text(t.dialog())).toContain('Their reason: “Trip called off”');
    await click('Approve cancellation', t.dialog()!.querySelector('mat-dialog-actions')!);
    expect(t.leave.ops[0]).toEqual({ kind: 'leave.decide', payload: { id: 'lr3', approve: true } });
    expect(t.text(detail().querySelector('app-status-pill'))).toBe('Cancelled');
  });

  it('a refusal stays in the dialog in plain words', async () => {
    t = await startPage('/staff/leave?id=lr1', 1440, ({ leave }) => {
      leave.refuse = 'period_finalised';
    });
    await click('Approve…', detail());
    await click('Approve', t.dialog()!.querySelector('mat-dialog-actions')!);
    expect(t.text(t.dialog()!.querySelector('[role="alert"]'))).toBe(
      'Pay for these dates is already finalised, so the leave can’t change. Add an adjustment in the next pay run instead',
    );
    expect(t.leave.ops).toEqual([]);
  });

  it('own requests: only the owner decides them', async () => {
    t = await startPage('/staff/leave?id=lr4', 1440, ({ arena }) => {
      arena.memberships = arena.memberships.map((m) => ({
        ...m,
        role: 'staff' as const,
        perms: ['reports', 'leave_approve'],
      }));
    });
    expect(t.button('Approve…', detail())).toBeUndefined();
    expect(t.text(detail())).toContain(
      'This is your own request: another approver (or the owner) decides it.',
    );
    // Someone else's request: the approver decides it.
    await t.harness.navigateByUrl('/staff/leave?id=lr1');
    await t.settle();
    expect(t.button('Approve…', detail())).toBeDefined();
  });

  it('the owner may decide their own request', async () => {
    t = await startPage('/staff/leave?id=lr4');
    expect(t.button('Approve…', detail())).toBeDefined();
  });

  it('All requests filters by staff and status (in the URL)', async () => {
    t = await startPage('/staff/leave?tab=all');
    expect(titles()).toHaveLength(8);
    expect(summary()).toBe('8 requests · 4 waiting for a decision');
    await t.harness.navigateByUrl('/staff/leave?tab=all&staff=st3');
    await t.settle();
    expect(titles()).toEqual(['Arjun Rao', 'Arjun Rao']);
    await t.harness.navigateByUrl('/staff/leave?tab=all&status=rejected');
    await t.settle();
    expect(titles()).toEqual(['Ravi Kumar']);
  });

  it('Balances: everyone’s leave year, and an adjustment with a reason', async () => {
    t = await startPage('/staff/leave?tab=balances');
    const table = t.doc().querySelector('app-leave-balances-table table') as HTMLElement;
    const head = [...table.querySelectorAll('thead th')].map((th) => t.text(th));
    expect(head.slice(0, 8)).toEqual([
      'Staff',
      'Joined on',
      'Leave year',
      'Allowance',
      'Adjustments',
      'Used',
      'Waiting',
      'Balance',
    ]);
    const ravi = [...table.querySelectorAll('tbody tr')].find((r) =>
      t.text(r)?.includes('Ravi Kumar'),
    )!;
    expect(t.text(ravi)).toContain('20 Nov 2024');
    expect(t.text(ravi)).toContain('12 0 11 2 1');
    (ravi.querySelector('button') as HTMLButtonElement).click();
    await t.settle();
    const dialog = t.dialog()!;
    expect(t.text(dialog)).toContain('Now 1 days left');
    t.type('Days to add or take away', '+1', dialog);
    await t.settle();
    expect(t.text(dialog)).toContain('New balance: 2 days');
    await click('Adjust balance', dialog.querySelector('mat-dialog-actions')!);
    expect(t.text(dialog.querySelector('[role="alert"]'))).toBe('Give a reason');
    t.type('Reason', 'Worked on Diwali', dialog);
    await click('Adjust balance', dialog.querySelector('mat-dialog-actions')!);
    expect(t.leave.ops).toEqual([
      { kind: 'leave.adjust', payload: { staff_id: 'st1', days: 1, reason: 'Worked on Diwali' } },
    ]);
    expect(t.snack()).toBe('Ravi Kumar’s balance adjusted');
    expect(t.text(ravi)).toContain('12 +1 11 2 2');
  });

  it('a person’s balance lists their adjustments and requests this leave year', async () => {
    t = await startPage('/staff/leave?tab=balances&person=st2');
    const d = t.doc().querySelector('app-leave-balance-detail') as HTMLElement;
    expect(t.text(d.querySelector('h2'))).toBe('Priya Nair');
    expect(t.text(section('Adjustments'))).toContain('Worked on Holi');
    expect(t.text(section('Adjustments'))).toContain('+1');
    expect(t.text(section('Requests this leave year'))).toContain('Cancel requested');
  });

  it('without leave_approve the screen and its nav entry are gone', async () => {
    t = await startPage('/staff/leave', 1440, ({ arena }) => {
      arena.memberships = arena.memberships.map((m) => ({
        ...m,
        role: 'staff' as const,
        perms: ['reports', 'payroll'],
      }));
    });
    expect(t.url()).toBe('/overview');
    expect(navLabels()).not.toContain('Leave');
    expect(navLabels()).toContain('Payroll');
  });
});
