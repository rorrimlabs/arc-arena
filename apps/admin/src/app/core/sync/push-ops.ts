import type { SupabaseClient } from '@supabase/supabase-js';
import { dbError } from '../supabase/db-error';
import { AppError } from '../auth/auth-api';

/** One write for sync_push: an op kind (`activity.upsert`, `rate.upsert`…) and its payload. */
export interface SyncOp {
  readonly kind: string;
  readonly payload: Record<string, unknown>;
  /** The op id to send (an [Attempt]'s); a fresh one when absent. */
  readonly opId?: string;
}

/**
 * The ids of one user action (op id, payment id, adjustment id…): the same on every resend of
 * that action, so a Save repeated after an ambiguous network failure replays the server's first
 * answer instead of recording the money or the adjustment twice. A dialog holds one per opening.
 */
export class Attempt {
  private readonly ids = new Map<string, string>();

  /** The id named `name` for this action, made on first use. */
  id(name: string): string {
    let id = this.ids.get(name);
    if (!id) {
      id = crypto.randomUUID();
      this.ids.set(name, id);
    }
    return id;
  }

  /**
   * After a failed Save. A refusal with nothing applied recorded no money or record, so the
   * next Save (with corrected values) gets new ids instead of replaying that refusal. A lost
   * answer, a `retry` or a partly applied batch keeps them.
   */
  settle(error: unknown): void {
    if (error instanceof PushRefusal && error.code !== 'retry' && !error.applied.length) {
      this.ids.clear();
    }
  }
}

/** The arena's private Realtime channel (Realtime Authorization admits only its members). */
export function arenaTopic(arenaId: string): string {
  return `arena:${arenaId}`;
}

/** Broadcast event both apps use for "these op kinds were just committed: pull". */
export const SYNC_EVENT = 'sync';

/**
 * A refusal from sync_push. `applied` lists the kinds of the batch's ops the server did apply
 * (each op applies on its own), so a caller that sent several knows the server holds part of
 * the change and must reload instead of keeping its drafts.
 */
export class PushRefusal extends AppError {
  constructor(
    code: string,
    message: string,
    readonly applied: readonly string[],
  ) {
    super(code, message);
  }
}

/** True when a write failed after part of its batch was applied (reload what the server holds). */
export function partlyApplied(e: unknown): boolean {
  return e instanceof PushRefusal && e.applied.length > 0;
}

/**
 * Runs a store's write, then `reload`. A refusal is rethrown unchanged; if part of the batch was
 * applied first, the store reloads before rethrowing so the screen never shows unsaved drafts as
 * saved. A refusal of nothing applied leaves the screen (and its drafts) as it was.
 */
export async function writeThenReload(
  write: () => Promise<unknown>,
  reload: () => Promise<void>,
): Promise<void> {
  try {
    await write();
  } catch (e) {
    if (partlyApplied(e)) await reload();
    throw e;
  }
  await reload();
}

/**
 * Sends ops through sync_push — the dashboard's only write path, with the same permission
 * checks and history as the floor app. Each op applies on its own; the first refusal is thrown
 * as a PushRefusal with the server's code, worded by `messages` when known. Resolves with each
 * op's result object, in order.
 *
 * Only after the server answered are the arena's other devices told which kinds were applied
 * (never on a transport error, never for a refused op).
 *
 * An op the server answers `retry` (a lock or serialization conflict: not recorded, and the
 * batch stopped there) is sent again shortly with the same op ids, so the ops already applied
 * replay their answers instead of applying twice. Still busy after that: refused as `retry`.
 */
export async function pushOps(
  client: SupabaseClient,
  arenaId: string,
  ops: readonly SyncOp[],
  messages: Readonly<Record<string, string>> = {},
): Promise<Record<string, unknown>[]> {
  if (!ops.length) return [];
  const batch = ops.map((op) => ({
    op_id: op.opId ?? crypto.randomUUID(),
    kind: op.kind,
    payload: op.payload,
  }));
  let results: PushResult[] = [];
  for (let attempt = 0; ; attempt++) {
    const { data, error } = await client.rpc('sync_push', {
      p_arena: arenaId,
      p_ops: batch,
      p_device: 'admin-web',
    });
    if (error) throw dbError(error);
    results = (data as { results?: PushResult[] } | null)?.results ?? [];
    if (attempt >= RETRY_DELAYS_MS.length || !results.some((r) => r.status === 'retry')) break;
    await new Promise((resolve) => setTimeout(resolve, RETRY_DELAYS_MS[attempt]));
  }
  const applied = ops.filter((_, i) => results[i]?.status === 'applied').map((op) => op.kind);
  void announcePush(client, arenaId, applied);
  const refused = ops.findIndex((_, i) => results[i]?.status !== 'applied');
  if (refused >= 0) {
    const r = results[refused];
    // A `retry` carries the SQLSTATE in `error`; the code to show is `retry` itself.
    const code = r?.status === 'retry' ? 'retry' : (r?.error ?? 'rejected');
    throw new PushRefusal(code, messages[code] ?? OP_MESSAGES[code] ?? code, applied);
  }
  return results.map((r) => r.result ?? {});
}

interface PushResult { status: string; error?: string; result?: Record<string, unknown> }

/** Waits before resending a batch the server answered `retry` (then it is refused). */
const RETRY_DELAYS_MS = [250, 750];

/**
 * Tells the arena's other devices which op kinds were just committed: a nudge to pull, never
 * the data. Uses the live channel when RealtimeSync has it joined, else Realtime's REST
 * endpoint with the signed-in user's token. A lost nudge only delays the others until their next
 * change event or pull, so failures are ignored.
 */
export async function announcePush(
  client: SupabaseClient,
  arenaId: string,
  kinds: readonly string[],
): Promise<void> {
  if (!kinds.length) return;
  const payload = {
    arena_id: arenaId,
    kind: 'push',
    kinds: [...new Set(kinds)],
    source: 'admin-web',
    at: new Date().toISOString(),
  };
  try {
    const channel = client.channel(arenaTopic(arenaId), { config: { private: true } });
    if (channel.state === 'joined') {
      await channel.send({ type: 'broadcast', event: SYNC_EVENT, payload });
    } else {
      await client.realtime.setAuth();
      await channel.httpSend(SYNC_EVENT, payload);
    }
  } catch {
    // Not delivered: the other devices still see the rows through their own change feed.
  }
}

/** Refusals any op can return. */
const OP_MESSAGES: Readonly<Record<string, string>> = {
  forbidden: 'You need the Settings permission for that',
  not_found: 'That is no longer there. Refresh',
  duplicate: 'That name is already in use',
  invalid: 'Check the values and try again',
  invalid_payload: 'Check the values and try again',
  retry: 'Busy right now. Try again',
};
