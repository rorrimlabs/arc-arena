import { Service, inject } from '@angular/core';
import type { PostgrestError } from '@supabase/supabase-js';
import { dbError } from '../arena/arena-api';
import { Supabase } from '../supabase/supabase';
import { SyncOp, pushOps } from '../sync/push-ops';
import {
  AgeRating,
  BillKind,
  BillStatus,
  Charge,
  CompatStatus,
  Customer,
  Game,
  GameCompat,
  GameInput,
  GameUsage,
  Play,
  Station,
  StationInput,
  StationStatus,
  Visit,
} from './floor.models';

/**
 * The arena's floor and catalog for the dashboard: stations, games, members, play history and
 * billed charges, read straight from the tables (RLS scopes every row to the caller's arenas).
 * Writes are `resource.*` / `game.*` ops through sync_push — the same path, `settings`
 * permission check and history as the floor app. Tests provide SampleFloorApi.
 */
@Service({ factory: () => new SupabaseFloorApi() })
export abstract class FloorApi {
  /** Every station, removed (disabled) ones included. */
  abstract stations(arenaId: string): Promise<Station[]>;
  abstract games(arenaId: string): Promise<Game[]>;
  /** Where each game can be played (game_resources rows; a missing pair is not installed). */
  abstract gameResources(arenaId: string): Promise<GameCompat[]>;
  /** Registered members (walk-in guests left out). */
  abstract customers(arenaId: string): Promise<Customer[]>;
  /** Plays that started at or after `since`, plus every one still open. */
  abstract plays(arenaId: string, since: Date): Promise<Play[]>;
  /** Billed lines of bills that were not voided, by segment start in [from, to). */
  abstract charges(arenaId: string, from: Date, to: Date): Promise<Charge[]>;
  /** Bills that started at or after `since`, plus every one still running. */
  abstract visits(arenaId: string, since: Date): Promise<Visit[]>;

  abstract saveStation(arenaId: string, station: StationInput): Promise<void>;
  abstract setStationStatus(arenaId: string, id: string, status: StationStatus): Promise<void>;
  /**
   * Saves the game, then marks it playable on `playableOn` (station ids), in one batch.
   * `baseActive` is the active flag the editor showed: the server refuses the edit (stale) if the
   * game was archived or restored elsewhere meanwhile, instead of flipping it back.
   */
  abstract saveGame(
    arenaId: string,
    game: GameInput,
    playableOn?: readonly string[],
    baseActive?: boolean,
  ): Promise<void>;
  /** Archives (false) or restores (true) a game (game.set_active). */
  abstract setGameActive(arenaId: string, id: string, active: boolean): Promise<void>;
  /** What still refers to the game (read before offering a delete). */
  abstract gameUsage(arenaId: string, gameId: string): Promise<GameUsage>;
  /**
   * Deletes a game nothing ever used (game.delete). Refused with game_in_play or
   * game_has_history otherwise: archive it instead.
   */
  abstract deleteGame(arenaId: string, id: string): Promise<void>;
  /** How the game runs on one station (game.set_compat, an upsert per game and station). */
  abstract setGameCompat(
    arenaId: string,
    gameId: string,
    resourceId: string,
    status: CompatStatus,
  ): Promise<void>;
}

export const FLOOR_MESSAGES: Readonly<Record<string, string>> = {
  forbidden: 'You need the Settings permission for that',
  duplicate: 'That name is already in use',
  not_found: 'That is no longer there. Refresh',
  mode_switch_busy: 'The station has a live session · end it on the floor first',
  resource_busy: 'The station has a live session · end it on the floor first',
  missing_reference: 'That game or station is no longer there. Refresh',
  invalid_name: 'Enter a title of up to 80 characters',
  invalid: 'Check the values and try again',
  stale: 'It was archived or restored elsewhere meanwhile. Check it and save again',
  game_in_play:
    'A station is playing it right now, so it cannot be deleted. Archive it instead, or wait until those sessions end',
  game_has_history:
    'Sessions or bookings already use it, so it cannot be deleted. Archive it instead: past bills keep it',
};

type Row = Record<string, unknown>;

const PAGE = 1000;

const str = (v: unknown) => (v == null ? null : String(v));
const strings = (v: unknown) => ((v as unknown[] | null) ?? []).map(String);
const one = (v: unknown) => (Array.isArray(v) ? (v[0] as Row | undefined) : (v as Row | null));

