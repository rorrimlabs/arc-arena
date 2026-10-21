import { TestBed } from '@angular/core/testing';
import { ArenaContext } from '../../core/arena/arena-context';
import { NAV_ITEMS } from '../../core/layout/nav';
import { PageTest, startPage } from '../../testing/page-test';
import { DEFAULT_ATTENDANCE_RULES } from '../settings/data/attendance-rules';
import { SAMPLE_FENCE } from './data/attendance-api.sample';
import { AttendanceStore } from './data/attendance-store';

describe('Staff › Attendance', () => {
  let t: PageTest;

  afterEach(() => t?.cleanup());

  const entries = () => [...t.doc().querySelectorAll('app-entry-row a')] as HTMLElement[];
  const names = () => entries().map((a) => t.text(a.querySelector('span.truncate')));
  const navLabels = () =>
    [...t.doc().querySelectorAll('nav[aria-label="Main"] a')].map((a) => a.getAttribute('title'));
  const summary = () => t.text(t.doc().querySelector('p[aria-live="polite"]'));

  it('the owner sees it under Staff; the last 7 days are listed, newest first', async () => {
    t = await startPage('/staff/attendance');
    expect(NAV_ITEMS.find((i) => i.path === 'staff/attendance')?.perm).toBe('attendance_review');
    expect(navLabels()).toContain('Attendance');
    expect(t.attendance.loads).toEqual([['2026-10-07', '2026-10-13']]);
    expect(names()).toEqual(['Rohan Das', 'Priya Nair', 'Kavya Iyer', 'Priya Nair', 'Kavya Iyer']);
    expect(summary()).toBe('5 entries · 4 need review · 1 on the clock');
    const rohan = t.text(entries()[0]);
    expect(rohan).toContain('13 Oct · 10:00 am → 6:10 pm');
    expect(rohan).toContain('8h 10m');
    expect(rohan).toContain('In · Inside');
    expect(rohan).toContain('Out · Outside');
    expect(rohan).toContain('Needs review');
    // The out badge already says outside: no extra chip for it.
    expect(rohan).not.toContain('Outside the arena');
    const priya = t.text(entries()[1]);
    expect(priya).toContain('9:02 am → On the clock');
    expect(priya).toContain('10h 28m');
    expect(t.text(entries()[3])).toContain('Closed automatically');
    expect(t.text(entries()[4])).toContain('Fake location (in)');
  });

  it('filters by location, staff, review and who is on the clock (all in the URL)', async () => {
    t = await startPage('/staff/attendance?where=outside');
    expect(names()).toEqual(['Rohan Das']);
    await t.harness.navigateByUrl('/staff/attendance?where=unknown');
    await t.settle();
    expect(names()).toEqual(['Kavya Iyer']);
    await t.harness.navigateByUrl('/staff/attendance?staff=s3&review=1');
    await t.settle();
    expect(names()).toEqual(['Kavya Iyer', 'Kavya Iyer']);
    await t.harness.navigateByUrl('/staff/attendance?open=1');
    await t.settle();
    expect(names()).toEqual(['Priya Nair']);
    await t.harness.navigateByUrl('/staff/attendance?range=30d');
    await t.settle();
    expect(names()).toHaveLength(6);
    await t.harness.navigateByUrl('/staff/attendance?range=today&where=inside');
    await t.settle();
    expect(names()).toEqual(['Rohan Das', 'Priya Nair']);
  });

  it('an entry shows both punches side by side and their pins on the map', async () => {
    t = await startPage('/staff/attendance?id=e2');
    const detail = t.doc().querySelector('app-entry-detail') as HTMLElement;
    expect(t.text(detail.querySelector('h2'))).toBe('Rohan Das');
    const [inSide, outSide] = [...detail.querySelectorAll('section[aria-label]')].map((s) =>
      t.text(s),
    );
    expect(inSide).toContain('Clock-in');
    expect(inSide).toContain('Server time 13 Oct, 10:00 am');
    expect(inSide).toContain('Where Inside');
    expect(outSide).toContain('Phone time 6:15 pm · 5 min ahead');
    expect(outSide).toContain('From the arena 380 m');
    expect(outSide).toContain('Accuracy ±12 m');
    expect(outSide).toContain('Position 12.938100, 77.626200');
    expect(outSide).toContain('Fake location No');
    expect(outSide).toContain('Device dev-s2');
    expect(t.text(detail)).toContain('Outside the arena (out)');
    const map = t.leaflet.maps[t.leaflet.maps.length - 1];
    const circle = map.layers.find((l) => l.type === 'circle')!;
    expect(circle.at).toEqual([SAMPLE_FENCE.lat, SAMPLE_FENCE.lng]);
    expect(circle.options['radius']).toBe(100);
    expect(
      map.layers.filter((l) => l.type === 'circleMarker').map((l) => l.options['className']),
    ).toEqual(['geo-in', 'geo-out']);
  });

  it('a punch without a position says so; the map shows the other pin only', async () => {
    t = await startPage('/staff/attendance?id=e3');
    const detail = t.doc().querySelector('app-entry-detail') as HTMLElement;
    const inSide = t.text(detail.querySelector('section[aria-label="Clock-in"]'));
    expect(inSide).toContain('Location Location permission off');
    expect(inSide).toContain('Position None');
    expect(inSide).toContain('Fake location Not reported');
    const map = t.leaflet.maps[t.leaflet.maps.length - 1];
    expect(map.layers.filter((l) => l.type === 'circleMarker')).toHaveLength(1);
  });

  it('the Map view puts every listed punch on one map with the current geofence', async () => {
    t = await startPage('/staff/attendance?view=map', 1440, ({ attendanceRules }) => {
      attendanceRules.saved = {
        ...DEFAULT_ATTENDANCE_RULES,
        geofence: { lat: 12.9, lng: 77.6, radiusM: 250 },
      };
    });
    const pane = t.doc().querySelector('app-punch-map') as HTMLElement;
    expect(t.text(pane.querySelector('h2'))).toBe('Punch map');
    expect(t.text(pane)).toContain('7 punches with a position.');
    const map = t.leaflet.maps[t.leaflet.maps.length - 1];
    expect(map.layers.filter((l) => l.type === 'circleMarker')).toHaveLength(7);
    expect(map.layers.find((l) => l.type === 'circle')?.options['radius']).toBe(250);
  });

  it('exports the filtered entries as CSV', async () => {
    t = await startPage('/staff/attendance?review=1');
    t.button('Export CSV')!.click();
    await t.settle();
    expect(t.snack()).toBe('4 entries exported');
  });

  it('a live reload picks up a new clock-in', async () => {
    t = await startPage('/staff/attendance');
    t.attendance.data.entries.push({
      ...t.attendance.data.entries[0],
      id: 'e9',
      staffId: 's2',
      inAt: '2026-10-13T13:50:00Z',
      outAt: null,
      inPunchId: null,
      outPunchId: null,
      outSource: null,
      flags: [],
      review: 'none',
    });
    await TestBed.inject(AttendanceStore).refresh();
    await t.settle();
    expect(names()[0]).toBe('Rohan Das');
    expect(summary()).toBe('6 entries · 4 need review · 2 on the clock');
  });
});

