// staff-admin — an owner invites someone (staff or co-owner) to the arena from the admin dashboard.
//
// POST { arena_id, email, name, role: 'staff' | 'owner', perms } with the caller's session as the
// Bearer token. Nobody is attached to an arena here and nobody's password is chosen by an owner:
//
// 1. Verifies the caller's session (auth.getUser — a real check against Auth, which is why the
//    function is deployed with --no-verify-jwt).
// 2. Creates the invitation with invite_member, called AS THE CALLER, so the database decides
//    (Settings to invite staff, owner level for money/reports, an owner to invite an owner). It
//    returns a one-time token; only its SHA-256 is stored.
// 3. E-mails the link <ADMIN_SITE_URL or Origin>/accept-invite?invite=<id>&token=<token> to the
//    invited address through Supabase Auth, so only the address's owner receives it:
//      no login uses the address  → Auth invite e-mail (creates the login, unconfirmed until the
//                                    link is opened; the person sets their own password);
//      an unconfirmed login        → its password is scrubbed first (whoever signed it up may not
//                                    own the address), then the invite e-mail;
//      a confirmed login           → a sign-in (magic) link, so they accept as themselves.
//    If the e-mail cannot be sent the invite is withdrawn again.
// 4. Replies the same way whichever case applied, so the response says nothing about whether an
//    address has an account: 200 { status: 'sent', invite_id, expires_at }.
// Membership is created only by accept_invite, when the invited, confirmed login presents the
// token (admin /accept-invite page).
//
// The service-role key lives only in this function's environment and is used for exactly three
// things: invite_delivery_target (which e-mail to send), scrubbing an unconfirmed login's
// password, and sending the Auth invite. Errors: 4xx/5xx { error: <code>, message }; database
// details are never echoed. Optional env: ADMIN_SITE_URL (base of the link), ADMIN_ORIGINS
// (comma-separated origins allowed by CORS; unset = any origin, for local development).
// Auth or the database not answering (down, unreachable, or slower than DEPENDENCY_TIMEOUT_MS) is
// 503 service_unavailable with nothing created, never "session expired" or a refused invite.
import { createClient } from 'npm:@supabase/supabase-js@2.117.3';

const MAX_NAME = 80;

/** Every call to Auth or the database gives up after this long: a hung dependency must not hang
 * the owner's Invite button (the platform's own limit is minutes). */
const DEPENDENCY_TIMEOUT_MS = 10_000;

const timedFetch: typeof fetch = (input, init) => {
  const timeout = AbortSignal.timeout(DEPENDENCY_TIMEOUT_MS);
  return fetch(input, {
    ...init,
    signal: init?.signal ? AbortSignal.any([init.signal, timeout]) : timeout,
  });
};

/**
 * The dependency did not answer: no response at all (status 0: connection refused, DNS, the
 * timeout above), a gateway error (502/503/504: the service behind it is down), or Auth's own
 * "retryable fetch" error. A refusal (4xx, a database error code) is not this.
 */
function dependencyDown(status: number | undefined, name?: string): boolean {
  if (name === 'AuthRetryableFetchError') return true;
  return status === 0 || status === 502 || status === 503 || status === 504;
}

function allowedOrigin(origin: string | null): string | null {
  const list = (Deno.env.get('ADMIN_ORIGINS') ?? '')
    .split(',')
    .map((o) => o.trim())
    .filter((o) => o.length > 0);
  if (list.length === 0) return origin ?? '*';
  return origin !== null && list.includes(origin) ? origin : null;
}

function corsHeaders(origin: string | null): Record<string, string> {
  const allow = allowedOrigin(origin);
  return {
    ...(allow ? { 'Access-Control-Allow-Origin': allow } : {}),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    Vary: 'Origin',
  };
}

interface Invite {
  arena_id: string;
  email: string;
  name: string;
  role: 'staff' | 'owner';
  perms: string[];
}

function parse(body: unknown): Invite | string {
  if (typeof body !== 'object' || body === null) return 'Send a JSON object.';
  const b = body as Record<string, unknown>;
  if ('password' in b) return 'Owners no longer set passwords: the invited person chooses their own.';
  const arena = typeof b.arena_id === 'string' ? b.arena_id : '';
  const email = typeof b.email === 'string' ? b.email.trim().toLowerCase() : '';
  const name = typeof b.name === 'string' ? b.name.trim() : '';
  const perms =
    Array.isArray(b.perms) && b.perms.every((p) => typeof p === 'string') ? b.perms : null;
  const role = b.role === undefined ? 'staff' : b.role;
  if (role !== 'staff' && role !== 'owner') return 'role must be staff or owner.';
  if (!/^[0-9a-f-]{36}$/i.test(arena)) return 'arena_id must be a uuid.';
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return 'Enter a valid email';
  if (name.length < 1 || name.length > MAX_NAME) return 'Enter a name';
  if (perms === null) return 'perms must be a list of permission codes.';
  return { arena_id: arena, email, name, role, perms: perms as string[] };
}

