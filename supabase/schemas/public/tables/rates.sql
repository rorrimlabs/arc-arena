-- rates — one price on a rate card: activity x band x controller count
--
-- price_paise is charged per unit_minutes of play for that activity in that band
-- (always standard), optionally for a specific controller count. Written by
-- op_rate_upsert / op_rate_delete (rate.upsert / rate.delete) on the active card
-- (_active_card; bands are created on demand by _band_id); seeded by
-- _seed_arena_catalog. Rates are part of the pricing snapshot: changing one
-- retires the previous price list into pricing_catalog_history. Synced through
-- sync_v_rates (adds activity_code and band code; active cards only).
create table "public"."rates" (
  "id"               uuid                     not null default gen_random_uuid(),
  "arena_id"         uuid                     not null,
  "rate_card_id"     uuid                     not null,
  "activity_id"      uuid                     not null,
  "band_id"          uuid                     not null,
  "controller_count" integer,
  "unit_minutes"     integer                  not null default 60,
  "price_paise"      bigint                   not null,
  "created_at"       timestamp with time zone not null default now(),
  "updated_at"       timestamp with time zone not null default now(),
  "sync_xid"         xid8                     not null default pg_current_xact_id(),
  constraint "rates_activity_id_fkey" foreign key (activity_id) references public.activities(id)
    on delete cascade,
  constraint "rates_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "rates_band_id_fkey" foreign key (band_id) references public.rate_bands(id)
    on delete cascade,
  -- A zero-minute unit would divide by zero when the bill is priced.
  constraint "rates_unit_minutes_check" check ((unit_minutes > 0)),
  constraint "rates_pkey" primary key (id),
  constraint "rates_price_paise_check" check ((price_paise >= 0)),
  -- Does not stop duplicates when controller_count is null (nulls are distinct);
  -- ux_rate_per_combination below covers that case.
  constraint "rates_rate_card_id_activity_id_band_id_controller_count_key" unique
    (rate_card_id, activity_id, band_id, controller_count),
  constraint "rates_rate_card_id_fkey" foreign key (rate_card_id) references public.rate_cards(id)
    on delete cascade
);

comment on table public.rates is 'Prices on a rate card: for an activity, band and optional controller count, price_paise per unit_minutes. Part of the pricing snapshot.';

comment on column public.rates.arena_id is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column public.rates.band_id is 'Rate band (rate_bands); the pricer only uses standard. Time-of-day prices are pricing_rules.';

comment on column public.rates.controller_count is 'Number of controllers the price is for (e.g. PS5 with 1-4 pads); null = the price does not depend on controllers. Matched exactly, null to null.';

comment on column public.rates.unit_minutes is 'Length in minutes of the unit that price_paise buys (> 0). For unit-model activities (e.g. VR) it is the sold unit; otherwise price is prorated per this many minutes.';

comment on column public.rates.price_paise is 'Price in integer paise (1/100 rupee) per unit_minutes; >= 0.';

comment on column public.rates.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull (via sync_v_rates).';

alter table "public"."rates"
  enable row level security;

create index ix_rates_sync on public.rates using btree (arena_id, sync_xid);

-- One price per (card, activity, band, controller count), treating a null
-- controller count as its own value (-1), which the unique constraint cannot.
create unique index ux_rate_per_combination on public.rates
  using btree (rate_card_id, activity_id, band_id, COALESCE(controller_count, '-1'::integer));

-- Foreign-key index (joins and cascading deletes).
create index ix_rates_activity_id on public.rates using btree (activity_id);

create index ix_rates_band_id on public.rates using btree (band_id);

create trigger t_rates_sync
  before insert or update on public.rates
  for each row
  execute function public.sync_stamp();

create trigger t_rates_tomb
  after delete on public.rates
  for each row
  execute function public.sync_record_delete();

create trigger t_rates_updated
  before update on public.rates
  for each row
  execute function public.set_updated_at();

-- Activity, band and card must all belong to the rate's arena
-- (raises cross_arena_reference).
create trigger t_same_arena
  before insert or update on public.rates
  for each row
  execute function
    public._assert_same_arena('activity_id', 'activities', 'band_id', 'rate_bands', 'rate_card_id',
    'rate_cards');

create policy "p_sel_rates" on "public"."rates"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."rates"
  to "postgres", "service_role";

revoke all on table "public"."rates" from "anon";

revoke all on table "public"."rates" from "authenticated";

grant select on table "public"."rates" to "authenticated";