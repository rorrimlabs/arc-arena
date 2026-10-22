import type { SupabaseClient } from '@supabase/supabase-js';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { AppError } from '../auth/auth-api';
import { PushRefusal, partlyApplied, pushOps, writeThenReload } from './push-ops';

interface Result { status: string; error?: string; result?: Record<string, unknown> }

describe('pushOps', () => {
  const order: string[] = [];
  let channelState: string;
  let reply: { data: { results: Result[] } | null; error: unknown };

  const channel = {
    get state() {
      return channelState;
    },
    send: vi.fn(async (_message: unknown) => {
      order.push('ws-send');
      return 'ok';
    }),
    httpSend: vi.fn(async (_event: string, _payload: unknown) => {
      order.push('http-send');
      return { success: true };
    }),
  };
  const client = {
    rpc: vi.fn(async (_fn: string, _args: unknown) => {
      order.push('rpc');
      return reply;
    }),
    channel: vi.fn((_topic: string, _params: unknown) => channel),
    realtime: { setAuth: vi.fn(async () => order.push('setAuth')) },
  } as unknown as SupabaseClient;

  const flush = () => new Promise((r) => setTimeout(r));
  const sent = () =>
    [
      ...channel.send.mock.calls.map((c) => (c[0] as { payload: unknown }).payload),
      ...channel.httpSend.mock.calls.map((c) => c[1]),
    ] as { arena_id: string; kind: string; kinds: string[]; source: string; at: string }[];

  beforeEach(() => {
    vi.clearAllMocks();
    order.length = 0;
    channelState = 'joined';
    reply = { data: { results: [] }, error: null };
  });

  it('announces the applied kinds only after the server answered', async () => {
    reply = {
      data: { results: [{ status: 'applied', result: { id: 'x' } }, { status: 'applied' }] },
      error: null,
    };
    const results = await pushOps(client, 'a1', [
      { kind: 'game.upsert', payload: { id: 'g1' } },
      { kind: 'game.set_compat', payload: { game_id: 'g1' } },
    ]);
    await flush();

    expect(results).toEqual([{ id: 'x' }, {}]);
    expect(order).toEqual(['rpc', 'ws-send']);
    expect(client.channel).toHaveBeenCalledWith('arena:a1', { config: { private: true } });
    expect(channel.send).toHaveBeenCalledWith(
      expect.objectContaining({ type: 'broadcast', event: 'sync' }),
    );
    expect(sent()).toEqual([
      {
        arena_id: 'a1',
        kind: 'push',
        kinds: ['game.upsert', 'game.set_compat'],
        source: 'admin-web',
        at: expect.any(String),
      },
    ]);
  });

  it('uses the REST endpoint with the user token when the channel is not joined', async () => {
    channelState = 'closed';
    reply = { data: { results: [{ status: 'applied' }] }, error: null };
    await pushOps(client, 'a1', [{ kind: 'rate.upsert', payload: {} }]);
    await flush();

    expect(order).toEqual(['rpc', 'setAuth', 'http-send']);
    expect(channel.httpSend).toHaveBeenCalledWith(
      'sync',
      expect.objectContaining({ arena_id: 'a1', kinds: ['rate.upsert'] }),
    );
  });

  it('a partial failure announces only what was applied, then throws the refusal', async () => {
    reply = {
      data: {
        results: [
          { status: 'applied' },
          { status: 'rejected', error: 'duplicate' },
          { status: 'applied' },
        ],
      },
      error: null,
    };
    const push = pushOps(
      client,
      'a1',
      [
        { kind: 'rate.upsert', payload: {} },
        { kind: 'activity.upsert', payload: {} },
        { kind: 'rate.delete', payload: {} },
      ],
      { duplicate: 'Another type already uses that code' },
    );
    const error = await push.catch((e: unknown) => e);
    await flush();

    expect(error).toBeInstanceOf(PushRefusal);
    expect(error).toMatchObject({
      code: 'duplicate',
      message: 'Another type already uses that code',
      applied: ['rate.upsert', 'rate.delete'],
    });
    expect(partlyApplied(error)).toBe(true);
    expect(sent().map((p) => p.kinds)).toEqual([['rate.upsert', 'rate.delete']]);
  });

  it('a refusal of everything announces nothing', async () => {
    reply = { data: { results: [{ status: 'rejected', error: 'forbidden' }] }, error: null };
    const error = await pushOps(client, 'a1', [{ kind: 'staff.update', payload: {} }]).catch(
      (e: unknown) => e,
    );
    await flush();

    expect(error).toMatchObject({ code: 'forbidden', applied: [] });
    expect(partlyApplied(error)).toBe(false);
    expect(client.channel).not.toHaveBeenCalled();
  });

  it('never announces on a transport error', async () => {
    reply = { data: null, error: new TypeError('Failed to fetch') };
    const error = await pushOps(client, 'a1', [{ kind: 'session.void', payload: {} }]).catch(
      (e: unknown) => e,
    );
    await flush();

    expect(error).toMatchObject({ code: 'network' });
    expect(client.channel).not.toHaveBeenCalled();
    expect(channel.send).not.toHaveBeenCalled();
    expect(channel.httpSend).not.toHaveBeenCalled();
  });

  /** The op ids of the n-th sync_push call. */
  const opIds = (n: number) =>
    (
      (client.rpc as ReturnType<typeof vi.fn>).mock.calls[n][1] as { p_ops: { op_id: string }[] }
    ).p_ops.map((o) => o.op_id);

  it('a busy server (retry) gets the same ops again, so nothing applies twice', async () => {
    (client.rpc as ReturnType<typeof vi.fn>)
      .mockImplementationOnce(async () => ({
        data: { results: [{ status: 'applied' }, { status: 'retry', error: '40001' }] },
        error: null,
      }))
      .mockImplementationOnce(async () => ({
        data: { results: [{ status: 'applied' }, { status: 'applied' }] },
        error: null,
      }));
    const results = await pushOps(client, 'a1', [
      { kind: 'game.upsert', payload: { id: 'g1' } },
      { kind: 'game.set_compat', payload: { game_id: 'g1' } },
    ]);
    expect(results).toEqual([{}, {}]);
    expect(client.rpc).toHaveBeenCalledTimes(2);
    expect(opIds(1)).toEqual(opIds(0));
  });

  it('still busy after the retries: refused as retry, worded, not as a SQLSTATE', async () => {
    reply = { data: { results: [{ status: 'retry', error: '40P01' }] }, error: null };
    const error = await pushOps(client, 'a1', [{ kind: 'game.delete', payload: {} }]).catch(
      (e: unknown) => e,
    );
    expect(client.rpc).toHaveBeenCalledTimes(3);
    expect(error).toMatchObject({ code: 'retry', message: 'Busy right now. Try again' });
  });
});

describe('writeThenReload', () => {
  it('reloads after a save', async () => {
    const reload = vi.fn(async () => undefined);
    await writeThenReload(async () => undefined, reload);
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it('reloads after a partly applied save, then rethrows', async () => {
    const reload = vi.fn(async () => undefined);
    const refusal = new PushRefusal('duplicate', 'Taken', ['rate.upsert']);
    await expect(writeThenReload(async () => Promise.reject(refusal), reload)).rejects.toBe(
      refusal,
    );
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it('keeps the screen (and its drafts) when nothing was applied', async () => {
    const reload = vi.fn(async () => undefined);
    await expect(
      writeThenReload(async () => Promise.reject(new AppError('forbidden', 'No')), reload),
    ).rejects.toMatchObject({ code: 'forbidden' });
    await expect(
      writeThenReload(async () => Promise.reject(new PushRefusal('invalid', 'No', [])), reload),
    ).rejects.toMatchObject({ code: 'invalid' });
    expect(reload).not.toHaveBeenCalled();
  });
});