export function stationOps(s: StationInput): SyncOp[] {
  return [
    {
      kind: 'resource.upsert',
      payload: {
        id: s.id,
        name: s.name,
        kind: s.kind,
        // Absent on an edit: the server keeps the stored status.
        ...(s.status === undefined ? {} : { status: s.status }),
        sort_order: s.sortOrder,
        activity_codes: s.activityCodes,
      },
    },
  ];
}

/** game.upsert; `baseActive` (an edit) lets the server refuse it over a newer archive/restore. */
export function gameOps(g: GameInput, baseActive?: boolean): SyncOp[] {
  return [
    {
      kind: 'game.upsert',
      payload: {
        id: g.id,
        name: g.name,
        aliases: g.aliases,
        category_id: g.categoryId,
        platforms: g.platforms,
        player_mode: g.playerMode,
        max_local_players: g.maxLocalPlayers,
        active: g.active,
        ...(baseActive === undefined ? {} : { base_active: baseActive }),
        age_rating: g.ageRating,
        media: g.media,
      },
    },
  ];
}

/**
 * game.set_compat: how one game runs on one station (the server upserts the pair). No notes key:
 * the dashboard does not show station notes, so it keeps the one staff wrote on the floor app.
 */
export function compatOps(gameId: string, resourceId: string, status: CompatStatus): SyncOp[] {
  return [
    {
      kind: 'game.set_compat',
      payload: { game_id: gameId, resource_id: resourceId, status },
    },
  ];
}

const COMPAT_STATUSES: readonly CompatStatus[] = [
  'playable',
  'not_installed',
  'not_playable',
  'maintenance',
  'temporarily_unavailable',
];

class SupabaseFloorApi extends FloorApi {
  private readonly supabase = inject(Supabase);

  async stations(arenaId: string): Promise<Station[]> {
    const [resources, links, activities] = await Promise.all([
      this.all('resources', 'id, name, kind, status, sort_order', arenaId, (q) =>
        q.order('sort_order').order('name'),
      ),
      this.all('resource_activities', 'id, resource_id, activity_id', arenaId),
      this.all('activities', 'id, code', arenaId),
    ]);
    const codeOf = new Map(activities.map((a) => [String(a['id']), String(a['code'])]));
    const codes = new Map<string, string[]>();
    for (const l of links) {
      const code = codeOf.get(String(l['activity_id']));
      if (!code) continue;
      const list = codes.get(String(l['resource_id'])) ?? [];
      list.push(code);
      codes.set(String(l['resource_id']), list);
    }
    return resources.map((r) => ({
      id: String(r['id']),
      name: String(r['name']),
      kind: (r['kind'] as Station['kind']) ?? 'station',
      status: (r['status'] as StationStatus) ?? 'available',
      sortOrder: Number(r['sort_order'] ?? 0),
      activityCodes: codes.get(String(r['id'])) ?? [],
    }));
  }

  async games(arenaId: string): Promise<Game[]> {
    const rows = await this.all(
      'games',
      'id, name, aliases, category_id, platforms, player_mode, max_local_players, active, age_rating, media',
      arenaId,
      (q) => q.order('name'),
    );
    return rows.map((r) => ({
      id: String(r['id']),
      name: String(r['name']),
      aliases: strings(r['aliases']),
      categoryId: str(r['category_id']),
      platforms: strings(r['platforms']),
      playerMode: (r['player_mode'] as Game['playerMode']) ?? 'single',
      maxLocalPlayers: Number(r['max_local_players'] ?? 1),
      active: r['active'] !== false,
      ageRating: r['age_rating'] == null ? null : (Number(r['age_rating']) as AgeRating),
      media: r['media'] === 'digital' || r['media'] === 'disc' ? r['media'] : null,
    }));
  }

  async gameResources(arenaId: string): Promise<GameCompat[]> {
    const rows = await this.all(
      'game_resources',
      'game_id, resource_id, status',
      arenaId,
      (q) => q,
      // Keyed by the pair (no id column).
      ['game_id', 'resource_id'],
    );
    return rows.map((r) => {
      const status = String(r['status']) as CompatStatus;
      return {
        gameId: String(r['game_id']),
        resourceId: String(r['resource_id']),
        // An unknown status blocks the game there, like the server's _game_playable.
        status: COMPAT_STATUSES.includes(status) ? status : 'not_playable',
      };
    });
  }

