import { Pipe, PipeTransform } from '@angular/core';

/** Integer paise → whole rupees for display, Indian grouping: 4812000 → "₹48,120". */
export function formatRupees(paise: number): string {
  return '₹' + Math.round(paise / 100).toLocaleString('en-IN');
}

@Pipe({ name: 'rupees' })
export class RupeesPipe implements PipeTransform {
  transform(paise: number | null | undefined): string {
    return formatRupees(paise ?? 0);
  }
}
