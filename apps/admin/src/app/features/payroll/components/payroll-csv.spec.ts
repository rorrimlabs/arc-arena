import { SamplePayrollApi } from '../data/payroll-api.sample';
import { SUMMARY_HEAD, TIMESHEET_HEAD, moneyCell, summaryCsv, timesheetCsv } from './payroll-csv';

describe('payroll CSV', () => {
  const api = new SamplePayrollApi();
  const run = api.runs.find((r) => r.id === 'r-oct')!;
  const lines = api.lines.filter((l) => l.runId === 'r-oct');
  const adjustments = api.adjustments.filter((a) => a.runId === 'r-oct');
  const meta = {
    arena: '404 Arena Koramangala',
    run,
    generatedAt: new Date('2026-10-13T14:00:00Z'),
    generatedBy: 'Arjun Mehra <arjun@404arena.in>',
  };

  /** One CSV line into cells (quoted cells may hold commas). */
  const cells = (line: string) => {
    const out: string[] = [];
    let cur = '';
    let quoted = false;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (quoted && c === '"' && line[i + 1] === '"') {
        cur += '"';
        i++;
      } else if (c === '"') quoted = !quoted;
      else if (c === ',' && !quoted) {
        out.push(cur);
        cur = '';
      } else cur += c;
    }
    out.push(cur);
    return out;
  };
  const table = (csv: string, head: readonly string[]) => {
    const rows = csv.trimEnd().split('\n');
    const at = rows.findIndex((r) => cells(r).join('|') === head.join('|'));
    expect(at).toBeGreaterThan(0);
    return rows.slice(at + 1).map(cells);
  };

  it('money cells come from integers', () => {
    expect(moneyCell(1_475_806)).toBe('14758.06');
    expect(moneyCell(-30_000)).toBe('-300.00');
    expect(moneyCell(5)).toBe('0.05');
  });

  it('timesheet: one row per person per day', () => {
    const csv = timesheetCsv(lines, meta);
    expect(csv).toContain('404 Arena Koramangala — Timesheet');
    expect(csv).toContain('Period,2026-10-01 to 2026-10-31 (IST calendar days)');
    const rows = table(csv, TIMESHEET_HEAD);
    expect(rows).toHaveLength(62);
    // Arjun Rao first (alphabetical): 2 Oct, the holiday he worked.
    const holiday = rows.find((r) => r[0] === 'Arjun Rao' && r[2] === '2026-10-02')!;
    expect(holiday.slice(1, 8)).toEqual([
      'Fixed monthly',
      '2026-10-02',
      'Fri',
      'Holiday',
      '480',
      '8.00',
      '480',
    ]);
    expect(holiday[14]).toBe('Gandhi Jayanti');
    const late = rows.find((r) => r[0] === 'Ravi Kumar' && r[2] === '2026-10-06')!;
    expect([late[4], late[5], late[8]]).toEqual(['Late', '465', 'Yes']);
  });

  it('summary: every column, each deduction kept or waived, each adjustment, totals', () => {
    const csv = summaryCsv(lines, adjustments, meta);
    const rows = table(csv, SUMMARY_HEAD);
    const col = (name: string) => SUMMARY_HEAD.indexOf(name);
    const ravi = rows.find((r) => r[0] === 'Ravi Kumar')!;
    expect(ravi[col('Gross (₹)')]).toBe('18000.00');
    expect(ravi[col('Absent suggested (₹)')]).toBe('580.65');
    expect(ravi[col('Absent kept')]).toBe('Kept');
    expect(ravi[col('Late suggested (₹)')]).toBe('290.32');
    expect(ravi[col('Deductions applied (₹)')]).toBe('1741.94');
    expect(ravi[col('Adjustments (₹)')]).toBe('-1500.00');
    expect(ravi[col('Net (₹)')]).toBe('14758.06');
    expect(csv).toContain('Advance -2000.00 (Oct 10 advance); Bonus 500.00 (Diwali)');
    const arjun = rows.find((r) => r[0] === 'Arjun Rao')!;
    expect(arjun[col('Base (₹)')]).toBe('21032.26');
    expect(arjun[col('Extra hours pay (₹)')]).toBe('3000.00');
    expect(arjun[col('Net (₹)')]).toBe('23022.58');
    const total = rows.at(-1)!;
    expect(total[0]).toBe('Total — 2 people');
    expect(total[col('Net (₹)')]).toBe('37780.64');
  });
});
