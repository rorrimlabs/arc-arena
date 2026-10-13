-- game_controls — button guide for a game (what each button does)
--
-- One row per action in a game's control guide, grouped by section and ordered by
-- sort_order, shown to players by staff. Written by op_game_replace_controls
-- (game.replace_controls), which deletes the game's whole guide and inserts the
-- new list; seeded by _seed_arena_catalog. The game must be in the row's arena
-- (t_same_arena).
create table "public"."game_controls" (
  "id"          uuid                     not null default gen_random_uuid(),
  "arena_id"    uuid                     not null,
  "game_id"     uuid                     not null,
  "section"     text                     not null,
  "action"      text                     not null,
  "buttons"     text[]                   not null default '{}'::text[],
  "explanation" text,
  "notes"       text,
  "image_url"   text,
  "sort_order"  integer                  not null default 0,
  "created_at"  timestamp with time zone not null default now(),
  "updated_at"  timestamp with time zone not null default now(),
  "sync_xid"    xid8                     not null default pg_current_xact_id(),
  constraint "game_controls_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "game_controls_pkey" primary key (id),
  constraint "game_controls_game_id_fkey" foreign key (game_id) references public.games(id)
    on delete cascade
);

comment on table public.game_controls is 'Control-guide entries for a game: an action, the buttons that perform it and an optional explanation. Replaced wholesale per game by game.replace_controls.';

comment on column public.game_controls.arena_id is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column public.game_controls.section is 'Group heading within the guide (e.g. Attacking, Defending).';

comment on column public.game_controls.action is 'What the player does (e.g. Shoot, Sprint).';

comment on column public.game_controls.buttons is 'Controller button names that perform the action, in order (e.g. {CIRCLE}). Free text.';

comment on column public.game_controls.image_url is 'Optional URL of an illustration for the action.';

comment on column public.game_controls.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

alter table "public"."game_controls"
  enable row level security;

-- A game's guide in display order.
create index ix_controls_game on public.game_controls using btree (game_id, sort_order);

create index ix_game_controls_sync on public.game_controls using btree (arena_id, sync_xid);

create trigger t_game_controls_sync
  before insert or update on public.game_controls
  for each row
  execute function public.sync_stamp();

create trigger t_game_controls_tomb
  after delete on public.game_controls
  for each row
  execute function public.sync_record_delete();

create trigger t_game_controls_updated
  before update on public.game_controls
  for each row
  execute function public.set_updated_at();

-- The game must belong to the row's arena (raises cross_arena_reference).
create trigger t_same_arena
  before insert or update on public.game_controls
  for each row
  execute function public._assert_same_arena('game_id', 'games');

create policy "p_sel_game_controls" on "public"."game_controls"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."game_controls"
  to "postgres", "service_role";

revoke all on table "public"."game_controls" from "anon";

revoke all on table "public"."game_controls" from "authenticated";

grant select on table "public"."game_controls" to "authenticated";