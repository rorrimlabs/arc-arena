import { SAMPLE_STAFF, sampleAttendance } from '../data/attendance-api.sample';
import { buildRows } from '../data/attendance.models';
import { ATTENDANCE_HEAD, attendanceCsv } from './attendance-csv';

const rows = buildRows({ staff: SAMPLE_STAFF, ...sampleAttendance() }).filter(
  (r) => r.entry.workDate >= '2026-10-12',
);
const meta = {
  arena: '404 Arena Koramangala',
  first: '2026-10-12',
  last: '2026-10-13',
  generatedAt: new Date('2026-10-13T14:00:00Z'),
  generatedBy: 'Arjun Mehra <arjun@404arena.in>',
  filters: null,
};

describe('attendanceCsv', () => {
  const lines = attendanceCsv(rows, meta).trimEnd().split('\n');
  const head = lines.indexOf(ATTENDANCE_HEAD.join(','));

  it('says what it covers, then the columns', () => {
    expect(lines[0]).toBe('404 Arena Koramangala — Attendance log');
    expect(lines).toContain(
      'Period,2026-10-12 to 2026-10-13 (IST calendar days; an entry belongs to the day it started)',
    );
    expect(lines).toContain('Generated,2026-10-13 19:30 IST (2026-10-13T14:00:00.000Z)');
    expect(head).toBeGreaterThan(0);
    expect(ATTENDANCE_HEAD).toEqual([
      'Staff',
      'Work date',
      'In (IST)',
      'Out (IST)',
      'Minutes',
      'In verdict',
      'In distance (m)',
      'In accuracy (m)',
      'Out verdict',
      'Out distance (m)',
      'Out accuracy (m)',
      'Flags',
      'Review',
    ]);
  });

  it('one row per entry, oldest first, times in IST, open entries without out or minutes', () => {
    expect(lines.slice(head + 1)).toEqual([
      'Kavya Iyer,2026-10-12,2026-10-12 10:30,2026-10-12 19:00,510,Unknown,,,Inside,30,8,Location unknown (in),Needs review',
      'Priya Nair,2026-10-13,2026-10-13 09:02,,,Inside,42,8,,,,,',
      'Rohan Das,2026-10-13,2026-10-13 10:00,2026-10-13 18:10,490,Inside,30,8,Outside,380,12,Outside the arena (out),Needs review',
    ]);
  });

  it('escapes names a spreadsheet would run as a formula', () => {
    const evil = [{ ...rows[0], staffName: '=HYPERLINK("x")' }];
    const csv = attendanceCsv(evil, { ...meta, filters: 'Priya; needs review' });
    expect(csv).toContain(`"'=HYPERLINK(""x"")"`);
    expect(csv).toContain('Filters,Priya; needs review');
  });
});
