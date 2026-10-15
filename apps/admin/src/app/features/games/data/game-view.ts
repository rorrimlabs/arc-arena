import {
  AgeRating,
  CompatStatus,
  Game,
  GameMedia,
  Station,
} from '../../../core/floor/floor.models';
import { PillTone } from '../../../shared/status-pill/status-pill';

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

/**
 * The stations a game can be marked on: those still in use offering a type that picks a game
 * (`gameTypes`, from core/venue; every station in use while it loads), in floor order.
 */
export function gameStations(
  stations: readonly Station[],
  gameTypes: ReadonlySet<string> | null,
): Station[] {
  return stations.filter(
    (s) => s.status !== 'disabled' && (!gameTypes || s.activityCodes.some((c) => gameTypes.has(c))),
  );
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

/** games.player_mode values, as the dialog offers them. */
export const PLAYER_MODES: readonly { readonly key: Game['playerMode']; readonly label: string }[] =
  [
    { key: 'single', label: 'Single player' },
    { key: 'local', label: 'Local multiplayer' },
    { key: 'online', label: 'Online' },
    { key: 'both', label: 'Local and online' },
  ];

/** games.max_local_players is 1-8 (players_exceeded above it on the floor). */
export const MAX_PLAYERS = 8;

export function playerModeLabel(g: Game): string {
  const mode = PLAYER_MODES.find((m) => m.key === g.playerMode)?.label ?? g.playerMode;
  return g.maxLocalPlayers > 1 ? `${mode} · up to ${g.maxLocalPlayers}` : mode;
}

/** The library order: available games first, archived ones after, each by name. */
export function libraryOrder(games: readonly Game[]): Game[] {
  return [...games].sort(
    (a, b) => Number(!a.active) - Number(!b.active) || a.name.localeCompare(b.name),
  );
}

/**
 * What a delete would do, from the game's usage: delete it for good, or explain why not (and
 * offer to archive it when it is still available). The server re-checks under a lock.
 */
export type DeletePlan =
  | { readonly kind: 'delete' }
  | { readonly kind: 'in_play' }
  | { readonly kind: 'history'; readonly records: number };

export function deletePlan(usage: { playingNow: number; records: number }): DeletePlan {
  if (usage.playingNow > 0) return { kind: 'in_play' };
  if (usage.records > 0) return { kind: 'history', records: usage.records };
  return { kind: 'delete' };
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
