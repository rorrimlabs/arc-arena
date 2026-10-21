import { Service, computed, inject, signal } from '@angular/core';
import { CanMatchFn, Router } from '@angular/router';
import { ArenaContext } from '../arena/arena-context';
import { LoginScope } from '../auth/login-scope';
import { dbError } from '../supabase/db-error';
import { Supabase } from '../supabase/supabase';
import { pushOps } from '../sync/push-ops';

/**
 * What kind of venue this is, as far as the dashboard needs to know: which optional parts it
 * uses (worked out from its active station types, never from a business category) and what it
 * calls the things it rents out (settings key `venue_profile`).
 *
 * The floor app applies the same rule (apps/mobile/lib/domain/services/venue_capabilities.dart).
 * Visibility only: the server still enforces every permission and op whatever is shown.
 */
export type Capability = 'games' | 'equipment';

/** The nouns the server accepts (_venue_profile). */
export type ResourceNoun = 'station' | 'table' | 'ground' | 'court' | 'machine' | 'room';
export const RESOURCE_NOUNS: readonly ResourceNoun[] = [
  'station',
  'table',
  'ground',
  'court',
  'machine',
  'room',
];

/** "Table" / "Tables" for headings, "table" inside a sentence. */
export const NOUN_WORDS: Readonly<Record<ResourceNoun, { one: string; many: string }>> = {
  station: { one: 'Station', many: 'Stations' },
  table: { one: 'Table', many: 'Tables' },
  ground: { one: 'Ground', many: 'Grounds' },
  court: { one: 'Court', many: 'Courts' },
  machine: { one: 'Machine', many: 'Machines' },
  room: { one: 'Room', many: 'Rooms' },
};

/** The flags a capability is derived from, per station type. */
export interface VenueType {
  readonly code: string;
  readonly usesGames: boolean;
  readonly usesControllers: boolean;
  readonly active: boolean;
}

/** One entry of the server's global station type catalog (station_type_catalog()). */
export interface CatalogType {
  readonly code: string;
  readonly name: string;
  readonly group: 'gaming' | 'cue' | 'sports' | 'arcade' | 'other';
  readonly usesControllers: boolean;
  readonly usesGames: boolean;
  readonly durationModel: 'hourly' | 'unit' | 'flat_hourly';
  readonly unitMinutes: number;
  readonly noun: ResourceNoun;
}

/** One entry of the server's global accessory type catalog (accessory_kind_catalog()). */
export interface CatalogAccessory {
  readonly name: string;
  readonly group: CatalogType['group'];
  readonly countsAsController: boolean;
}

export const VENUE_MESSAGES: Readonly<Record<string, string>> = {
  invalid_venue_profile: 'Choose what your venue calls the things it rents out',
  setting_not_shared:
    'This server does not accept a venue profile yet. Apply the latest migrations',
};

/** The capability rule, shared by the store and anything that has types in hand. */
export function capabilitiesOf(types: readonly VenueType[]): ReadonlySet<Capability> {
  const active = types.filter((t) => t.active);
  const caps = new Set<Capability>();
  if (active.some((t) => t.usesGames)) caps.add('games');
  if (active.some((t) => t.usesControllers)) caps.add('equipment');
  return caps;
}

export function parseNoun(json: unknown): ResourceNoun {
  const noun = (json as { resource_noun?: unknown } | null)?.resource_noun;
  return RESOURCE_NOUNS.find((n) => n === noun) ?? 'station';
}

/**
 * The noun a set of chosen catalog types suggests: theirs when they all share one, else station
 * (a mixed venue's generic word).
 */
export function nounFor(types: readonly Pick<CatalogType, 'noun'>[]): ResourceNoun {
  const nouns = new Set(types.map((t) => t.noun));
  return nouns.size === 1 ? [...nouns][0] : 'station';
}

/** What the dashboard reads about the venue in one go. */
export interface VenueData {
  readonly types: VenueType[];
  readonly noun: ResourceNoun;
  /** Whether the owner has saved opening hours (setup resumes at that step otherwise). */
  readonly hoursSaved: boolean;
}

/** Reads type flags and the profile (RLS), the catalog (client RPC); saves via settings.save. */
@Service({ factory: () => new SupabaseVenueApi() })
export abstract class VenueApi {
  abstract load(arenaId: string): Promise<VenueData>;
  abstract catalog(): Promise<CatalogType[]>;
  abstract accessoryCatalog(): Promise<CatalogAccessory[]>;
  abstract saveNoun(arenaId: string, noun: ResourceNoun): Promise<void>;
}

class SupabaseVenueApi extends VenueApi {
  private readonly supabase = inject(Supabase);

