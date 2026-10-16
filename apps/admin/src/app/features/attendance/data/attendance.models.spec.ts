import { SAMPLE_FENCE, SAMPLE_STAFF, sampleAttendance } from './attendance-api.sample';
import {
  LogFilter,
  buildRows,
  entryFence,
  entryMinutes,
  filterRows,
  flagLabel,
  flagTone,
  phoneSkew,
  rowFlags,
} from './attendance.models';

const NOW = new Date('2026-10-13T14:00:00Z');
const rows = buildRows({ staff: SAMPLE_STAFF, ...sampleAttendance() });
const week: LogFilter = {
  first: '2026-10-07',
  last: '2026-10-13',
  staffId: null,
  verdict: 'any',
  needsReview: false,
  onClock: false,
};
const ids = (f: Partial<LogFilter>) => filterRows(rows, { ...week, ...f }).map((r) => r.entry.id);

describe('attendance log', () => {
  it('joins names and punches, newest clock-in first', () => {
    expect(rows.map((r) => r.entry.id)).toEqual(['e2', 'e1', 'e3', 'e4', 'e6', 'e5']);
    const e2 = rows[0];
    expect(e2.staffName).toBe('Rohan Das');
    expect(e2.inPunch?.geofence).toBe('inside');
    expect(e2.outPunch?.geofence).toBe('outside');
    expect(rows.find((r) => r.entry.id === 'e4')?.outPunch).toBeNull();
  });

  it('filters by IST work date (inclusive), staff and review', () => {
    expect(ids({})).toEqual(['e2', 'e1', 'e3', 'e4', 'e6']);
    expect(ids({ first: '2026-10-13', last: '2026-10-13' })).toEqual(['e2', 'e1']);
    expect(ids({ first: '2026-10-01' })).toContain('e5');
    expect(ids({ staffId: 's3' })).toEqual(['e3', 'e6']);
    expect(ids({ needsReview: true })).toEqual(['e2', 'e3', 'e4', 'e6']);
  });

  it('a location filter matches when either punch does', () => {
    expect(ids({ verdict: 'outside' })).toEqual(['e2']);
    expect(ids({ verdict: 'unknown' })).toEqual(['e3']);
    expect(ids({ verdict: 'inside' })).toEqual(['e2', 'e1', 'e3', 'e4', 'e6']);
  });

  it('"On the clock now" lists open entries whatever day they started', () => {
    expect(ids({ onClock: true })).toEqual(['e1']);
    expect(ids({ onClock: true, first: '2026-10-01', last: '2026-10-02' })).toEqual(['e1']);
  });

  it('worked minutes come from the stored times; an open entry counts up to now', () => {
    const [e2, e1] = rows;
    expect(entryMinutes(e2.entry, NOW)).toBe(490);
    expect(entryMinutes(e1.entry, NOW)).toBe(628);
    expect(entryMinutes(e1.entry, new Date('2026-10-13T14:30:00Z'))).toBe(658);
  });

  it('names flags in plain words', () => {
    expect(flagLabel('auto_out')).toBe('Closed automatically');
    expect(flagLabel('mock_in')).toBe('Fake location (in)');
    expect(flagLabel('outside_out')).toBe('Outside the arena (out)');
    expect(flagLabel('unknown_in')).toBe('Location unknown (in)');
    expect(flagLabel('low_accuracy_in')).toBe('Weak GPS (in)');
    expect(flagLabel('no_geofence_out')).toBe('No arena location set (out)');
    expect(flagLabel('mock')).toBe('Fake location');
    expect(flagLabel('worked_on_leave')).toBe('Worked on a leave day');
    expect(flagLabel('something_new')).toBe('Something new');
    expect(flagTone('mock_in')).toBe('danger');
    expect(flagTone('auto_out')).toBe('warning');
    expect(flagTone('low_accuracy_in')).toBe('info');
  });

  it('list rows leave out the flags the in/out badges already show', () => {
    expect(
      rowFlags(['outside_out', 'unknown_in', 'low_accuracy_in', 'auto_out', 'mock_in']),
    ).toEqual(['low_accuracy_in', 'auto_out', 'mock_in']);
  });

  it('notes a phone clock more than 2 minutes off', () => {
    const out = rows[0].outPunch!;
    expect(phoneSkew(out)).toBe('5 min ahead');
    expect(phoneSkew({ ...out, deviceAt: '2026-10-13T12:38:30Z' })).toBeNull();
    expect(phoneSkew({ ...out, deviceAt: '2026-10-13T12:30:00Z' })).toBe('10 min behind');
    expect(phoneSkew({ ...out, deviceAt: null })).toBeNull();
  });

  it('draws the geofence a punch was judged against, else the current one', () => {
    const current = { lat: 1, lng: 2, radiusM: 300 };
    expect(entryFence(rows[0], current)).toEqual({ fence: SAMPLE_FENCE, fromPunch: true });
    expect(entryFence({ inPunch: null, outPunch: null }, current)).toEqual({
      fence: current,
      fromPunch: false,
    });
  });
});
