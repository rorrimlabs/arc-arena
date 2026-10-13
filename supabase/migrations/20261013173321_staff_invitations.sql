set local check_function_bodies = off;

drop function "private"."add_member_by_email"(uuid, text, text, text, text[]);

drop function "private"."add_staff_by_email"(uuid, text, text, text[]);

drop function "public"."add_member_by_email"(uuid, text, text, text, text[]);

drop function "public"."add_staff_by_email"(uuid, text, text, text[]);

create table "public"."staff_invites" (
  "id"          uuid                     not null default gen_random_uuid(),
  "arena_id"    uuid                     not null,
  "email"       text                     not null,
  "name"        text                     not null,
  "role"        text                     not null,
  "perms"       text[]                   not null default '{}'::text[],
  "token_hash"  bytea                    not null,
  "invited_by"  uuid                     not null,
  "created_at"  timestamp with time zone not null default statement_timestamp(),
  "expires_at"  timestamp with time zone not null,
  "accepted_at" timestamp with time zone,
  "accepted_by" uuid,
  "revoked_at"  timestamp with time zone,
  constraint "staff_invites_email_check"
    check (((email = lower(btrim(email))) AND (POSITION(('@'::text) IN (email)) > 1))),
  constraint "staff_invites_name_check"
    check (((length(btrim(name)) >= 1) AND (length(btrim(name)) <= 80))),
  constraint "staff_invites_one_outcome" check (((accepted_at IS NULL) OR (revoked_at IS NULL))),
  constraint "staff_invites_pkey" primary key (id),
  constraint "staff_invites_role_check" check ((role = ANY (ARRAY['owner'::text, 'staff'::text]))),
  constraint "staff_invites_token_hash_check" check ((length(token_hash) = 32))
);

alter table "public"."staff_invites"
  enable row level security;

revoke all on table "public"."staff_invites" from "anon", "authenticated";

create or replace function private.accept_invite (
  p_invite uuid,
  p_token  text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_inv       staff_invites%rowtype;
  v_email     text;
  v_confirmed timestamptz;
  v_allowed   boolean;
begin
  if auth.uid() is null then
    raise exception 'forbidden' using errcode = '42501', hint = 'sign in first';
  end if;
  select * into v_inv from staff_invites where id = p_invite for update;
  if not found or p_token is null
     or extensions.digest(p_token, 'sha256') <> v_inv.token_hash then
    raise exception 'invite_invalid' using hint = 'this invitation link is not valid';
  end if;
  if v_inv.accepted_at is not null then
    raise exception 'invite_used' using hint = 'this invitation was already accepted';
  end if;
  if v_inv.revoked_at is not null then
    raise exception 'invite_revoked' using hint = 'this invitation was withdrawn';
  end if;
  if v_inv.expires_at <= statement_timestamp() then
    raise exception 'invite_expired' using hint = 'ask for a new invitation';
  end if;
  select lower(email), email_confirmed_at into v_email, v_confirmed
    from auth.users where id = auth.uid();
  if v_email is distinct from v_inv.email then
    raise exception 'invite_wrong_account' using errcode = '42501',
      hint = 'sign in with the e-mail address the invitation was sent to';
  end if;
  if v_confirmed is null then
    raise exception 'email_not_confirmed' using hint = 'confirm your e-mail address first';
  end if;
  -- The inviter's authority is re-checked now: an invite from someone who has
  -- since lost Settings (or ownership) must not still work.
  if v_inv.role = 'owner' then
    v_allowed := exists (select 1 from staff_profiles where arena_id = v_inv.arena_id
                           and user_id = v_inv.invited_by and active and role = 'owner');
  else
    v_allowed := exists (select 1 from staff_profiles where arena_id = v_inv.arena_id
                           and user_id = v_inv.invited_by and active
                           and (role = 'owner' or 'settings' = any(perms))
                           and (not (v_inv.perms && array['money', 'reports'])
                                or role = 'owner' or perms && array['money', 'reports']));
  end if;
  if not v_allowed then
    raise exception 'invite_invalid'
      using hint = 'the person who invited you can no longer add members';
  end if;
  if exists (select 1 from staff_profiles where arena_id = v_inv.arena_id
              and user_id = auth.uid() and role = 'owner') then
    raise exception 'owner_profile' using hint = 'you are already an owner of this arena';
  end if;
  insert into staff_profiles (arena_id, user_id, name, role, perms, active)
    values (v_inv.arena_id, auth.uid(), v_inv.name, v_inv.role, v_inv.perms, true)
  on conflict (user_id, arena_id) do update
    set name = excluded.name, role = excluded.role, perms = excluded.perms, active = true,
        updated_at = statement_timestamp();
  perform _assert_settings_holder(v_inv.arena_id);
  update staff_invites set accepted_at = statement_timestamp(), accepted_by = auth.uid()
   where id = v_inv.id;
  return jsonb_build_object(
    'arena_id', v_inv.arena_id,
    'arena_name', (select name from arenas where id = v_inv.arena_id),
    'role', v_inv.role);
end;
$function$;

create or replace function private.arena_invites (
  p_arena uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can list invites';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'invite_id', i.id, 'email', i.email, 'name', i.name, 'role', i.role,
        'perms', to_jsonb(i.perms), 'created_at', i.created_at, 'expires_at', i.expires_at,
        'expired', i.expires_at <= statement_timestamp(),
        'invited_by_name', s.name) order by i.created_at desc)
      from staff_invites i
      left join staff_profiles s on s.arena_id = i.arena_id and s.user_id = i.invited_by
     where i.arena_id = p_arena and i.accepted_at is null and i.revoked_at is null
  ), '[]'::jsonb);
