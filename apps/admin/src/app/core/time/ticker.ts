import { DestroyRef, Signal, inject, signal } from '@angular/core';
import { Clock } from './clock';

/**
 * "Now" for live countdowns, refreshed every `everyMs` while the calling component lives.
 * Call from an injection context (a field initializer or constructor).
 */
export function injectNow(everyMs = 30_000): Signal<Date> {
  const clock = inject(Clock);
  const now = signal(clock.now());
  const timer = setInterval(() => now.set(clock.now()), everyMs);
  inject(DestroyRef).onDestroy(() => clearInterval(timer));
  return now.asReadonly();
}
