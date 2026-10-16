-- staff_terms_acceptances — who accepted which version of the staff terms, and when
--
-- Append-only, written by op_terms_accept (terms.accept): a member accepts the version in
-- force for themselves, once. accepted_at is server time; device_at is the phone's clock,
-- kept as evidence only. Read by the person and by owner level.
create table "public"."staff_terms_acceptances" (
  "id"          uuid                     not null default gen_random_uuid(),
  "arena_id"    uuid                     not null,
  "staff_id"    uuid                     not null,
  "terms_id"    uuid                     not null,
  "accepted_at" timestamp with time zone not null default now(),
  "device_at"   timestamp with time zone,
  constraint "staff_terms_acceptances_arena_id_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "staff_terms_acceptances_pkey" primary key (id),
  constraint "staff_terms_acceptances_staff_id_fkey" foreign key (staff_id) references public.staff_profiles(id) on delete cascade,
  constraint "staff_terms_acceptances_staff_id_terms_id_key" unique (staff_id, terms_id),
  constraint "staff_terms_acceptances_terms_id_fkey" foreign key (terms_id) references public.staff_terms(id) on delete cascade
);

comment on table public.staff_terms_acceptances is 'Append-only record of each member accepting a version of the staff terms (server time, with the device clock as evidence).';

comment on column public.staff_terms_acceptances.accepted_at is 'Server time of the acceptance.';

comment on column public.staff_terms_acceptances.device_at is 'The device clock at acceptance; evidence only, never used for rules.';

alter table "public"."staff_terms_acceptances"
  enable row level security;

create index ix_staff_terms_acceptances_arena on public.staff_terms_acceptances using btree (arena_id);

create index ix_staff_terms_acceptances_terms on public.staff_terms_acceptances using btree (terms_id);

create trigger t_same_arena
  before insert or update on public.staff_terms_acceptances
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles');

-- A member reads their own; owner level reads everyone's.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_staff_terms_acceptances" on "public"."staff_terms_acceptances"
  for select
  to authenticated
  using (((staff_id in ( select private.app_my_staff_ids() as app_my_staff_ids)) or (arena_id in ( select private.app_arena_ids_with(ARRAY['money'::text, 'reports'::text]) as app_arena_ids_with))));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_terms_acceptances"
  to "postgres", "service_role";

revoke all on table "public"."staff_terms_acceptances" from "anon";

revoke all on table "public"."staff_terms_acceptances" from "authenticated";

grant select on table "public"."staff_terms_acceptances" to "authenticated";
