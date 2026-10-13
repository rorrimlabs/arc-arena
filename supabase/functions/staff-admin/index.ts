// staff-admin — an arena owner creates a user's login (staff or co-owner) from the admin dashboard.
//
// POST { arena_id, email, name, password, role: 'staff' | 'owner', perms } with the owner's
// session as the Bearer token.
//
// 1. Verifies the caller's session and that they are owner level in arena_id (app_is_owner,
//    called as the caller, so RLS and the database's own rules decide).
// 2. Creates the login with the service-role key: already confirmed, with the starting password
//    the owner chose. If a login with that e-mail already exists it is left untouched (its
//    password is never changed: the person may belong to other arenas) and only linked.
// 3. Links it to the arena with add_member_by_email, again called AS THE OWNER, so every
//    database check (owner level; only an owner adds an owner; known perms; settings holder)
//    still applies.
//    If linking fails, a login created in step 2 is deleted again.
//
// The service-role key lives only in this function's environment; it never reaches a browser
// or the app. Responses: 200 { user_id, created }, or 4xx/5xx { error: <code>, message }.
import { createClient } from 'npm:@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const MIN_PASSWORD = 10;
const MAX_NAME = 80;

function reply(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

const fail = (status: number, error: string, message: string) => reply(status, { error, message });

interface CreateStaff {
  arena_id: string;
  email: string;
  name: string;
  password: string;
  role: 'staff' | 'owner';
  perms: string[];
}

function parse(body: unknown): CreateStaff | string {
  if (typeof body !== 'object' || body === null) return 'Send a JSON object.';
  const b = body as Record<string, unknown>;
  const arena = typeof b.arena_id === 'string' ? b.arena_id : '';
  const email = typeof b.email === 'string' ? b.email.trim().toLowerCase() : '';
  const name = typeof b.name === 'string' ? b.name.trim() : '';
  const password = typeof b.password === 'string' ? b.password : '';
  const perms = Array.isArray(b.perms) && b.perms.every((p) => typeof p === 'string') ? b.perms : null;
  const role = b.role === undefined ? 'staff' : b.role;
  if (role !== 'staff' && role !== 'owner') return 'role must be staff or owner.';
  if (!/^[0-9a-f-]{36}$/i.test(arena)) return 'arena_id must be a uuid.';
  if (!/^\S+@\S+\.\S+$/.test(email)) return 'Enter a valid email';
  if (name.length < 2 || name.length > MAX_NAME) return 'Enter a name';
  if (password.length < MIN_PASSWORD || !/[A-Za-z]/.test(password) || !/[0-9]/.test(password)) {
    return `Use at least ${MIN_PASSWORD} characters with letters and digits`;
  }
  if (perms === null) return 'perms must be a list of permission codes.';
  return { arena_id: arena, email, name, password, role, perms: perms as string[] };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return fail(405, 'method_not_allowed', 'Use POST.');

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) return fail(500, 'misconfigured', 'Function environment is incomplete.');

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return fail(401, 'unauthorized', 'Sign in first.');

  // Everything the owner does runs as the owner; only createUser/deleteUser use the admin client.
  const asOwner = createClient(url, anonKey, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: who, error: whoErr } = await asOwner.auth.getUser(auth.slice('Bearer '.length));
  if (whoErr || !who.user) return fail(401, 'unauthorized', 'Your session has expired. Sign in again.');

  let input: CreateStaff | string;
  try {
    input = parse(await req.json());
  } catch {
    input = 'Send a JSON object.';
  }
  if (typeof input === 'string') return fail(400, 'invalid_input', input);

  const { data: isOwner, error: ownerErr } = await asOwner.rpc('app_is_owner', { p_arena: input.arena_id });
  if (ownerErr) return fail(500, 'server_error', ownerErr.message);
  if (isOwner !== true) return fail(403, 'forbidden', 'Only an owner of this arena can add users.');

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  let createdId: string | null = null;
  const { data: made, error: makeErr } = await admin.auth.admin.createUser({
    email: input.email,
    password: input.password,
    email_confirm: true,
    user_metadata: { name: input.name },
  });
  if (makeErr) {
    // An existing login is linked as it is; anything else is a real failure.
    if (makeErr.code !== 'email_exists' && makeErr.code !== 'user_already_exists') {
      return fail(400, makeErr.code ?? 'create_failed', makeErr.message);
    }
  } else {
    createdId = made.user.id;
  }

  const { data: userId, error: linkErr } = await asOwner.rpc('add_member_by_email', {
    p_arena: input.arena_id,
    p_email: input.email,
    p_name: input.name,
    p_role: input.role,
    p_perms: input.perms,
  });
  if (linkErr) {
    if (createdId) await admin.auth.admin.deleteUser(createdId);
    const status = linkErr.code === '42501' ? 403 : 400;
    return fail(status, linkErr.message, linkErr.hint ?? linkErr.message);
  }
  return reply(200, { user_id: userId, created: createdId !== null });
});
