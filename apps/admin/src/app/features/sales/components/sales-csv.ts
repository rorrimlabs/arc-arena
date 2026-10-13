import { formatIsoDate, formatTime } from '../../../shared/time/ist';
import { Bill, billState, playedMinutes } from '../data/sale.models';

const HEAD = [
  'Bill',
  'Date',
  'Time',
  'Station',
  'Member',
  'Game',
  'Minutes',
  'Method',
  'Started by',
  'Billed',
  'Collected',
  'Status',
  'Void reason',
];

function cell(value: string | number): string {
  const s = String(value);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

/** Paise as rupees with two decimals (no symbol, no grouping) for spreadsheets. */
function rupees(paise: number): string {
  return (paise / 100).toFixed(2);
}

/** The design's CSV (`csv()`), with the columns these bills have: one row per bill, IST times. */
export function salesCsv(bills: readonly Bill[]): string {
  const rows = bills.map((b) =>
    [
      b.ref,
      formatIsoDate(b.at),
      formatTime(b.at),
      b.stations.join(' + '),
      b.customer,
      b.games.join(' + '),
      playedMinutes(b),
      b.voided ? '' : billState(b).label,
      b.startedBy ?? '',
      rupees(b.billedPaise ?? 0),
      rupees(b.paidPaise),
      b.voided ? 'void' : b.paymentStatus,
      b.voidReason ?? '',
    ]
      .map(cell)
      .join(','),
  );
  return [HEAD.join(','), ...rows].join('\n') + '\n';
}
