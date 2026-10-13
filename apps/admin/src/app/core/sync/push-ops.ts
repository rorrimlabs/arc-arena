import type { SupabaseClient } from '@supabase/supabase-js';
import { dbError } from '../arena/arena-api';
import { AppError } from '../auth/auth-api';

/** One write for sync_push: an op kind (`activity.upsert`, `rate.upsert`…) and its payload. */
export interface SyncOp {
  readonly kind: string;
  readonly payload: Record<string, unknown>;
}

/**
 * Sends ops through sync_push — the dashboard's only write path, with the same permission
 * checks and history as the floor app. Each op applies on its own; the first refusal is thrown
 * as an AppError with the server's code, worded by `messages` when known. Resolves with each
 * op's result object, in order.
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
  const results = (
    data as { results: { status: string; error?: string; result?: Record<string, unknown> }[] }
  ).results;
  const refused = results.find((r) => r.status !== 'applied');
  if (refused) {
    const code = refused.error ?? 'rejected';
    throw new AppError(code, messages[code] ?? OP_MESSAGES[code] ?? code);
  }
  return results.map((r) => r.result ?? {});
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