/** The page the invitation link opens (the admin dashboard's /accept-invite). */
function acceptUrl(req: Request, inviteId: string, token: string): string | null {
  const base = Deno.env.get('ADMIN_SITE_URL') ?? req.headers.get('Origin') ?? '';
  let url: URL;
  try {
    url = new URL('/accept-invite', base);
  } catch {
    return null;
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;
  url.searchParams.set('invite', inviteId);
  url.searchParams.set('token', token);
  return url.toString();
}

/** Server-side diagnostics: a stage and error codes only — never tokens, keys or the address. */
function logFailure(stage: string, err: { code?: string; status?: number } | null): void {
  console.error(`staff-admin: ${stage} failed`, { code: err?.code ?? null, status: err?.status ?? null });
}

function randomSecret(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('') + 'Aa1';
}

Deno.serve(async (req) => {
  const cors = corsHeaders(req.headers.get('Origin'));
  const reply = (status: number, body: Record<string, unknown>) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  const fail = (status: number, error: string, message: string) =>
    reply(status, { error, message });

  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (req.method !== 'POST') return fail(405, 'method_not_allowed', 'Use POST.');
  if (allowedOrigin(req.headers.get('Origin')) === null) {
    return fail(403, 'origin_not_allowed', 'This site may not call the function.');
  }

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) {
    console.error('staff-admin: environment incomplete', {
      SUPABASE_URL: !!url,
      SUPABASE_ANON_KEY: !!anonKey,
      SUPABASE_SERVICE_ROLE_KEY: !!serviceKey,
    });
    return fail(500, 'misconfigured', 'Function environment is incomplete.');
  }

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return fail(401, 'unauthorized', 'Sign in first.');

  // Everything the caller decides runs as the caller; the admin client only delivers e-mail.
  const asCaller = createClient(url, anonKey, {
    global: { headers: { Authorization: auth }, fetch: timedFetch },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: who, error: whoErr } = await asCaller.auth.getUser(auth.slice('Bearer '.length));
  if (whoErr && dependencyDown(whoErr.status, whoErr.name)) {
    logFailure('auth.getUser', whoErr);
    return fail(503, 'service_unavailable', 'Sign-in could not be checked right now. Try again.');
  }
  if (whoErr || !who.user) {
    return fail(401, 'unauthorized', 'Your session has expired. Sign in again.');
  }

  let input: Invite | string;
  try {
    input = parse(await req.json());
  } catch {
    input = 'Send a JSON object.';
  }
  if (typeof input === 'string') return fail(400, 'invalid_input', input);

  const {
    data: made,
    error: inviteErr,
    status: inviteStatus,
  } = await asCaller.rpc('invite_member', {
    p_arena: input.arena_id,
    p_email: input.email,
    p_name: input.name,
    p_role: input.role,
    p_perms: input.perms,
  });
  if (inviteErr) {
    if (dependencyDown(inviteStatus)) {
      logFailure('invite_member', { code: inviteErr.code, status: inviteStatus });
      return fail(503, 'service_unavailable', 'The database did not answer. Nothing was sent.');
    }
    if (inviteErr.code === '42501') {
      return fail(403, 'forbidden', inviteErr.hint ?? 'You cannot invite people to this arena.');
    }
    if (inviteErr.code === 'P0001' && /^[a-z_]+$/.test(inviteErr.message)) {
      return fail(400, inviteErr.message, inviteErr.hint ?? inviteErr.message);
    }
    logFailure('invite_member', inviteErr);
    return fail(500, 'server_error', 'Could not create the invitation. Try again.');
  }
  const invite = made as { invite_id: string; token: string; expires_at: string };
  /** Takes the unsent invitation back. If even that fails, say so in the log: it stays pending
   * (listed on the Users page, withdrawable, and replaced by the next invite to the address). */
  const withdraw = async () => {
    const { error, status } = await asCaller.rpc('revoke_invite', {
      p_arena: input.arena_id,
      p_invite: invite.invite_id,
    });
    if (error) logFailure('withdrawing the unsent invite', { code: error.code, status });
  };

  const redirectTo = acceptUrl(req, invite.invite_id, invite.token);
  if (redirectTo === null) {
    console.error('staff-admin: no invitation link base (set ADMIN_SITE_URL or send Origin)');
    await withdraw();
    return fail(500, 'misconfigured', 'Set ADMIN_SITE_URL for the invitation link.');
  }

  const admin = createClient(url, serviceKey, {
    global: { fetch: timedFetch },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const signInLink = () =>
    createClient(url, anonKey, {
      global: { fetch: timedFetch },
      auth: { persistSession: false, autoRefreshToken: false, flowType: 'implicit' },
    }).auth.signInWithOtp({
      email: input.email,
      options: { shouldCreateUser: false, emailRedirectTo: redirectTo },
    });

  const { data: target, error: targetErr } = await admin.rpc('invite_delivery_target', {
    p_email: input.email,
  });
  let sendErr: { code?: string; status?: number } | null = null;
  if (targetErr) {
    logFailure('invite_delivery_target', targetErr);
    sendErr = { code: 'lookup_failed' };
  } else if (target === null) {
    ({ error: sendErr } = await admin.auth.admin.inviteUserByEmail(input.email, {
      redirectTo,
      data: { name: input.name },
    }));
  } else {
    const t = target as { user_id: string; confirmed: boolean };
    if (!t.confirmed) {
      // Whoever signed this address up may not own it: their password must not survive the
      // owner of the address confirming it through our link.
      const { error: scrubErr } = await admin.auth.admin.updateUserById(t.user_id, {
        password: randomSecret(),
      });
      if (scrubErr) {
        sendErr = { code: 'scrub_failed' };
      } else {
        ({ error: sendErr } = await admin.auth.admin.inviteUserByEmail(input.email, {
          redirectTo,
          data: { name: input.name },
        }));
        if (sendErr?.code === 'email_exists') ({ error: sendErr } = await signInLink());
      }
    } else {
      ({ error: sendErr } = await signInLink());
    }
  }
  if (sendErr) {
    logFailure('invitation e-mail', sendErr);
    await withdraw();
    const limited = sendErr.status === 429 || /rate_limit/.test(sendErr.code ?? '');
    return limited
      ? fail(429, 'email_rate_limited', 'Too many e-mails right now. Try again in a while.')
      : fail(502, 'email_failed', 'The invitation e-mail could not be sent. Try again.');
  }
  return reply(200, { status: 'sent', invite_id: invite.invite_id, expires_at: invite.expires_at });
});
