-- staff_terms — the venue's terms and conditions for staff, one row per published version
--
-- Append-only, written by op_terms_publish (terms.publish, owner level): a change is a new
-- version, numbered 1, 2, 3… per arena; the highest is in force. Every active member reads
-- them (the floor app shows the latest until it is accepted: staff_terms_acceptances). Not in
-- sync_pull: the apps read them online.
create table "public"."staff_terms" (
  "id"           uuid                     not null default gen_random_uuid(),
  "arena_id"     uuid                     not null,
  "version"      integer                  not null,
  "title"        text                     not null,
  "body"         text                     not null,
  "published_by" uuid,
  "published_at" timestamp with time zone not null default now(),
  constraint "staff_terms_arena_id_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "staff_terms_arena_id_version_key" unique (arena_id, version),
  constraint "staff_terms_body_check" check (((btrim(body) <> ''::text) AND (char_length(body) <= 50000))),
  constraint "staff_terms_pkey" primary key (id),
  constraint "staff_terms_published_by_fkey" foreign key (published_by) references auth.users(id) on delete set null,
  constraint "staff_terms_title_check" check (((btrim(title) <> ''::text) AND (char_length(title) <= 120))),
  constraint "staff_terms_version_check" check ((version >= 1))
);

comment on table public.staff_terms is 'Append-only versions of a venue''s terms and conditions for staff; the highest version is in force and every member must accept it.';

comment on column public.staff_terms.version is 'Per-arena version number, 1 for the first; a new version asks everyone to accept again.';

comment on column public.staff_terms.body is 'The full text (plain text, paragraphs separated by blank lines), at most 50,000 characters.';

comment on column public.staff_terms.published_at is 'Server time the version was published.';

alter table "public"."staff_terms"
  enable row level security;

create index ix_staff_terms_published_by on public.staff_terms using btree (published_by);

-- Every active member reads the terms they are asked to accept.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_staff_terms" on "public"."staff_terms"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_terms"
  to "postgres", "service_role";

revoke all on table "public"."staff_terms" from "anon";

revoke all on table "public"."staff_terms" from "authenticated";

grant select on table "public"."staff_terms" to "authenticated";
