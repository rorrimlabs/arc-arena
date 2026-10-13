/**
 * Shared by the dashboard's integration specs (`*.it.spec.ts`). They drive the dashboard's real
 * data layer (the same services the screens use) against the LOCAL Supabase stack — no browser,
 * no UI driving — and run only under `bash tool/sync_it.sh`, which provisions throw-away logins
 * and exports AO_IT_*. Without that environment every integration spec is skipped.
 */
interface Fs {
  writeFileSync(path: string, data: string): void;
  readFileSync(path: string, encoding: 'utf8'): string;
  existsSync(path: string): boolean;
}

interface NodeProcess {
  readonly env: Record<string, string | undefined>;
  getBuiltinModule(id: string): unknown;
}

const nodeProcess = (globalThis as { process?: NodeProcess }).process;

/** AO_IT_* and AO_SUPABASE_* from tool/sync_it.sh (empty outside it). */
export const itEnv: Readonly<Record<string, string | undefined>> = nodeProcess?.env ?? {};

/** Set only inside tool/sync_it.sh. */
export const IT_RUN = itEnv['AO_IT_RUN'];

export function need(name: string): string {
  const v = itEnv[name];
  if (!v) throw new Error(`${name} is not set (run tool/sync_it.sh)`);
  return v;
}

function fs(): Fs {
  return nodeProcess!.getBuiltinModule('node:fs') as Fs;
}

/** A file in the run's hand-off directory, shared with the Flutter phases. */
export const handoff = {
  write(name: string, data: unknown): void {
    fs().writeFileSync(`${need('AO_IT_HANDOFF')}/${name}`, JSON.stringify(data));
  },
  read<T>(name: string): T {
    return JSON.parse(fs().readFileSync(`${need('AO_IT_HANDOFF')}/${name}`, 'utf8')) as T;
  },
  exists(name: string): boolean {
    return fs().existsSync(`${need('AO_IT_HANDOFF')}/${name}`);
  },
};

export async function until(
  check: () => boolean | Promise<boolean>,
  label: string,
  timeoutMs = 30_000,
): Promise<void> {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    if (await check()) return;
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error(`timed out waiting for: ${label}`);
}

/**
 * The newest Supabase Auth link e-mailed to `to`, read from the local mail catcher (Mailpit) —
 * what the invited person would click in their inbox.
 */
export async function latestAuthLink(to: string, timeoutMs = 30_000): Promise<string> {
  const base = need('AO_IT_MAILPIT_URL');
  let link: string | null = null;
  await until(
    async () => {
      const search = await fetch(
        `${base}/api/v1/search?query=${encodeURIComponent(`to:"${to}"`)}`,
      ).then((r) => r.json() as Promise<{ messages?: { ID: string }[] }>);
      const id = search.messages?.[0]?.ID;
      if (!id) return false;
      const msg = await fetch(`${base}/api/v1/message/${id}`).then(
        (r) => r.json() as Promise<{ Text?: string; HTML?: string }>,
      );
      const body = `${msg.Text ?? ''} ${msg.HTML ?? ''}`.replace(/&amp;/g, '&');
      link = /https?:\/\/[^\s"'<>]+\/auth\/v1\/verify\?[^\s"'<>]+/.exec(body)?.[0] ?? null;
      return link !== null;
    },
    `an Auth e-mail to ${to}`,
    timeoutMs,
  );
  return link!;
}

/**
 * Lets the real Realtime WebSocket run under the test DOM (jsdom). jsdom's WebSocket wraps the
 * `undici` client, which builds its `open` event with whatever global `Event` exists — jsdom's —
 * and then dispatches it through Node's own EventTarget, which rejects it ("must be an instance
 * of Event"). Restores Node's native Event class (the parent of the MessageEvent a Node
 * MessageChannel delivers) as the global. Integration specs render no DOM, so nothing else
 * depends on jsdom's Event there. Call once before the first channel is joined.
 */
export async function useNodeEventsForWebSockets(): Promise<void> {
  interface Port {
    addEventListener(type: string, fn: (e: object) => void, opts?: { once: boolean }): void;
    start(): void;
    postMessage(v: unknown): void;
    close(): void;
  }
  const { MessageChannel } = nodeProcess!.getBuiltinModule('node:worker_threads') as {
    MessageChannel: new () => { port1: Port; port2: Port };
  };
  const channel = new MessageChannel();
  const event = await new Promise<object>((resolve) => {
    channel.port2.addEventListener('message', resolve, { once: true });
    channel.port2.start();
    channel.port1.postMessage(0);
  });
  channel.port1.close();
  channel.port2.close();
  const nodeEvent = Object.getPrototypeOf(event.constructor) as typeof Event;
  (globalThis as { Event: typeof Event }).Event = nodeEvent;
}
