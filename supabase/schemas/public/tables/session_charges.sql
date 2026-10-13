-- session_charges — itemised bill lines of an ended single session
--
-- One row per priced band piece (standard / happy hour) of each segment, written
-- once by op_session_end. The server re-prices the session from its segments and
-- pricing_snapshot (_pr_session_bill) and refuses the op (price_mismatch) unless
-- the set of charge rows and the total match exactly. Immutable afterwards.
create table "public"."session_charges" (
  "id"               uuid                     not null default gen_random_uuid(),
  "arena_id"         uuid                     not null,
  "session_id"       uuid                     not null,
  "segment_index"    integer                  not null,
  "band_code"        text                     not null,
  "activity_code"    text                     not null,
  "controller_count" integer,
  "segment_start"    timestamp with time zone not null,
  "segment_end"      timestamp with time zone not null,
  "played_minutes"   integer                  not null,
  "billed_minutes"   integer                  not null,
  "unit_minutes"     integer                  not null,
  "unit_price_paise" bigint                   not null,
  "amount_paise"     bigint                   not null,
  "created_at"       timestamp with time zone not null default now(),
  "segment_id"       uuid,
  "resource_id"      uuid,
  "sync_xid"         xid8                     not null default pg_current_xact_id(),
  constraint "session_charges_arena_id_activity_code_fkey" foreign key (arena_id, activity_code)
    references public.activities(arena_id, code),
  constraint "session_charges_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "session_charges_band_code_check"
    check ((band_code = ANY (ARRAY['standard'::text, 'happy'::text]))),
  constraint "session_charges_pkey" primary key (id),
  constraint "session_charges_resource_id_fkey" foreign key (resource_id)
    references public.resources(id),
  constraint "session_charges_session_id_segment_index_key" unique (session_id, segment_index),
  constraint "session_charges_segment_id_fkey" foreign key (segment_id)
    references public.session_segments(id),
  constraint "session_charges_session_id_fkey" foreign key (session_id)
    references public.sessions(id) on delete cascade
);

comment on table public.session_charges is 'Itemised bill lines of an ended single session: one row per price band piece of each segment, verified against the server''s own re-pricing.';

comment on column public.session_charges.arena_id is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column public.session_charges.segment_index is '0-based ordinal of this charge line within the session''s bill (one segment can yield several lines); not session_segments.idx.';

comment on column public.session_charges.band_code is 'Price band: standard or happy (happy hour).';

comment on column public.session_charges.controller_count is 'Controller count the rate was looked up for (copied from the segment).';

comment on column public.session_charges.segment_start is 'Start of the billed band interval (UTC).';

comment on column public.session_charges.segment_end is 'End of the billed band interval (UTC); can extend past the actual end when the minimum charge applies.';

comment on column public.session_charges.played_minutes is 'Whole minutes actually played inside this interval.';

comment on column public.session_charges.billed_minutes is 'Minutes charged after billing-unit / block rounding (or units x unit_minutes for unit-priced activities).';

comment on column public.session_charges.unit_minutes is 'Length in minutes of the rate''s pricing unit that unit_price_paise buys.';

comment on column public.session_charges.unit_price_paise is 'Rate price per unit_minutes, in integer paise, from the session''s pricing_snapshot.';

comment on column public.session_charges.amount_paise is 'Line amount in integer paise before bill-level cash rounding; the session total is sessions.billed_amount_paise.';

comment on column public.session_charges.segment_id is 'Segment this line was priced from.';

comment on column public.session_charges.resource_id is 'Station of that segment.';

comment on column public.session_charges.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

alter table "public"."session_charges"
  enable row level security;

create index ix_charges_session on public.session_charges using btree (session_id);

create index ix_session_charges_sync on public.session_charges using btree (arena_id, sync_xid);

-- Foreign-key index (joins and cascading deletes).
create index ix_session_charges_resource_id on public.session_charges using btree (resource_id);

create index ix_session_charges_segment_id on public.session_charges using btree (segment_id);

create index ix_session_charges_activity on public.session_charges using btree (arena_id, activity_code);

-- Referenced station, segment and session must belong to this row's arena (cross_arena_reference, 0016).
create trigger t_same_arena
  before insert or update on public.session_charges
  for each row
  execute function
    public._assert_same_arena('resource_id', 'resources', 'segment_id', 'session_segments',
    'session_id', 'sessions');

-- Change feed: stamp sync_xid on every write; record deletes as tombstones.
create trigger t_session_charges_sync
  before insert or update on public.session_charges
  for each row
  execute function public.sync_stamp();

create trigger t_session_charges_tomb
  after delete on public.session_charges
  for each row
  execute function public.sync_record_delete();

-- Readable by an active member holding bill, or owner level (money/reports): bill lines are financial records.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_session_charges" on "public"."session_charges"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids_with(ARRAY['bill'::text, 'money'::text, 'reports'::text]) as app_arena_ids_with)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."session_charges"
  to "postgres", "service_role";

revoke all on table "public"."session_charges" from "anon";

revoke all on table "public"."session_charges" from "authenticated";

grant select on table "public"."session_charges" to "authenticated";