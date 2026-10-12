-- rate_cards — a named price list that groups rates
--
-- rates hang off a card. The server works on one card at a time: _active_card
-- returns the newest active card by effective_from and creates a 'Current' card
-- if none is active (on rate.upsert / rate.delete). Only rates on active cards
-- reach devices and the pricing snapshot (sync_v_rates). Seeded by
-- _seed_arena_catalog; no op_* edits a card directly. Not itself in the sync feed.
create table "public"."rate_cards" (
  "id"             uuid                     not null default gen_random_uuid(),
  "arena_id"       uuid                     not null,
  "name"           text                     not null,
  "effective_from" timestamp with time zone not null default now(),
  "active"         boolean                  not null default true,
  "created_at"     timestamp with time zone not null default now(),
  "updated_at"     timestamp with time zone not null default now(),
  "sync_xid"       xid8                     not null default pg_current_xact_id(),
  constraint "rate_cards_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "rate_cards_pkey" primary key (id)
);

comment on table public.rate_cards is 'Named price lists grouping rates. Rates on active cards form the arena''s live price list; ops edit the newest active card.';

comment on column public.rate_cards.arena_id is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column public.rate_cards.effective_from is 'When the card takes effect (UTC); the newest active card is the one rate.upsert / rate.delete edit.';

comment on column public.rate_cards.active is 'Only rates on active cards are synced (sync_v_rates) and priced (_pricing_snapshot).';

comment on column public.rate_cards.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp). The table is not in the sync_pull feed; devices see cards only through sync_v_rates.';

alter table "public"."rate_cards"
  enable row level security;

create index ix_rate_cards_sync on public.rate_cards using btree (arena_id, sync_xid);

create trigger t_rate_cards_sync
  before insert or update on public.rate_cards
  for each row
  execute function public.sync_stamp();

create trigger t_rate_cards_tomb
  after delete on public.rate_cards
  for each row
  execute function public.sync_record_delete();

create trigger t_rate_cards_updated
  before update on public.rate_cards
  for each row
  execute function public.set_updated_at();

create policy "p_sel_rate_cards" on "public"."rate_cards"
  for select
  to authenticated
  using ((arena_id in ( select public.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."rate_cards"
  to "postgres", "service_role";

revoke all on table "public"."rate_cards" from "anon";

revoke all on table "public"."rate_cards" from "authenticated";

grant select on table "public"."rate_cards" to "authenticated";