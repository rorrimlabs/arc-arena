-- rate_bands — time bands a rate can apply in (standard, happy hour)
--
-- The pricer labels each stretch of play 'happy' (inside the day's happy-hour
-- window, for happy-hour-eligible activities) or 'standard' and looks up the rate
-- for that band code. Seeded with 'standard' and 'happy' by _seed_arena_catalog;
-- _band_id creates a missing band on rate.upsert. Not in the sync feed: devices
-- see band codes through sync_v_rates.band.
create table "public"."rate_bands" (
  "id"         uuid                     not null default gen_random_uuid(),
  "arena_id"   uuid                     not null,
  "code"       text                     not null,
  "name"       text                     not null,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "sync_xid"   xid8                     not null default pg_current_xact_id(),
  -- Rates and the pricing snapshot refer to bands by code.
  constraint "rate_bands_arena_id_code_key" unique (arena_id, code),
  constraint "rate_bands_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "rate_bands_pkey" primary key (id)
);

comment on table public.rate_bands is 'Pricing time bands per arena, identified by code. The server pricer uses the codes standard and happy.';

comment on column public.rate_bands.arena_id is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column public.rate_bands.code is 'Band code, unique per arena; the pricer selects standard or happy. Any other code is stored but never chosen.';

comment on column public.rate_bands.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp). The table is not in the sync_pull feed; devices see band codes through sync_v_rates.';

alter table "public"."rate_bands"
  enable row level security;

create index ix_rate_bands_sync on public.rate_bands using btree (arena_id, sync_xid);

create trigger t_rate_bands_sync
  before insert or update on public.rate_bands
  for each row
  execute function public.sync_stamp();

create trigger t_rate_bands_tomb
  after delete on public.rate_bands
  for each row
  execute function public.sync_record_delete();

create trigger t_rate_bands_updated
  before update on public.rate_bands
  for each row
  execute function public.set_updated_at();

create policy "p_sel_rate_bands" on "public"."rate_bands"
  for select
  to authenticated
  using ((arena_id in ( select public.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."rate_bands"
  to "postgres", "service_role";

revoke all on table "public"."rate_bands" from "anon";

revoke all on table "public"."rate_bands" from "authenticated";

grant select on table "public"."rate_bands" to "authenticated";