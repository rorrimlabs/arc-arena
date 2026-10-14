import { Service, computed, effect, inject, signal } from '@angular/core';
import { formatTime } from '../../shared/time/ist';
import { ArenaContext } from '../arena/arena-context';
import { FloorStore } from '../floor/floor-store';
import { injectNow } from '../time/ticker';

export type AdminNotificationType = 'ending_soon' | 'time_completed' | 'session_ended';

export interface AdminNotification {
  readonly id: string;
  readonly playId: string;
  readonly billId: string;
  readonly type: AdminNotificationType;
  readonly stationName: string;
  readonly customerName: string;
  readonly scheduledEndAt: string;
  readonly endedAt: string | null;
  readonly title: string;
  readonly subtitle: string;
}

/**
 * Derives operational notifications (sessions ending soon, session time completed,
 * and sessions ended) directly from Realtime-synchronized `FloorStore` plays and clock.
 */
@Service()
export class AdminNotificationsStore {
  private readonly floor = inject(FloorStore);
  private readonly arena = inject(ArenaContext);
  private readonly now = injectNow(5_000); // 5s tick for responsive countdowns

  private readonly dismissed = signal<Set<string>>(new Set());

  constructor() {
    effect(() => {
      const arenaId = this.arena.current().id;
      if (!arenaId) {
        this.dismissed.set(new Set());
        return;
      }
      this.dismissed.set(this.loadDismissed(arenaId));
    });
  }

  readonly notifications = computed<readonly AdminNotification[]>(() => {
    const arenaId = this.arena.current().id;
    if (!arenaId) return [];

    const nowTime = this.now().getTime();
    const plays = this.floor.plays();
    const stations = this.floor.stationById();
    const customers = this.floor.customerById();
    const dismissed = this.dismissed();

    const items: AdminNotification[] = [];

    for (const p of plays) {
      const station = stations.get(p.resourceId);
      const stationName = station?.name ?? 'Station';
      const customer = customers.get(p.customerId);
      const customerName = customer?.name ?? (p.kind === 'group' ? 'Group' : 'Guest');

      if (!p.endedAt && p.billStatus === 'active') {
        const endTime = Date.parse(p.scheduledEndAt);
        const diffMinutes = (endTime - nowTime) / 60_000;

        if (diffMinutes <= 0) {
          // Time completed
          const id = `${p.id}_completed_${p.scheduledEndAt}`;
          if (!dismissed.has(id)) {
            items.push({
              id,
              playId: p.id,
              billId: p.billId,
              type: 'time_completed',
              stationName,
              customerName,
              scheduledEndAt: p.scheduledEndAt,
              endedAt: null,
              title: `${stationName} — Session time completed`,
              subtitle: `${customerName} • Scheduled end: ${formatTime(p.scheduledEndAt)}`,
            });
          }
        } else if (diffMinutes <= 5) {
          // Ending soon (5 min or less)
          const remainingMin = Math.max(1, Math.ceil(diffMinutes));
          const id = `${p.id}_soon_${p.scheduledEndAt}`;
          if (!dismissed.has(id)) {
            items.push({
              id,
              playId: p.id,
              billId: p.billId,
              type: 'ending_soon',
              stationName,
              customerName,
              scheduledEndAt: p.scheduledEndAt,
              endedAt: null,
              title: `${stationName} — Ending soon (${remainingMin}m)`,
              subtitle: `${customerName} • Ends at ${formatTime(p.scheduledEndAt)}`,
            });
          }
        }
      } else if (p.endedAt && p.billStatus === 'completed') {
        const endedTime = Date.parse(p.endedAt);
        // Show recently ended sessions in the last 15 minutes
        if (nowTime - endedTime <= 15 * 60_000) {
          const id = `${p.id}_ended_${p.endedAt}`;
          if (!dismissed.has(id)) {
            items.push({
              id,
              playId: p.id,
              billId: p.billId,
              type: 'session_ended',
              stationName,
              customerName,
              scheduledEndAt: p.scheduledEndAt,
              endedAt: p.endedAt,
              title: `${stationName} — Session ended`,
              subtitle: `${customerName} • Ended at ${formatTime(p.endedAt)}`,
            });
          }
        }
      }
    }

    // Sort order: time_completed first, then ending_soon, then session_ended
    const typePriority: Record<AdminNotificationType, number> = {
      time_completed: 1,
      ending_soon: 2,
      session_ended: 3,
    };

    return items.sort((a, b) => typePriority[a.type] - typePriority[b.type]);
  });

  readonly unreadCount = computed(() => this.notifications().length);

  dismiss(id: string): void {
    const arenaId = this.arena.current().id;
    const current = new Set(this.dismissed());
    current.add(id);
    this.dismissed.set(current);
    if (arenaId) this.saveDismissed(arenaId, current);
  }

  clearAll(): void {
    const arenaId = this.arena.current().id;
    const current = new Set(this.dismissed());
    for (const n of this.notifications()) {
      current.add(n.id);
    }
    this.dismissed.set(current);
    if (arenaId) this.saveDismissed(arenaId, current);
  }

  private loadDismissed(arenaId: string): Set<string> {
    if (typeof localStorage === 'undefined') return new Set();
    try {
      const raw = localStorage.getItem(`arena_ops_dismissed_${arenaId}`);
      return raw ? new Set(JSON.parse(raw)) : new Set();
    } catch {
      return new Set();
    }
  }

  private saveDismissed(arenaId: string, set: Set<string>): void {
    if (typeof localStorage === 'undefined') return;
    try {
      localStorage.setItem(`arena_ops_dismissed_${arenaId}`, JSON.stringify([...set].slice(-100)));
    } catch {}
  }
}
