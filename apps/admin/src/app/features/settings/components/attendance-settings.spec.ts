import { TestBed } from '@angular/core/testing';
import { ArenaContext } from '../../../core/arena/arena-context';
import { PageTest, startPage } from '../../../testing/page-test';
import { DEFAULT_ATTENDANCE_RULES } from '../data/attendance-rules';

describe('Settings › Attendance', () => {
  let t: PageTest;

  afterEach(() => t?.cleanup());

  const pane = () => t.doc().querySelector('app-attendance-settings') as HTMLElement;
  const saveBar = () => t.doc().querySelector('app-unsaved-bar') as HTMLElement | null;
  const radios = (value: string) =>
    [...pane().querySelectorAll(`mat-radio-button input[value="${value}"]`)] as HTMLInputElement[];
  const map = () => t.leaflet.maps[t.leaflet.maps.length - 1];

  it('starts on the defaults: no location, flag, 50 m, block mock, 14 hours', async () => {
    t = await startPage('/settings?id=attendance');
    expect(t.text(pane().querySelector('h2'))).toBe('Attendance');
    expect(t.text(pane())).toContain('No location set');
    const inputs = [...pane().querySelectorAll('input[matinput]')] as HTMLInputElement[];
    expect(inputs.map((i) => i.value)).toEqual(['', '', '100', '50', '14']);
    expect(radios('flag')[0].checked).toBe(true);
    expect(radios('block')[1].checked).toBe(true);
    expect(saveBar()).toBeNull();
  });

  it('a click on the map sets the centre; saving sends the five keys', async () => {
    t = await startPage('/settings?id=attendance');
    map().click(12.93521234, 77.62459876);
    await t.settle();
    expect(map().layers.map((l) => l.type)).toEqual(['circle', 'marker']);
    expect(map().layers[0].options['radius']).toBe(100);
    t.type('Radius', '150', pane());
    t.type('Close automatically after', '12', pane());
    await t.settle();
    t.button('Save', saveBar()!)!.click();
    await t.settle();
    expect(t.attendanceRules.writes).toEqual([
      {
        geofence: { lat: 12.935212, lng: 77.624599, radius_m: 150 },
        outside_rule: 'flag',
        min_accuracy_m: 50,
        mock_rule: 'block',
        max_open_hours: 12,
      },
    ]);
    expect(t.snack()).toBe('Attendance settings saved · the next clock-in uses them');
    expect(saveBar()).toBeNull();
  });

  it('dragging the pin moves the centre', async () => {
    t = await startPage('/settings?id=attendance', 1440, ({ attendanceRules }) => {
      attendanceRules.saved = {
        ...DEFAULT_ATTENDANCE_RULES,
        geofence: { lat: 12.9352, lng: 77.6245, radiusM: 100 },
      };
    });
    const pin = map().layers.find((l) => l.type === 'marker')!;
    expect(pin.options['draggable']).toBe(true);
    pin.latLng = { lat: 12.94, lng: 77.63 };
    pin.handlers['dragend']();
    await t.settle();
    const inputs = [...pane().querySelectorAll('input[matinput]')] as HTMLInputElement[];
    expect(inputs.slice(0, 2).map((i) => i.value)).toEqual(['12.94', '77.63']);
    expect(saveBar()).not.toBeNull();
  });

  it('Block without a location says so at once and is not saved', async () => {
    t = await startPage('/settings?id=attendance');
    radios('block')[0].click();
    await t.settle();
    expect(t.text(pane())).toContain(
      'Block needs the arena location: set it on the map, or choose Flag or Allow',
    );
    t.button('Save', saveBar()!)!.click();
    await t.settle();
    expect(t.attendanceRules.writes).toEqual([]);
    expect(t.text(pane())).toContain('Fix the values marked above, then save again');
  });

  it('out-of-range values show after a save attempt; Clear location removes the geofence', async () => {
    t = await startPage('/settings?id=attendance', 1440, ({ attendanceRules }) => {
      attendanceRules.saved = {
        ...DEFAULT_ATTENDANCE_RULES,
        geofence: { lat: 12.9352, lng: 77.6245, radiusM: 100 },
      };
    });
    t.type('Minimum GPS accuracy', '2', pane());
    await t.settle();
    expect(t.text(pane())).not.toContain('Minimum accuracy must be');
    t.button('Save', saveBar()!)!.click();
    await t.settle();
    expect(t.text(pane())).toContain(
      'Minimum accuracy must be a whole number of metres from 5 to 500',
    );
    t.type('Minimum GPS accuracy', '40', pane());
    t.button('Clear location', pane())!.click();
    await t.settle();
    t.button('Save', saveBar()!)!.click();
    await t.settle();
    expect(t.attendanceRules.writes[0]['geofence']).toBeNull();
    expect(t.attendanceRules.writes[0]['min_accuracy_m']).toBe(40);
  });

  it('read-only without the Settings permission', async () => {
    t = await startPage('/settings?id=attendance', 1440, ({ arena }) => {
      arena.memberships = arena.memberships.map((m) => ({
        ...m,
        role: 'staff' as const,
        perms: ['money', 'reports'],
      }));
    });
    expect(TestBed.inject(ArenaContext).canEdit()).toBe(false);
    const inputs = [...pane().querySelectorAll('input[matinput]')] as HTMLInputElement[];
    expect(inputs.every((i) => i.disabled)).toBe(true);
    expect(radios('allow')[0].disabled).toBe(true);
    expect(t.button('Clear location', pane())!.disabled).toBe(true);
    map().click(12.9, 77.6);
    await t.settle();
    expect(map().layers).toEqual([]);
  });
});
