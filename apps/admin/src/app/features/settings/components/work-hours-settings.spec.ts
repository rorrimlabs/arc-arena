import { TestBed } from '@angular/core/testing';
import { ArenaContext } from '../../../core/arena/arena-context';
import { PageTest, startPage } from '../../../testing/page-test';
import { DEFAULT_WORK_HOURS } from '../data/work-hours';

describe('Settings › Working hours', () => {
  let t: PageTest;

  afterEach(() => t?.cleanup());

  const pane = () => t.doc().querySelector('app-work-hours-settings') as HTMLElement;
  const saveBar = () => t.doc().querySelector('app-unsaved-bar') as HTMLElement | null;
  const inputs = () => [...pane().querySelectorAll('input[matinput]')] as HTMLInputElement[];
  const radio = (value: string) =>
    pane().querySelector(`mat-radio-button input[value="${value}"]`) as HTMLInputElement;

  it('is listed in Settings and starts on the server defaults', async () => {
    t = await startPage('/settings?id=workhours');
    expect(t.rows().map(t.rowText)).toContainEqual([
      'Working hours',
      'Late grace, half days, extra hours',
    ]);
    expect(t.text(pane().querySelector('h2'))).toBe('Working hours');
    expect(t.text(pane())).toContain('8h standard day · 10 min late grace');
    // Late, early, break after, full %, half %, hours, minutes, auto clock-out.
    expect(inputs().map((i) => i.value)).toEqual(['10', '15', '300', '75', '40', '8', '0', '120']);
    expect(radio('exact').checked).toBe(true);
    expect(radio('day').checked).toBe(true);
    expect(saveBar()).toBeNull();
  });

  it('saves the whole work_hours object', async () => {
    t = await startPage('/settings?id=workhours');
    t.type('Late grace', '5', pane());
    t.type('Minutes', '30', pane());
    radio('nearest_15').click();
    radio('week').click();
    await t.settle();
    t.button('Save', saveBar()!)!.click();
    await t.settle();
    expect(t.workHours.writes).toEqual([
      {
        late_grace_min: 5,
        early_leave_min: 15,
        break_after_min: 300,
        rounding: 'nearest_15',
        full_day_pct: 75,
        half_day_pct: 40,
        standard_day_min: 510,
        extra_basis: 'week',
        week_start: 1,
        auto_out_after_min: 120,
      },
    ]);
    expect(t.snack()).toBe('Working hours saved');
    expect(saveBar()).toBeNull();
    expect(t.text(pane())).toContain('8h 30m standard day · 5 min late grace');
  });

  it('half day at or above full day is flagged at once; other problems after a save attempt', async () => {
    t = await startPage('/settings?id=workhours');
    t.type('Half day from', '80', pane());
    await t.settle();
    expect(t.text(pane())).toContain('Half day must be less than full day');
    t.type('Half day from', '40', pane());
    t.type('Auto clock-out after the shift end', '900', pane());
    await t.settle();
    expect(t.text(pane())).not.toContain('Auto clock-out grace must be');
    t.button('Save', saveBar()!)!.click();
    await t.settle();
    expect(t.text(pane())).toContain(
      'Auto clock-out grace must be a whole number of minutes from 0 to 720',
    );
    expect(t.text(pane())).toContain('Fix the values marked above, then save again');
    expect(t.workHours.writes).toEqual([]);
  });

  it('shows what the arena saved', async () => {
    t = await startPage('/settings?id=workhours', 1440, ({ workHours }) => {
      workHours.saved = { ...DEFAULT_WORK_HOURS, standardDayMin: 570, weekStart: 7 };
    });
    expect(inputs().slice(5, 7).map((i) => i.value)).toEqual(['9', '30']);
    expect(t.text(pane().querySelector('mat-select'))).toContain('Sunday');
  });

  it('read-only without the Settings permission', async () => {
    t = await startPage('/settings?id=workhours', 1440, ({ arena }) => {
      arena.memberships = arena.memberships.map((m) => ({
        ...m,
        role: 'staff' as const,
        perms: ['money', 'reports'],
      }));
    });
    expect(TestBed.inject(ArenaContext).canEdit()).toBe(false);
    expect(inputs().every((i) => i.disabled)).toBe(true);
    expect(radio('week').disabled).toBe(true);
  });
});
