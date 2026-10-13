-- staff_invites — invitations to join an arena as staff or co-owner
--
-- The only way a login becomes a member of an arena (besides bootstrap_owner /
-- create_my_arena for an arena's first owner). invite_member stores the invite
-- and the SHA-256 of a random one-time token; the token itself travels only in
-- the link the staff-admin Edge Function e-mails to the invited address. The
-- membership is created when the invited person — signed in with a confirmed
-- login whose e-mail is the invited address — presents that token
-- (accept_invite). Nobody is attached to an arena without accepting, and an
-- owner never sets or learns the invited person's password.
--
-- Server-only: RLS on, no policies and no client grants. Owners list open
-- invites through arena_invites(); the token hash is never returned.
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
  constraint "staff_invites_pkey" primary key (id),
  constraint "staff_invites_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "staff_invites_invited_by_fkey" foreign key (invited_by) references auth.users(id)
    on delete cascade,
  constraint "staff_invites_accepted_by_fkey" foreign key (accepted_by) references auth.users(id)
    on delete set null,
  constraint "staff_invites_role_check" check ((role = ANY (ARRAY['owner'::text, 'staff'::text]))),
  -- Stored normalised (trimmed, lower case) so matching is exact.
  constraint "staff_invites_email_check"
    check (((email = lower(btrim(email))) AND (POSITION(('@'::text) IN (email)) > 1))),
  constraint "staff_invites_name_check"
    check (((length(btrim(name)) >= 1) AND (length(btrim(name)) <= 80))),
  constraint "staff_invites_token_hash_check" check ((length(token_hash) = 32)),
  -- An invite ends exactly one way: accepted or withdrawn.
  constraint "staff_invites_one_outcome" check (((accepted_at IS NULL) OR (revoked_at IS NULL)))
);

-- At most one open invite per address and arena: a new invite replaces it.
create unique index staff_invites_one_open on public.staff_invites using btree (arena_id, email)
  where ((accepted_at IS NULL) AND (revoked_at IS NULL));

create index staff_invites_invited_by_idx on public.staff_invites using btree (invited_by);

create index staff_invites_accepted_by_idx on public.staff_invites using btree (accepted_by);

alter table "public"."staff_invites" enable row level security;

comment on table public.staff_invites is 'Invitations to join an arena (staff or co-owner). Membership is created only when the invited, confirmed login presents the one-time token (accept_invite). Server-only; owners list open invites via arena_invites().';

comment on column public.staff_invites.email is 'Invited address, trimmed and lower case. accept_invite requires the caller''s confirmed auth e-mail to equal it.';

comment on column public.staff_invites.token_hash is 'SHA-256 of the one-time token sent in the invitation link. The token itself is never stored.';

comment on column public.staff_invites.invited_by is 'Who invited. accept_invite re-checks that they still hold the authority the invite needs.';

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_invites"
  to "postgres", "service_role";

revoke all on table "public"."staff_invites" from "anon";

revoke all on table "public"."staff_invites" from "authenticated";
