import { Service, computed, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { LoginScope } from '../../../core/auth/login-scope';
import { dbError } from '../../../core/supabase/db-error';
import { Supabase } from '../../../core/supabase/supabase';
import { Attempt, pushOps } from '../../../core/sync/push-ops';

/**
 * The venue's staff terms (docs/STAFF_API.md): append-only versions in `staff_terms`, the
 * highest in force; publishing one (`terms.publish`, owner level) asks every member who is not
 * owner level to accept it on the floor app (`staff_terms_acceptances`, written there only).
 */
export interface StaffTerms {
  readonly id: string;
  readonly version: number;
  readonly title: string;
  /** Plain text; paragraphs are separated by blank lines. */
  readonly body: string;
  readonly publishedAt: string;
}

export interface TermsAcceptance {
  readonly staffId: string;
  readonly termsId: string;
  /** Server time. */
  readonly acceptedAt: string;
}

/** A member of the arena, for the acceptance list. */
export interface TermsMember {
  readonly id: string;
  readonly name: string;
  readonly role: 'owner' | 'staff';
  readonly perms: readonly string[];
  readonly active: boolean;
}

export interface TermsData {
  /** The version in force (with its body), or null before the first publish. */
  readonly current: StaffTerms | null;
  /** Every version's number by id (older ones without their body). */
  readonly versionOf: ReadonlyMap<string, number>;
  readonly acceptances: readonly TermsAcceptance[];
  readonly members: readonly TermsMember[];
}

/** The latest version a member accepted. */
export interface AcceptedTerms {
  readonly version: number;
  readonly acceptedAt: string;
}

export const TERMS_LIMITS = { title: 120, body: 50_000 } as const;

export const TERMS_MESSAGES: Readonly<Record<string, string>> = {
  forbidden: 'Only an owner can publish the staff terms',
  invalid_payload: 'Give the terms a title (up to 120 characters) and a text (up to 50,000)',
  duplicate: 'That version was already published. Refresh',
};

/** Owner level (app_is_owner): never asked to accept the terms. */
export function exemptFromTerms(m: { role: string; perms: readonly string[] }): boolean {
  return m.role === 'owner' || m.perms.includes('money') || m.perms.includes('reports');
}

/** The body as paragraphs (split on blank lines); single newlines stay inside a paragraph. */
export function termsParagraphs(body: string): string[] {
  return body
    .split(/\n[ \t]*\n/)
    .map((p) => p.trim())
    .filter(Boolean);
}

export interface TermsDraft {
  readonly title: string;
  readonly body: string;
}

export type TermsProblems = Partial<Record<keyof TermsDraft, string>>;

/** The server's checks, on the trimmed text. */
export function termsProblems(d: TermsDraft): TermsProblems {
  const problems: TermsProblems = {};
  const title = d.title.trim();
  const body = d.body.trim();
  if (!title || title.length > TERMS_LIMITS.title) {
    problems.title = 'The title must be 1 to 120 characters';
  }
  if (!body || body.length > TERMS_LIMITS.body) {
    problems.body = 'The text must be 1 to 50,000 characters';
  }
  return problems;
}

/** Reads the terms, acceptances and members (RLS); publishes through sync_push. */
@Service({ factory: () => new SupabaseTermsApi() })
export abstract class TermsApi {
  abstract load(arenaId: string): Promise<TermsData>;
  /** Resolves with the new version number. */
  abstract publish(arenaId: string, draft: TermsDraft, attempt: Attempt): Promise<number>;
}

type Row = Record<string, unknown>;

class SupabaseTermsApi extends TermsApi {
  private readonly supabase = inject(Supabase);

  async load(arenaId: string): Promise<TermsData> {
    const client = await this.supabase.client();
    const [current, versions, acceptances, members] = await Promise.all([
      client
        .from('staff_terms')
        .select('id, version, title, body, published_at')
        .eq('arena_id', arenaId)
        .order('version', { ascending: false })
        .limit(1)
        .maybeSingle(),
      client.from('staff_terms').select('id, version').eq('arena_id', arenaId),
      client
        .from('staff_terms_acceptances')
        .select('staff_id, terms_id, accepted_at')
        .eq('arena_id', arenaId),
      client
        .from('staff_profiles')
        .select('id, name, role, perms, active')
        .eq('arena_id', arenaId)
        .order('name'),
    ]);
    for (const r of [current, versions, acceptances, members]) {
      if (r.error) throw dbError(r.error);
    }
    const c = current.data as Row | null;
    return {
      current: c
        ? {
            id: String(c['id']),
            version: Number(c['version']),
            title: String(c['title'] ?? ''),
            body: String(c['body'] ?? ''),
            publishedAt: String(c['published_at']),
          }
        : null,
      versionOf: new Map(
        ((versions.data as Row[]) ?? []).map((v) => [String(v['id']), Number(v['version'])]),
      ),
      acceptances: ((acceptances.data as Row[]) ?? []).map((a) => ({
        staffId: String(a['staff_id']),
        termsId: String(a['terms_id']),
        acceptedAt: String(a['accepted_at']),
      })),
      members: ((members.data as Row[]) ?? []).map((m) => ({
        id: String(m['id']),
        name: String(m['name'] ?? ''),
        role: m['role'] === 'owner' ? 'owner' : 'staff',
        perms: (m['perms'] as string[] | null) ?? [],
        active: m['active'] === true,
      })),
    };
  }

  async publish(arenaId: string, draft: TermsDraft, attempt: Attempt): Promise<number> {
    const [result] = await pushOps(
      await this.supabase.client(),
      arenaId,
      [
        {
          kind: 'terms.publish',
          opId: attempt.id('op'),
          payload: { id: attempt.id('terms'), title: draft.title.trim(), body: draft.body.trim() },
        },
      ],
      TERMS_MESSAGES,
    );
    return Number(result?.['version'] ?? 0);
  }
}

/** The current arena's staff terms; a publish goes to the server first, then reloads. */
@Service()
export class TermsStore {
  private readonly api = inject(TermsApi);
  private readonly arena = inject(ArenaContext);

  readonly data = signal<TermsData | null>(null);
  readonly loading = signal(false);
  readonly loadError = signal('');
  readonly current = computed(() => this.data()?.current ?? null);
  /** Each member's latest accepted version. */
  readonly acceptedOf = computed(() => {
    const d = this.data();
    const map = new Map<string, AcceptedTerms>();
    for (const a of d?.acceptances ?? []) {
      const version = d?.versionOf.get(a.termsId);
      if (version === undefined) continue;
      const seen = map.get(a.staffId);
      if (!seen || version > seen.version) map.set(a.staffId, { version, acceptedAt: a.acceptedAt });
    }
    return map;
  });
  private loadedArena: string | null = null;
  private latest = 0;

  constructor() {
    inject(LoginScope).onEnd(() => {
      this.latest++;
      this.loadedArena = null;
      this.data.set(null);
      this.loading.set(false);
      this.loadError.set('');
    });
  }

  async load(force = false): Promise<void> {
    const arenaId = this.arena.current().id;
    if (!arenaId || (!force && this.loadedArena === arenaId)) return;
    if (this.loadedArena !== arenaId) this.data.set(null);
    const call = ++this.latest;
    this.loading.set(true);
    this.loadError.set('');
    try {
      const data = await this.api.load(arenaId);
      if (call !== this.latest) return;
      this.data.set(data);
      this.loadedArena = arenaId;
    } catch (e) {
      if (call === this.latest) this.loadError.set(toAppError(e).message);
    } finally {
      if (call === this.latest) this.loading.set(false);
    }
  }

  async publish(draft: TermsDraft, attempt = new Attempt()): Promise<number> {
    const version = await this.api.publish(this.arena.current().id, draft, attempt);
    await this.load(true);
    return version;
  }
}
