-- group_charges — itemised bill lines of an ended group session
--
-- Written once by op_group_end. Per station, the group's time is swept into
-- slices priced at that station's combined controller count (per_system); in
-- shared_controller_pool mode one extra line bills the purchased controllers
-- over the whole window. The server re-prices (_pr_group_bill) and refuses the op
-- (price_mismatch) unless the set of lines and the total match exactly.
create table "public"."group_charges" (
  "id"               uuid                     not null default gen_random_uuid(),
  "arena_id"         uuid                     not null,
  "group_id"         uuid                     not null,
  "assignment_id"    uuid,
  "player_number"    integer,
  "charge_index"     integer                  not null,
  "band_code"        text                     not null,
  "activity_code"    text                     not null,
  "resource_id"      uuid,
  "controller_count" integer,
  "segment_start"    timestamp with time zone not null,
  "segment_end"      timestamp with time zone not null,
  "played_minutes"   integer                  not null,
  "billed_minutes"   integer                  not null,
  "unit_minutes"     integer                  not null,
  "unit_price_paise" bigint                   not null,
  "amount_paise"     bigint                   not null,
  "created_at"       timestamp with time zone not null default now(),
  "sync_xid"         xid8                     not null default pg_current_xact_id(),
  constraint "group_charges_arena_id_activity_code_fkey" foreign key (arena_id, activity_code)
    references public.activities(arena_id, code),
  constraint "group_charges_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "group_charges_assignment_id_fkey" foreign key (assignment_id)
    references public.group_assignments(id),
  constraint "group_charges_band_code_check"
    check ((band_code = ANY (ARRAY['standard'::text, 'happy'::text]))),
  constraint "group_charges_pkey" primary key (id),
  constraint "group_charges_group_id_fkey" foreign key (group_id)
    references public.group_sessions(id) on delete cascade,
  constraint "group_charges_resource_id_fkey" foreign key (resource_id)
    references public.resources(id)
);

comment on table public.group_charges is 'Itemised bill lines of an ended group session, verified against the server''s own re-pricing of the group.';

comment on column public.group_charges.arena_id is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column public.group_charges.assignment_id is 'Assignment billed by this line when exactly one player was on the station for it; null for shared or pooled lines.';

comment on column public.group_charges.player_number is 'That player''s number when the line belongs to one player; otherwise null.';

comment on column public.group_charges.charge_index is '0-based ordinal of this line within the group''s bill.';

comment on column public.group_charges.band_code is 'Price band: standard or happy (happy hour).';

comment on column public.group_charges.resource_id is 'Station billed; null for the pooled-controller line.';

comment on column public.group_charges.controller_count is 'Controller count the rate was looked up for (combined per station, or the purchased count for the pooled line).';

comment on column public.group_charges.segment_start is 'Start of the billed interval (UTC).';

comment on column public.group_charges.segment_end is 'End of the billed interval (UTC); can extend past the actual end when the minimum charge applies.';

comment on column public.group_charges.played_minutes is 'Whole minutes actually played inside this interval.';

comment on column public.group_charges.billed_minutes is 'Minutes charged after billing-unit / block rounding (or units x unit_minutes for unit-priced activities).';

comment on column public.group_charges.unit_minutes is 'Length in minutes of the rate''s pricing unit that unit_price_paise buys.';

comment on column public.group_charges.unit_price_paise is 'Rate price per unit_minutes, in integer paise, from the group''s pricing_snapshot.';

comment on column public.group_charges.amount_paise is 'Line amount in integer paise before bill-level cash rounding; the group total is group_sessions.billed_amount_paise.';

comment on column public.group_charges.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

alter table "public"."group_charges"
  enable row level security;

create index ix_group_charges_group on public.group_charges using btree (group_id, charge_index);

create index ix_group_charges_sync on public.group_charges using btree (arena_id, sync_xid);

-- Foreign-key index (joins and cascading deletes).
create index ix_group_charges_assignment_id on public.group_charges using btree (assignment_id);

create index ix_group_charges_resource_id on public.group_charges using btree (resource_id);

create index ix_group_charges_activity on public.group_charges using btree (arena_id, activity_code);

-- Change feed: stamp sync_xid on every write; record deletes as tombstones.
create trigger t_group_charges_sync
  before insert or update on public.group_charges
  for each row
  execute function public.sync_stamp();

create trigger t_group_charges_tomb
  after delete on public.group_charges
  for each row
  execute function public.sync_record_delete();

-- Referenced assignment, group and station must belong to this row's arena (cross_arena_reference, 0016).
create trigger t_same_arena
  before insert or update on public.group_charges
  for each row
  execute function
    public._assert_same_arena('assignment_id', 'group_assignments', 'group_id', 'group_sessions',
    'resource_id', 'resources');

-- Members read their arenas' rows. No write policy: clients change data only through sync_push.
create policy "p_sel_group_charges" on "public"."group_charges"
  for select
  to authenticated
  using ((arena_id in ( select public.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."group_charges"
  to "postgres", "service_role";

revoke all on table "public"."group_charges" from "anon";

revoke all on table "public"."group_charges" from "authenticated";

grant select on table "public"."group_charges" to "authenticated";