  async customers(arenaId: string): Promise<Customer[]> {
    const rows = await this.all(
      'customers',
      'id, name, phone, last_visit_at, created_at, birth_year',
      arenaId,
      (q) => q.eq('is_guest', false).order('name'),
    );
    return rows.map((r) => ({
      id: String(r['id']),
      name: String(r['name']),
      phone: str(r['phone']),
      lastVisitAt: str(r['last_visit_at']),
      createdAt: String(r['created_at']),
      birthYear: r['birth_year'] == null ? null : Number(r['birth_year']),
    }));
  }

  async plays(arenaId: string, since: Date): Promise<Play[]> {
    const window = `ended_at.is.null,started_at.gte.${since.toISOString()}`;
    const cols = 'id, resource_id, activity_code, game_id, controller_count, started_at, ended_at';
    const [segments, assignments] = await Promise.all([
      this.all(
        'session_segments',
        `${cols}, session_id, sessions!inner(customer_id, status, scheduled_end_at)`,
        arenaId,
        (q) => q.or(window),
      ),
      this.all(
        'group_assignments',
        `${cols}, group_id, group_sessions!inner(primary_customer_id, status, scheduled_end_at)`,
        arenaId,
        (q) => q.or(window),
      ),
    ]);
    const play = (r: Row, kind: BillKind, billId: string, parent: Row | null | undefined) => ({
      id: String(r['id']),
      kind,
      billId,
      billStatus: (parent?.['status'] as BillStatus) ?? 'completed',
      customerId: String(parent?.['customer_id'] ?? parent?.['primary_customer_id'] ?? ''),
      resourceId: String(r['resource_id']),
      activityCode: String(r['activity_code']),
      gameId: str(r['game_id']),
      controllers: r['controller_count'] == null ? null : Number(r['controller_count']),
      startedAt: String(r['started_at']),
      endedAt: str(r['ended_at']),
      scheduledEndAt: String(parent?.['scheduled_end_at'] ?? r['started_at']),
    });
    return [
      ...segments.map((r) => play(r, 'single', String(r['session_id']), one(r['sessions']))),
      ...assignments.map((r) => play(r, 'group', String(r['group_id']), one(r['group_sessions']))),
    ];
  }

  async charges(arenaId: string, from: Date, to: Date): Promise<Charge[]> {
    const cols = 'resource_id, activity_code, segment_start, played_minutes, amount_paise';
    const range = (q: Query) =>
      q.gte('segment_start', from.toISOString()).lt('segment_start', to.toISOString());
    const [single, group] = await Promise.all([
      this.all('session_charges', `${cols}, session_id, sessions!inner(status)`, arenaId, (q) =>
        range(q).neq('sessions.status', 'voided'),
      ),
      this.all('group_charges', `${cols}, group_id, group_sessions!inner(status)`, arenaId, (q) =>
        range(q).neq('group_sessions.status', 'voided'),
      ),
    ]);
    const charge = (r: Row, kind: BillKind, billId: string): Charge => ({
      kind,
      billId,
      resourceId: str(r['resource_id']),
      activityCode: String(r['activity_code']),
      segmentStart: String(r['segment_start']),
      playedMinutes: Number(r['played_minutes'] ?? 0),
      amountPaise: Number(r['amount_paise'] ?? 0),
    });
    return [
      ...single.map((r) => charge(r, 'single', String(r['session_id']))),
      ...group.map((r) => charge(r, 'group', String(r['group_id']))),
    ];
  }

  async visits(arenaId: string, since: Date): Promise<Visit[]> {
    const window = `status.eq.active,started_at.gte.${since.toISOString()}`;
    const cols = 'id, status, started_at, actual_ended_at, billed_amount_paise';
    const [sessions, groups] = await Promise.all([
      this.all('sessions', `${cols}, customer_id`, arenaId, (q) => q.or(window)),
      this.all('group_sessions', `${cols}, primary_customer_id`, arenaId, (q) => q.or(window)),
    ]);
    const visit = (r: Row, kind: BillKind, customerId: unknown): Visit => ({
      kind,
      id: String(r['id']),
      customerId: String(customerId),
      status: (r['status'] as BillStatus) ?? 'completed',
      startedAt: String(r['started_at']),
      endedAt: str(r['actual_ended_at']),
      billedPaise: r['billed_amount_paise'] == null ? null : Number(r['billed_amount_paise']),
    });
    return [
      ...sessions.map((r) => visit(r, 'single', r['customer_id'])),
      ...groups.map((r) => visit(r, 'group', r['primary_customer_id'])),
    ];
  }

