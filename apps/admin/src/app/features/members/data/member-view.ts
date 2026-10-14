import { istDayStart } from '../../../shared/time/ist';

/** "98••• ••873": enough to recognise a number, not to copy it. */
export function maskPhone(phone: string | null): string {
  if (!phone) return 'No phone';
  const digits = phone.replace(/\D/g, '');
  if (digits.length < 6) return '•••••';
  return `${digits.slice(0, 2)}••• ••${digits.slice(-3)}`;
}

/** "Today", "Yesterday", "12 days ago" (IST calendar days), or "—". */
export function daysAgo(at: string | null, now: Date): string {
  if (!at) return '—';
  const d = Math.round(
    (istDayStart(now).getTime() - istDayStart(new Date(at)).getTime()) / 86_400_000,
  );
  return d <= 0 ? 'Today' : d === 1 ? 'Yesterday' : `${d} days ago`;
}
