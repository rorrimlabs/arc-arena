/** A station (server: resources). `available` is in service; anything else is out of it. */
export type StationStatus = 'available' | 'maintenance' | 'temporarily_unavailable' | 'disabled';

export interface Station {
  readonly id: string;
  readonly name: string;
  readonly kind: 'station' | 'table' | 'room';
  readonly status: StationStatus;
  readonly sortOrder: number;
  /** Station types (activity codes) it offers. */
  readonly activityCodes: readonly string[];
}

/** What resource.upsert sends. */
export interface StationInput {
  readonly id: string;
  readonly name: string;
  readonly kind: Station['kind'];
  /**
   * A new station's status. An edit leaves it out, so a rename made on an old copy never puts a
   * station back in service or takes it out (that is resource.set_status).
   */
  readonly status?: StationStatus;
  readonly sortOrder: number;
  readonly activityCodes: readonly string[];
}

/** A game in the catalog (server: games). */
export interface Game {
  readonly id: string;
  readonly name: string;
  readonly aliases: readonly string[];
  readonly categoryId: string | null;
  /** Free-text platform codes (PS5, PSVR2, PC…). */
  readonly platforms: readonly string[];
  readonly playerMode: 'single' | 'local' | 'online' | 'both';
  readonly maxLocalPlayers: number;
  /** Shown to staff when starting a session. */
  readonly active: boolean;
  /** Minimum age it is rated for (3, 7, 12, 16 or 18); null when not set. */
  readonly ageRating: AgeRating | null;
  readonly media: GameMedia | null;
}

export type AgeRating = 3 | 7 | 12 | 16 | 18;

/**
 * How a game runs on one station (server: game_resources). Staff can start a game on a station
 * only where it is `playable`; no row counts as not installed. The dashboard sets the first
 * three; the floor app may also report maintenance or a temporary outage.
 */
export type CompatStatus =
  'playable' | 'not_installed' | 'not_playable' | 'maintenance' | 'temporarily_unavailable';

export interface GameCompat {
  readonly gameId: string;
  readonly resourceId: string;
  readonly status: CompatStatus;
}
export type GameMedia = 'digital' | 'disc';

/** A registered member (server: customers that are not walk-in guests). */
export interface Customer {
  readonly id: string;
  readonly name: string;
  readonly phone: string | null;
  readonly lastVisitAt: string | null;
  readonly createdAt: string;
  /** Given at registration on the floor app; null when not given. */
  readonly birthYear: number | null;
}

export type BillKind = 'single' | 'group';
export type BillStatus = 'active' | 'completed' | 'voided';

/**
 * One stretch of play on a station: a single session's segment or a group player's assignment.
 * Open while `endedAt` is null and the bill is active.
 */
export interface Play {
  readonly id: string;
  readonly kind: BillKind;
  /** Session or group id (the Sales screen's bill id). */
  readonly billId: string;
  readonly billStatus: BillStatus;
  readonly customerId: string;
  readonly resourceId: string;
  readonly activityCode: string;
  readonly gameId: string | null;
  readonly controllers: number | null;
  readonly startedAt: string;
  readonly endedAt: string | null;
  /** When the bill is booked to end (the floor's countdown). */
  readonly scheduledEndAt: string;
}

/** A billed line (session_charges / group_charges) of a bill that was not voided. */
export interface Charge {
  readonly kind: BillKind;
  readonly billId: string;
  readonly resourceId: string | null;
  readonly activityCode: string;
  readonly segmentStart: string;
  readonly playedMinutes: number;
  readonly amountPaise: number;
}

/** A bill seen from its customer (sessions / group_sessions by customer). */
export interface Visit {
  readonly kind: BillKind;
  readonly id: string;
  readonly customerId: string;
  readonly status: BillStatus;
  readonly startedAt: string;
  readonly endedAt: string | null;
  /** Final bill; null while running or when voided before it ended. */
  readonly billedPaise: number | null;
}

/**
 * What still refers to a game, which decides between deleting and archiving it. Read when the
 * owner asks to delete; game.delete checks again on the server under a lock.
 */
export interface GameUsage {
  /** Stations playing it right now (open session segments and group players). */
  readonly playingNow: number;
  /** Session segments, group players and bookings that name it, past or present. */
  readonly records: number;
}

/** What game.upsert sends. */
export interface GameInput {
  readonly id: string;
  readonly name: string;
  readonly aliases: readonly string[];
  readonly categoryId: string | null;
  readonly platforms: readonly string[];
  readonly playerMode: Game['playerMode'];
  readonly maxLocalPlayers: number;
  readonly active: boolean;
  readonly ageRating: AgeRating | null;
  readonly media: GameMedia | null;
}

/** A station as the floor sees it right now. */
export type FloorState = 'playing' | 'free' | 'oos';

export interface LiveStation {
  readonly station: Station;
  readonly state: FloorState;
  /** Open plays on it (a group can put several players on one station). */
  readonly plays: readonly Play[];
  readonly gameId: string | null;
  readonly players: number;
  /** Earliest booked end among its open plays. */
  readonly endsAt: string | null;
}

export const FLOOR_STATE_LABEL: Readonly<Record<FloorState, string>> = {
  playing: 'Playing',
  free: 'Free',
  oos: 'Out of service',
};

/** Open plays grouped onto stations; disabled (removed) stations are left out. */
export function liveStations(stations: readonly Station[], plays: readonly Play[]): LiveStation[] {
  const open = new Map<string, Play[]>();
  for (const p of plays) {
    if (p.endedAt || p.billStatus !== 'active') continue;
    const list = open.get(p.resourceId) ?? [];
    list.push(p);
    open.set(p.resourceId, list);
  }
  return stations
    .filter((s) => s.status !== 'disabled')
    .map((station) => {
      const on = open.get(station.id) ?? [];
      const state: FloorState = on.length
        ? 'playing'
        : station.status === 'available'
          ? 'free'
          : 'oos';
      const ends = on.map((p) => p.scheduledEndAt).sort();
      const players = on.reduce((n, p) => n + (p.kind === 'group' ? 1 : (p.controllers ?? 1)), 0);
      return {
        station,
        state,
        plays: on,
        gameId: on.find((p) => p.gameId)?.gameId ?? null,
        players,
        endsAt: ends[0] ?? null,
      };
    });
}

/** Minutes a play has run (to `now` while still open). */
export function playMinutes(p: Play, now: Date): number {
  const end = p.endedAt ? Date.parse(p.endedAt) : now.getTime();
  return Math.max(0, (end - Date.parse(p.startedAt)) / 60_000);
}

/** Whole minutes left until `endsAt` (negative when overdue). */
export function minutesLeft(endsAt: string, now: Date): number {
  return Math.ceil((Date.parse(endsAt) - now.getTime()) / 60_000);
}

/** "AM" from "Arjun Mehra". */
export function initials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .map((w) => w[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();
}