  async saveStation(arenaId: string, station: StationInput): Promise<void> {
    await pushOps(await this.supabase.client(), arenaId, stationOps(station), FLOOR_MESSAGES);
  }

  async setStationStatus(arenaId: string, id: string, status: StationStatus): Promise<void> {
    await pushOps(
      await this.supabase.client(),
      arenaId,
      [{ kind: 'resource.set_status', payload: { id, status } }],
      FLOOR_MESSAGES,
    );
  }

  async saveGame(
    arenaId: string,
    game: GameInput,
    playableOn: readonly string[] = [],
    baseActive?: boolean,
  ): Promise<void> {
    // Ops apply in order: the game exists before its stations are marked.
    const ops = [
      ...gameOps(game, baseActive),
      ...playableOn.flatMap((resourceId) => compatOps(game.id, resourceId, 'playable')),
    ];
    await pushOps(await this.supabase.client(), arenaId, ops, FLOOR_MESSAGES);
  }

  async gameUsage(arenaId: string, gameId: string): Promise<GameUsage> {
    const client = await this.supabase.client();
    const count = async (table: string, openOnly: boolean): Promise<number> => {
      let q = client
        .from(table)
        .select('id', { count: 'exact', head: true })
        .eq('arena_id', arenaId)
        .eq('game_id', gameId);
      if (openOnly) q = q.is('ended_at', null);
      const { count: n, error } = await q;
      if (error) throw dbError(error);
      return n ?? 0;
    };
    const [segments, openSegments, players, openPlayers, bookings] = await Promise.all([
      count('session_segments', false),
      count('session_segments', true),
      count('group_assignments', false),
      count('group_assignments', true),
      count('bookings', false),
    ]);
    return { playingNow: openSegments + openPlayers, records: segments + players + bookings };
  }

  async deleteGame(arenaId: string, id: string): Promise<void> {
    await pushOps(
      await this.supabase.client(),
      arenaId,
      [{ kind: 'game.delete', payload: { id } }],
      FLOOR_MESSAGES,
    );
  }

  async setGameCompat(
    arenaId: string,
    gameId: string,
    resourceId: string,
    status: CompatStatus,
  ): Promise<void> {
    await pushOps(
      await this.supabase.client(),
      arenaId,
      compatOps(gameId, resourceId, status),
      FLOOR_MESSAGES,
    );
  }

  async setGameActive(arenaId: string, id: string, active: boolean): Promise<void> {
    await pushOps(
      await this.supabase.client(),
      arenaId,
      [{ kind: 'game.set_active', payload: { id, active } }],
      FLOOR_MESSAGES,
    );
  }

  /** Every row of an arena-scoped select, a page (the API's row cap) at a time. */
  private async all(
    table: string,
    columns: string,
    arenaId: string,
    refine: (q: Query) => Query = (q) => q,
    /** The table's unique key, the final sort so pages neither overlap nor skip rows. */
    key: readonly string[] = ['id'],
  ): Promise<Row[]> {
    const client = await this.supabase.client();
    const out: Row[] = [];
    for (let from = 0; ; from += PAGE) {
      const query = key.reduce(
        (q, column) => q.order(column),
        refine(client.from(table).select(columns).eq('arena_id', arenaId) as unknown as Query),
      );
      const { data, error } = (await query.range(from, from + PAGE - 1)) as {
        data: Row[] | null;
        error: PostgrestError | null;
      };
      if (error) throw dbError(error);
      out.push(...(data ?? []));
      if ((data?.length ?? 0) < PAGE) return out;
    }
  }
}

/** The chainable filter builder supabase-js returns from `select()` (kept loose on purpose). */
interface Query {
  eq(column: string, value: unknown): Query;
  neq(column: string, value: unknown): Query;
  gte(column: string, value: unknown): Query;
  lt(column: string, value: unknown): Query;
  or(filters: string): Query;
  order(column: string): Query;
  range(from: number, to: number): PromiseLike<unknown>;
}
