import { Service, computed, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { LoginScope } from '../../../core/auth/login-scope';
import { dbError } from '../../../core/supabase/db-error';
import { Supabase } from '../../../core/supabase/supabase';
import { pushOps } from '../../../core/sync/push-ops';
import { istDayStartOf } from '../../../shared/time/ist';

/**
 * A staff member's optional personal details (`staff_personal_details`, one row per profile;
 * docs/STAFF_API.md): contact, date of birth, blood group, address and emergency contact. Read by
 * the person and owner level; saved with `staff_details.save` (a key left out keeps its value,
 * empty clears it). The server trims and checks every field the same way as detailsProblems.
 */
export const DETAIL_COLUMNS = {
  phone: 'phone',
  email: 'email',
  birthDate: 'birth_date',
  bloodGroup: 'blood_group',
  addressLine1: 'address_line1',
  addressLine2: 'address_line2',
  city: 'city',
  state: 'state',
  pinCode: 'pin_code',
  emergencyName: 'emergency_name',
  emergencyRelation: 'emergency_relation',
  emergencyPhone: 'emergency_phone',
} as const;

export type DetailField = keyof typeof DETAIL_COLUMNS;

/** Every field as typed ('' = not set). */
export type DetailsDraft = Readonly<Record<DetailField, string>>;

export interface PersonalDetails {
  readonly staffId: string;
  readonly fields: DetailsDraft;
  readonly updatedBy: string | null;
  readonly updatedAt: string;
}

export const BLOOD_GROUPS = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'] as const;

/** The server's length limits (characters, after trimming). */
export const DETAIL_MAX: Readonly<Partial<Record<DetailField, number>>> = {
  email: 254,
  addressLine1: 200,
  addressLine2: 200,
  city: 80,
  state: 80,
  emergencyName: 80,
  emergencyRelation: 40,
};

const FIELDS = Object.keys(DETAIL_COLUMNS) as DetailField[];
const PHONE = /^\+?[0-9][0-9 -]{5,18}[0-9]$/;
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const PIN = /^[1-9][0-9]{5}$/;

export const EMPTY_DETAILS: DetailsDraft = Object.fromEntries(
  FIELDS.map((f) => [f, '']),
) as DetailsDraft;

export const DETAILS_MESSAGES: Readonly<Record<string, string>> = {
  forbidden: 'Only the person or an owner can change these details',
  not_found: 'This staff member is no longer there. Refresh',
  invalid_payload: 'The server refused one of the values. Check the fields marked and try again',
};

export type DetailsProblems = Partial<Record<DetailField, string>>;

/** The server's checks on the trimmed draft; `today` is the IST date ("2026-10-16"). */
export function detailsProblems(d: DetailsDraft, today: string): DetailsProblems {
  const p: DetailsProblems = {};
  const v = (f: DetailField) => d[f].trim();
  for (const f of ['phone', 'emergencyPhone'] as const) {
    if (v(f) && !PHONE.test(v(f))) {
      p[f] = 'Use 7 to 20 digits, spaces or dashes, with an optional + first';
    }
  }
  if (v('email') && (v('email').length > 254 || !EMAIL.test(v('email')))) {
    p.email = 'Enter an e-mail like name@example.com';
  }
  const birth = v('birthDate');
  if (birth && (!istDayStartOf(birth) || birth < '1900-01-01' || birth > today)) {
    p.birthDate = 'The date of birth must be from 1900 to today';
  }
  if (v('bloodGroup') && !(BLOOD_GROUPS as readonly string[]).includes(v('bloodGroup'))) {
    p.bloodGroup = 'Pick a blood group from the list';
  }
  if (v('pinCode') && !PIN.test(v('pinCode'))) {
    p.pinCode = 'Six digits, not starting with 0';
  }
  for (const f of FIELDS) {
    const max = DETAIL_MAX[f];
    if (max && !p[f] && v(f).length > max) p[f] = `At most ${max} characters`;
  }
  return p;
}

export function sameDetails(a: DetailsDraft, b: DetailsDraft): boolean {
  return FIELDS.every((f) => a[f].trim() === b[f].trim());
}

/** The `staff_details.save` payload: only the changed keys (trimmed; empty = null, cleared). */
export function detailsPayload(
  staffId: string,
  draft: DetailsDraft,
  saved: DetailsDraft,
): Record<string, unknown> {
  const payload: Record<string, unknown> = { staff_id: staffId };
  for (const f of FIELDS) {
    const value = draft[f].trim();
    if (value !== saved[f].trim()) payload[DETAIL_COLUMNS[f]] = value || null;
  }
  return payload;
}

/** Reads the arena's rows (RLS: owner level reads everyone's); saves through sync_push. */
@Service({ factory: () => new SupabasePersonalDetailsApi() })
export abstract class PersonalDetailsApi {
  abstract load(arenaId: string): Promise<PersonalDetails[]>;
  abstract save(arenaId: string, payload: Record<string, unknown>): Promise<void>;
}

class SupabasePersonalDetailsApi extends PersonalDetailsApi {
  private readonly supabase = inject(Supabase);

  async load(arenaId: string): Promise<PersonalDetails[]> {
    const client = await this.supabase.client();
    const { data, error } = await client
      .from('staff_personal_details')
      .select('*')
      .eq('arena_id', arenaId);
    if (error) throw dbError(error);
    return ((data as Record<string, unknown>[]) ?? []).map((r) => ({
      staffId: String(r['staff_id']),
      fields: Object.fromEntries(
        FIELDS.map((f) => [f, r[DETAIL_COLUMNS[f]] == null ? '' : String(r[DETAIL_COLUMNS[f]])]),
      ) as DetailsDraft,
      updatedBy: r['updated_by'] == null ? null : String(r['updated_by']),
      updatedAt: String(r['updated_at']),
    }));
  }

  async save(arenaId: string, payload: Record<string, unknown>): Promise<void> {
    await pushOps(
      await this.supabase.client(),
      arenaId,
      [{ kind: 'staff_details.save', payload }],
      DETAILS_MESSAGES,
    );
  }
}

/** The current arena's personal details; a save goes to the server first, then reloads. */
@Service()
export class PersonalDetailsStore {
  private readonly api = inject(PersonalDetailsApi);
  private readonly arena = inject(ArenaContext);

  readonly rows = signal<readonly PersonalDetails[] | null>(null);
  readonly loading = signal(false);
  readonly loadError = signal('');
  readonly byStaff = computed(() => new Map((this.rows() ?? []).map((r) => [r.staffId, r])));
  private loadedArena: string | null = null;
  private latest = 0;

  constructor() {
    inject(LoginScope).onEnd(() => {
      this.latest++;
      this.loadedArena = null;
      this.rows.set(null);
      this.loading.set(false);
      this.loadError.set('');
    });
  }

  async load(force = false): Promise<void> {
    const arenaId = this.arena.current().id;
    if (!arenaId || (!force && this.loadedArena === arenaId)) return;
    if (this.loadedArena !== arenaId) this.rows.set(null);
    const call = ++this.latest;
    this.loading.set(true);
    this.loadError.set('');
    try {
      const rows = await this.api.load(arenaId);
      if (call !== this.latest) return;
      this.rows.set(rows);
      this.loadedArena = arenaId;
    } catch (e) {
      if (call === this.latest) this.loadError.set(toAppError(e).message);
    } finally {
      if (call === this.latest) this.loading.set(false);
    }
  }

  async save(staffId: string, draft: DetailsDraft): Promise<void> {
    const saved = this.byStaff().get(staffId)?.fields ?? EMPTY_DETAILS;
    await this.api.save(this.arena.current().id, detailsPayload(staffId, draft, saved));
    await this.load(true);
  }
}
