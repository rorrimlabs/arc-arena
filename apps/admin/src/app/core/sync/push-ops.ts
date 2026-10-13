import type { SupabaseClient } from '@supabase/supabase-js';
import { dbError } from '../supabase/db-error';
import { AppError } from '../auth/auth-api';

/** One write for sync_push: an op kind (`activity.upsert`, `rate.upsert`…) and its payload. */
export interface SyncOp {
  readonly kind: string;
  readonly payload: Record<string, unknown>;
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
 */
export async function pushOps(
  client: SupabaseClient,
  arenaId: string,
  ops: readonly SyncOp[],
  messages: Readonly<Record<string, string>> = {},
): Promise<Record<string, unknown>[]> {
  if (!ops.length) return [];
  const { data, error } = await client.rpc('sync_push', {
    p_arena: arenaId,
    p_ops: ops.map((op) => ({ op_id: crypto.randomUUID(), kind: op.kind, payload: op.payload })),
    p_device: 'admin-web',
  });
  if (error) throw dbError(error);
  const results =
    (
      data as {
        results?: { status: string; error?: string; result?: Record<string, unknown> }[];
      } | null
    )?.results ?? [];
  const applied = ops.filter((_, i) => results[i]?.status === 'applied').map((op) => op.kind);
  void announcePush(client, arenaId, applied);
  const refused = ops.findIndex((_, i) => results[i]?.status !== 'applied');
  if (refused >= 0) {
    const code = results[refused]?.error ?? 'rejected';
    throw new PushRefusal(code, messages[code] ?? OP_MESSAGES[code] ?? code, applied);
  }
  return results.map((r) => r.result ?? {});
}

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