  async load(arenaId: string): Promise<VenueData> {
    const client = await this.supabase.client();
    const [types, profile] = await Promise.all([
      client
        .from('activities')
        .select('code, uses_games, uses_controllers, active')
        .eq('arena_id', arenaId),
      client
        .from('settings')
        .select('key, json')
        .eq('arena_id', arenaId)
        .in('key', ['venue_profile', 'business_hours']),
    ]);
    if (types.error) throw dbError(types.error);
    if (profile.error) throw dbError(profile.error);
    const settings = profile.data as { key: string; json: unknown }[];
    return {
      types: (
        types.data as {
          code: string;
          uses_games: boolean;
          uses_controllers: boolean;
          active: boolean;
        }[]
      ).map((t) => ({
        code: t.code,
        usesGames: t.uses_games,
        usesControllers: t.uses_controllers,
        active: t.active,
      })),
      noun: parseNoun(settings.find((s) => s.key === 'venue_profile')?.json ?? null),
      hoursSaved: settings.some((s) => s.key === 'business_hours'),
    };
  }

  async catalog(): Promise<CatalogType[]> {
    const client = await this.supabase.client();
    const { data, error } = await client.rpc('station_type_catalog');
    if (error) throw dbError(error);
    return ((data ?? []) as Record<string, unknown>[]).map((e) => ({
      code: String(e['code']),
      name: String(e['name']),
      group: e['group'] as CatalogType['group'],
      usesControllers: e['uses_controllers'] === true,
      usesGames: e['uses_games'] === true,
      durationModel: e['duration_model'] as CatalogType['durationModel'],
      unitMinutes: Number(e['unit_minutes']),
      noun: parseNoun({ resource_noun: e['noun'] }),
    }));
  }

  async accessoryCatalog(): Promise<CatalogAccessory[]> {
    const client = await this.supabase.client();
    const { data, error } = await client.rpc('accessory_kind_catalog');
    if (error) throw dbError(error);
    return ((data ?? []) as Record<string, unknown>[]).map((e) => ({
      name: String(e['name']),
      group: e['group'] as CatalogType['group'],
      countsAsController: e['counts_as_controller'] === true,
    }));
  }

  async saveNoun(arenaId: string, noun: ResourceNoun): Promise<void> {
    await pushOps(
      await this.supabase.client(),
      arenaId,
      [{ kind: 'settings.save', payload: { key: 'venue_profile', json: { resource_noun: noun } } }],
      VENUE_MESSAGES,
    );
  }
}

/** The current arena's capabilities and noun; follows the selected arena. */
@Service()
export class VenueStore {
  private readonly api = inject(VenueApi);
  private readonly arena = inject(ArenaContext);

  readonly types = signal<readonly VenueType[] | null>(null);
  readonly noun = signal<ResourceNoun>('station');
  readonly hoursSaved = signal(false);
  /** Null until loaded: everything shows meanwhile, so a console venue never sees nav flicker. */
  readonly capabilities = computed<ReadonlySet<Capability> | null>(() => {
    const types = this.types();
    return types ? capabilitiesOf(types) : null;
  });
  readonly words = computed(() => NOUN_WORDS[this.noun()]);
  /** Codes of the active types that pick a game; null until loaded. */
  readonly gameTypeCodes = computed<ReadonlySet<string> | null>(() => {
    const types = this.types();
    return types ? new Set(types.filter((t) => t.active && t.usesGames).map((t) => t.code)) : null;
  });

  private loadedArena: string | null = null;
  private pending: Promise<void> | null = null;
  private latest = 0;

  constructor() {
    inject(LoginScope).onEnd(() => {
      this.latest++;
      this.loadedArena = null;
      this.pending = null;
      this.types.set(null);
      this.noun.set('station');
      this.hoursSaved.set(false);
    });
  }

  /** Whether the venue uses a capability; true until the catalog is known. */
  has(cap: Capability): boolean {
    return this.capabilities()?.has(cap) ?? true;
  }

  /** Loads once per arena (again when forced, e.g. a live update or a setup step). */
  load(force = false): Promise<void> {
    const arenaId = this.arena.current().id;
    if (!arenaId) return Promise.resolve();
    if (!force && this.loadedArena === arenaId) return this.pending ?? Promise.resolve();
    if (this.loadedArena !== arenaId) this.types.set(null);
    this.loadedArena = arenaId;
    const call = ++this.latest;
    this.pending = this.api.load(arenaId).then(
      ({ types, noun, hoursSaved }) => {
        if (call !== this.latest) return;
        this.types.set(types);
        this.noun.set(noun);
        this.hoursSaved.set(hoursSaved);
      },
      () => {
        // Unreadable: keep everything visible (the default) and try again next time.
        if (call === this.latest) this.loadedArena = null;
      },
    );
    return this.pending;
  }

  /** Reads again if anything loaded it (live updates). */
  async refresh(): Promise<void> {
    if (this.loadedArena) await this.load(true);
  }

  async saveNoun(noun: ResourceNoun): Promise<void> {
    await this.api.saveNoun(this.arena.current().id, noun);
    await this.load(true);
  }
}

/** Route guard: the screen exists only for venues using the capability; else Overview. */
export function capabilityGuard(cap: Capability): CanMatchFn {
  return async () => {
    const venue = inject(VenueStore);
    const router = inject(Router);
    await venue.load();
    return venue.has(cap) || router.parseUrl('/overview');
  };
}
