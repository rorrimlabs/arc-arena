import { Service, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { LoginScope } from '../../../core/auth/login-scope';
import { Clock } from '../../../core/time/clock';
import { CalendarApi } from './calendar-api';
import { AttendanceDay } from './calendar.models';

/**
 * Person-days for one period (a month on the Calendar). Live updates of attendance, shifts,
 * holidays or the working-hours setting reload it (RealtimeSync), since the server's figures
 * depend on all of them.
 */
@Service()
export class CalendarStore {
  private readonly api = inject(CalendarApi);
  private readonly arena = inject(ArenaContext);
  private readonly clock = inject(Clock);

  readonly days = signal<readonly AttendanceDay[] | null>(null);
  readonly loading = signal(false);
  readonly loadError = signal('');
  readonly loadedAt = signal<Date | null>(null);
  private loadedKey: string | null = null;
  private current: { first: string; last: string } | null = null;
  private outOfDate = false;
  private latest = 0;

  constructor() {
    inject(LoginScope).onEnd(() => {
      this.latest++;
      this.loadedKey = null;
      this.current = null;
      this.days.set(null);
      this.loading.set(false);
      this.loadError.set('');
      this.loadedAt.set(null);
    });
  }

  async load(first: string, last: string, force = false): Promise<void> {
    this.current = { first, last };
    const arenaId = this.arena.current().id;
    if (!arenaId) return;
    const key = `${arenaId}|${first}|${last}`;
    if (!force && !this.outOfDate && key === this.loadedKey) return;
    const call = ++this.latest;
    if (this.loadedKey !== key) this.days.set(null);
    this.outOfDate = false;
    this.loadedKey = key;
    this.loading.set(true);
    this.loadError.set('');
    try {
      const days = await this.api.days(arenaId, first, last);
      if (call === this.latest) {
        this.days.set(days);
        this.loadedAt.set(this.clock.now());
      }
    } catch (e) {
      if (call === this.latest) {
        this.loadError.set(toAppError(e).message);
        this.loadedKey = null;
      }
    } finally {
      if (call === this.latest) this.loading.set(false);
    }
  }

  /** Marks the days out of date without reading them (a live update nobody is looking at). */
  stale(): void {
    if (this.loadedKey) this.outOfDate = true;
  }

  /** A live update, the Refresh button or a reconnect: reads the open period again. */
  async refresh(): Promise<void> {
    if (this.current && (this.loadedKey || this.loadError())) {
      await this.load(this.current.first, this.current.last, true);
    }
  }
}
