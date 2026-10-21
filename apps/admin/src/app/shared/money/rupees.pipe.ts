import { Pipe, PipeTransform } from '@angular/core';

/** Integer paise → whole rupees for display, Indian grouping: 4812000 → "₹48,120". */
export function formatRupees(paise: number): string {
  return '₹' + Math.round(paise / 100).toLocaleString('en-IN');
}

/**
 * Integer paise → rupees to the paisa, Indian grouping, from integers only (no float maths):
 * 1475806 → "₹14,758.06", -30000 → "−₹300.00". Pay figures are shown this way.
 */
export function formatPaise(paise: number): string {
  const p = Math.round(paise);
  const abs = Math.abs(p);
  const rupees = Math.trunc(abs / 100);
  const rest = String(abs % 100).padStart(2, '0');
  return `${p < 0 ? '−' : ''}₹${rupees.toLocaleString('en-IN')}.${rest}`;
}

/** `{{ paise | rupees }}` → "₹48,120"; `{{ paise | rupees: 'paise' }}` → "₹48,120.50". */
@Pipe({ name: 'rupees' })
export class RupeesPipe implements PipeTransform {
  transform(paise: number | null | undefined, exact?: 'paise'): string {
    return exact === 'paise' ? formatPaise(paise ?? 0) : formatRupees(paise ?? 0);
  }
}