describe('Staff › Attendance: who may see it', () => {
  let t: PageTest;

  afterEach(() => t?.cleanup());

  const navLabels = () =>
    [...t.doc().querySelectorAll('nav[aria-label="Main"] a')].map((a) => a.getAttribute('title'));

  it('a manager without attendance_review neither sees it nor opens it by URL', async () => {
    t = await startPage('/staff/attendance', 1440, ({ arena }) => {
      arena.memberships = arena.memberships.map((m) => ({
        ...m,
        role: 'staff' as const,
        perms: ['money', 'reports', 'settings'],
      }));
    });
    expect(t.url()).toBe('/overview');
    expect(navLabels()).not.toContain('Attendance');
    expect(t.attendance.loads).toEqual([]);
  });

  it('a manager holding attendance_review sees it', async () => {
    t = await startPage('/staff/attendance', 1440, ({ arena }) => {
      arena.memberships = arena.memberships.map((m) => ({
        ...m,
        role: 'staff' as const,
        perms: ['reports', 'attendance_review'],
      }));
    });
    expect(t.url()).toBe('/staff/attendance');
    expect(navLabels()).toContain('Attendance');
    expect(TestBed.inject(ArenaContext).hasPerm('attendance_review')).toBe(true);
  });

  it('the permission taken away live: the page leaves for Overview', async () => {
    t = await startPage('/staff/attendance', 1440, ({ arena }) => {
      arena.memberships = arena.memberships.map((m) => ({
        ...m,
        role: 'staff' as const,
        perms: ['reports', 'attendance_review'],
      }));
    });
    const arena = TestBed.inject(ArenaContext);
    t.arena.memberships = t.arena.memberships.map((m) => ({ ...m, perms: ['reports'] }));
    await arena.load(true);
    await t.settle();
    expect(t.url()).toBe('/overview');
    expect(navLabels()).not.toContain('Attendance');
  });
});
