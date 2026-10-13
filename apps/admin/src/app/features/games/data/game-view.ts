import {
  AgeRating,
  CompatStatus,
  Customer,
  Game,
  GameMedia,
  Play,
  Station,
  playMinutes,
} from '../../../core/floor/floor.models';
import { PillTone } from '../../../shared/status-pill/status-pill';
import { istDayStart } from '../../../shared/time/ist';

/** The age ratings and media the catalog accepts (games.age_rating / games.media). */
export const AGE_RATINGS: readonly AgeRating[] = [3, 7, 12, 16, 18];
export const MEDIA: readonly { readonly key: GameMedia; readonly label: string }[] = [
  { key: 'digital', label: 'Digital' },
  { key: 'disc', label: 'Disc' },
];

/** What the dashboard sets per station (game.set_compat); only Playable lets staff start it. */
export const COMPAT_CHOICES: readonly { readonly key: CompatStatus; readonly label: string }[] = [
  { key: 'playable', label: 'Playable' },
  { key: 'not_installed', label: 'Not installed' },
  { key: 'not_playable', label: 'Not playable' },
];

const COMPAT_LABELS: Readonly<Record<CompatStatus, string>> = {
  playable: 'Playable',
  not_installed: 'Not installed',
  not_playable: 'Not playable',
  maintenance: 'Maintenance',
  temporarily_unavailable: 'Temporarily unavailable',
};

export function compatLabel(status: CompatStatus): string {
  return COMPAT_LABELS[status] ?? status;
}

/** The stations a game can be marked on: the arena's stations still in use, in floor order. */
export function gameStations(stations: readonly Station[]): Station[] {
  return stations.filter((s) => s.kind === 'station' && s.status !== 'disabled');
}

/** How many of `stations` let staff start the game (a station without a row: not installed). */
export function playableCount(
  statuses: ReadonlyMap<string, CompatStatus> | undefined,
  stations: readonly Station[],
): number {
  return stations.filter((s) => statuses?.get(s.id) === 'playable').length;
}

export function mediaLabel(media: GameMedia | null): string {
  return MEDIA.find((m) => m.key === media)?.label ?? '';
}

/** The design's age badge colours: 18+ red, 16+ amber, anything lower neutral. */
export function ageTone(age: AgeRating): PillTone {
  return age >= 18 ? 'age18' : age >= 16 ? 'age16' : 'info';
}

const PLAYER_MODES: Readonly<Record<Game['playerMode'], string>> = {
  single: 'Single player',
  local: 'Local multiplayer',
  online: 'Online',
  both: 'Local and online',
};

export function playerModeLabel(g: Game): string {
  const mode = PLAYER_MODES[g.playerMode] ?? g.playerMode;
  return g.maxLocalPlayers > 1 ? `${mode} · up to ${g.maxLocalPlayers}` : mode;
}

export function platformLabel(g: Game): string {
  return g.platforms.join(', ') || 'No platform';
}

export function gameIcon(g: Game): string {
  return g.platforms.some((p) => /vr/i.test(p))
    ? 'view_in_ar'
    : g.platforms.some((p) => /pc/i.test(p))
      ? 'computer'
      : 'sports_esports';
}

/** Platforms in use, for the filter chips and the Add dialog. */
export function knownPlatforms(games: readonly Game[], extra: readonly string[] = []): string[] {
  return [...new Set([...games.flatMap((g) => g.platforms), ...extra])].sort();
}

export interface GameStats {
  readonly minutes30: number;
  readonly sessions30: number;
  readonly playingNow: number;
}

/** Plays that were not voided, started in the last 30 IST days (or still open). */
function recent(plays: readonly Play[], now: Date): Play[] {
  const since = istDayStart(now, 29).getTime();
  return plays.filter(
    (p) => p.billStatus !== 'voided' && (!p.endedAt || Date.parse(p.startedAt) >= since),
  );
}

/** Per game id: 30-day minutes, bills and stations playing it now. */
export function gameStats(plays: readonly Play[], now: Date): Map<string, GameStats> {
  const out = new Map<string, { minutes30: number; bills: Set<string>; playingNow: number }>();
  for (const p of recent(plays, now)) {
    if (!p.gameId) continue;
    const s = out.get(p.gameId) ?? { minutes30: 0, bills: new Set<string>(), playingNow: 0 };
    s.minutes30 += playMinutes(p, now);
    s.bills.add(p.billId);
    if (!p.endedAt && p.billStatus === 'active') s.playingNow++;
    out.set(p.gameId, s);
  }
  return new Map(
    [...out].map(([id, s]) => [
      id,
      { minutes30: s.minutes30, sessions30: s.bills.size, playingNow: s.playingNow },
    ]),
  );
}

export interface Fan {
  readonly customer: Customer;
  readonly sessions: number;
  readonly minutes: number;
}

/** Members who played a game most in the last 30 days (guests left out). */
export function topFans(
  gameId: string,
  plays: readonly Play[],
  customers: ReadonlyMap<string, Customer>,
  now: Date,
  limit = 4,
): Fan[] {
  const by = new Map<string, { bills: Set<string>; minutes: number }>();
  for (const p of recent(plays, now)) {
    if (p.gameId !== gameId || !customers.has(p.customerId)) continue;
    const f = by.get(p.customerId) ?? { bills: new Set<string>(), minutes: 0 };
    f.bills.add(p.billId);
    f.minutes += playMinutes(p, now);
    by.set(p.customerId, f);
  }
  return [...by]
    .map(([id, f]) => ({
      customer: customers.get(id) as Customer,
      sessions: f.bills.size,
      minutes: f.minutes,
    }))
    .sort((a, b) => b.minutes - a.minutes)
    .slice(0, limit);
}