end;
$function$;

create or replace function private.invite_member (
  p_arena uuid,
  p_email text,
  p_name  text,
  p_role  text,
  p_perms text[]
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_email   text := lower(btrim(coalesce(p_email, '')));
  v_name    text := btrim(coalesce(p_name, ''));
  v_owner   boolean;
  v_perms   text[];
  v_token   text;
  v_id      uuid;
  v_expires timestamptz := statement_timestamp() + interval '7 days';
begin
  if auth.uid() is null then
    raise exception 'forbidden' using errcode = '42501', hint = 'sign in first';
  end if;
  if p_role is null or p_role not in ('staff', 'owner') then
    raise exception 'invalid_role' using hint = 'role must be staff or owner';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid_email' using hint = 'enter a valid e-mail address';
  end if;
  if length(v_name) < 1 or length(v_name) > 80 then
    raise exception 'invalid_name' using hint = 'the name must be 1 to 80 characters';
  end if;
  v_owner := exists (select 1 from staff_profiles where arena_id = p_arena
                       and user_id = auth.uid() and active and role = 'owner');
  if p_role = 'owner' then
    if not v_owner then
      raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can invite an owner';
    end if;
    v_perms := _known_perms();
  else
    perform _need(p_arena, 'settings');
    perform _assert_known_perms(p_perms);
    v_perms := coalesce(p_perms, '{}');
    if v_perms && array['money', 'reports'] and not private.app_is_owner(p_arena) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'only an owner can grant money or reports';
    end if;
  end if;
  if exists (select 1 from auth.users where id = auth.uid() and lower(email) = v_email) then
    raise exception 'forbidden' using errcode = '42501', hint = 'you cannot invite yourself';
  end if;
  if not v_owner and exists (select 1 from staff_invites where arena_id = p_arena
       and email = v_email and role = 'owner' and accepted_at is null and revoked_at is null) then
    raise exception 'forbidden' using errcode = '42501',
      hint = 'an owner invited this address; only an owner can replace that invite';
  end if;
  update staff_invites set revoked_at = statement_timestamp()
   where arena_id = p_arena and email = v_email and accepted_at is null and revoked_at is null;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into staff_invites (arena_id, email, name, role, perms, token_hash, invited_by, expires_at)
    values (p_arena, v_email, v_name, p_role, v_perms,
            extensions.digest(v_token, 'sha256'), auth.uid(), v_expires)
    returning id into v_id;
  return jsonb_build_object('invite_id', v_id, 'token', v_token, 'expires_at', v_expires);
end;
$function$;

create or replace function private.revoke_invite (
  p_arena  uuid,
  p_invite uuid
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_role text;
begin
  perform _need(p_arena, 'settings');
  select role into v_role from staff_invites
   where id = p_invite and arena_id = p_arena and accepted_at is null and revoked_at is null
     for update;
  if not found then
    raise exception 'not_found' using hint = 'invite';
  end if;
  if v_role = 'owner' and not exists (select 1 from staff_profiles where arena_id = p_arena
       and user_id = auth.uid() and active and role = 'owner') then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can withdraw an owner invite';
  end if;
  update staff_invites set revoked_at = statement_timestamp() where id = p_invite;
end;
$function$;

create or replace function public.accept_invite (
  p_invite uuid,
  p_token  text
)
  returns jsonb
  language sql
  set search_path to ''
  AS $function$
  select private.accept_invite(p_invite, p_token);
$function$;

revoke all on function "public"."accept_invite"(uuid, text) from public, "anon";

create or replace function public.arena_invites (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_invites(p_arena);
$function$;

revoke all on function "public"."arena_invites"(uuid) from public, "anon";

create or replace function public.invite_delivery_target (
  p_email text
)
  returns jsonb
  language sql
  stable
  security definer
  set search_path to ''
  AS $function$
  select jsonb_build_object('user_id', u.id, 'confirmed', u.email_confirmed_at is not null)
    from auth.users u
   where lower(u.email) = lower(btrim(p_email))
   limit 1;
$function$;

revoke all on function "public"."invite_delivery_target"(text) from public, "anon", "authenticated";

create or replace function public.invite_member (
  p_arena uuid,
  p_email text,
  p_name  text,
  p_role  text,
  p_perms text[]
)
  returns jsonb
  language sql
  set search_path to ''
  AS $function$
  select private.invite_member(p_arena, p_email, p_name, p_role, p_perms);
$function$;

revoke all on function "public"."invite_member"(uuid, text, text, text, text[]) from public, "anon";

create or replace function public.revoke_invite (
  p_arena  uuid,
  p_invite uuid
)
  returns void
  language sql
  set search_path to ''
  AS $function$
  select private.revoke_invite(p_arena, p_invite);
$function$;

revoke all on function "public"."revoke_invite"(uuid, uuid) from public, "anon";

alter table "public"."staff_invites"
  add constraint "staff_invites_accepted_by_fkey" foreign key (accepted_by)
    references auth.users(id) on delete set null;

alter table "public"."staff_invites"
  add constraint "staff_invites_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."staff_invites"
  add constraint "staff_invites_invited_by_fkey" foreign key (invited_by) references auth.users(id)
    on delete cascade;

create index staff_invites_accepted_by_idx on public.staff_invites using btree (accepted_by);

create index staff_invites_invited_by_idx on public.staff_invites using btree (invited_by);

create unique index staff_invites_one_open on public.staff_invites using btree (arena_id, email)
  where ((accepted_at is null) AND (revoked_at is null));

comment on column "public"."staff_invites"."email" is 'Invited address, trimmed and lower case. accept_invite requires the caller''s confirmed auth e-mail to equal it.';

comment on column "public"."staff_invites"."invited_by" is 'Who invited. accept_invite re-checks that they still hold the authority the invite needs.';

comment on column "public"."staff_invites"."token_hash" is 'SHA-256 of the one-time token sent in the invitation link. The token itself is never stored.';

comment on function "private"."accept_invite"(uuid, text) is 'The invited, confirmed login (auth e-mail = invited address) presents the one-time token and joins the invite''s arena with its role and permissions. Single use; refuses wrong, used, withdrawn or expired invites, the wrong account, and invites whose inviter lost the authority.';

comment on function "private"."arena_invites"(uuid) is 'Owner level: the arena''s open invitations (not accepted or withdrawn), newest first, without their token hashes.';

comment on function "private"."invite_member"(uuid, text, text, text, text[]) is
  'Create a one-time invitation to the arena (staff: caller holds Settings, money/reports only from owner level; owner: caller is an owner). Returns {invite_id, token, expires_at}; only the token''s SHA-256 is stored. Never reads or changes the invited address''s login.';

comment on function "private"."revoke_invite"(uuid, uuid) is 'Withdraw an open invitation of the arena (caller holds Settings; owner invites need an owner). Its link stops working.';

comment on function "public"."accept_invite"(uuid, text) is 'Client API: the invited, confirmed login presents its one-time token and joins the arena. Returns {arena_id, arena_name, role}.';

comment on function "public"."arena_invites"(uuid) is 'Client API (owner level): the arena''s open invitations, newest first.';

comment on function "public"."invite_delivery_target"(text) is 'Server-only (service_role, staff-admin Edge Function): null when no login uses the address, else {user_id, confirmed}. Not executable by clients.';

comment on function "public"."invite_member"(uuid, text, text, text, text[]) is
  'Client API (Settings holder; owner invites need an owner): create a one-time invitation to the arena. Returns {invite_id, token, expires_at}.';

comment on function "public"."revoke_invite"(uuid, uuid) is 'Client API (Settings holder; owner invites need an owner): withdraw an open invitation.';

comment on table "public"."staff_invites" is 'Invitations to join an arena (staff or co-owner). Membership is created only when the invited, confirmed login presents the one-time token (accept_invite). Server-only; owners list open invites via arena_invites().';

revoke all on function "private"."accept_invite"(uuid, text) from public;

grant execute on function "private"."accept_invite"(uuid, text) to "authenticated";

revoke all on function "private"."accept_invite"(uuid, text) from "postgres";

grant execute on function "private"."accept_invite"(uuid, text) to "postgres";

grant execute on function "private"."accept_invite"(uuid, text) to "service_role";

revoke all on function "private"."arena_invites"(uuid) from public;

grant execute on function "private"."arena_invites"(uuid) to "authenticated";

revoke all on function "private"."arena_invites"(uuid) from "postgres";

grant execute on function "private"."arena_invites"(uuid) to "postgres";

grant execute on function "private"."arena_invites"(uuid) to "service_role";

revoke all on function "private"."invite_member"(uuid, text, text, text, text[]) from public;

grant execute
  on function "private"."invite_member"(uuid, text, text, text, text[])
  to "authenticated";

revoke all on function "private"."invite_member"(uuid, text, text, text, text[]) from "postgres";

grant execute on function "private"."invite_member"(uuid, text, text, text, text[]) to "postgres";

grant execute
  on function "private"."invite_member"(uuid, text, text, text, text[])
  to "service_role";

revoke all on function "private"."revoke_invite"(uuid, uuid) from public;

grant execute on function "private"."revoke_invite"(uuid, uuid) to "authenticated";

revoke all on function "private"."revoke_invite"(uuid, uuid) from "postgres";

grant execute on function "private"."revoke_invite"(uuid, uuid) to "postgres";

grant execute on function "private"."revoke_invite"(uuid, uuid) to "service_role";

grant execute on function "public"."accept_invite"(uuid, text) to "authenticated";

revoke all on function "public"."accept_invite"(uuid, text) from "postgres";

grant execute on function "public"."accept_invite"(uuid, text) to "postgres";

grant execute on function "public"."accept_invite"(uuid, text) to "service_role";

grant execute on function "public"."arena_invites"(uuid) to "authenticated";

revoke all on function "public"."arena_invites"(uuid) from "postgres";

grant execute on function "public"."arena_invites"(uuid) to "postgres";

grant execute on function "public"."arena_invites"(uuid) to "service_role";

revoke all on function "public"."invite_delivery_target"(text) from "postgres";

grant execute on function "public"."invite_delivery_target"(text) to "postgres";

grant execute on function "public"."invite_delivery_target"(text) to "service_role";

grant execute
  on function "public"."invite_member"(uuid, text, text, text, text[])
  to "authenticated";

revoke all on function "public"."invite_member"(uuid, text, text, text, text[]) from "postgres";

grant execute on function "public"."invite_member"(uuid, text, text, text, text[]) to "postgres";

grant execute on function "public"."invite_member"(uuid, text, text, text, text[]) to "service_role";

grant execute on function "public"."revoke_invite"(uuid, uuid) to "authenticated";

revoke all on function "public"."revoke_invite"(uuid, uuid) from "postgres";

grant execute on function "public"."revoke_invite"(uuid, uuid) to "postgres";

grant execute on function "public"."revoke_invite"(uuid, uuid) to "service_role";

revoke all on table "public"."staff_invites" from "postgres";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_invites"
  to "postgres";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_invites"
  to "service_role";
