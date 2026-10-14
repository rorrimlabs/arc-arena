-- rate_bands — the band a rate belongs to; only 'standard' is priced
--
-- The pricer looks up every rate at the 'standard' band. Time-of-day prices (happy
-- hours, weekend surcharges) are pricing_rules on top of it; rate.upsert refuses any
-- other band, and rows of the retired 'happy' band are never chosen (rate.delete can
-- still remove them). Seeded with 'standard' by _seed_arena_catalog; _band_id
-- creates it on the first rate.upsert. Not in the sync feed: devices
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

comment on table public.rate_bands is 'Rate bands per arena, identified by code. The pricer only uses standard; time-of-day prices are pricing_rules.';

comment on column public.rate_bands.arena_id is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column public.rate_bands.code is 'Band code, unique per arena; the pricer selects standard. Any other code (e.g. the retired happy) is stored but never chosen.';

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
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."rate_bands"
  to "postgres", "service_role";

revoke all on table "public"."rate_bands" from "anon";

revoke all on table "public"."rate_bands" from "authenticated";

grant select on table "public"."rate_bands" to "authenticated";