-- settings — per-arena key/value configuration shared across devices (jsonb)
--
-- One row per (arena, key). Devices may write 'business_hours', 'floor_options',
-- 'discount_options' and 'venue_profile' (op_settings_save / settings.save refuses others
-- with setting_not_shared).
-- venue_profile holds what the venue calls its resources (validated by _venue_profile; labels only).
-- floor_options holds what the floor app offers staff: payment methods, session start presets
-- and the end-of-session warning (validated by _floor_options; not part of pricing).
-- business_hours holds the opening window per ISO weekday in IST and
-- is part of the pricing snapshot (built-in defaults when absent); saving it
-- retires the previous price list into pricing_catalog_history.
create table "public"."settings" (
  "arena_id"   uuid                     not null,
  "key"        text                     not null,
  "json"       jsonb                    not null,
  "updated_at" timestamp with time zone not null default now(),
  "sync_xid"   xid8                     not null default pg_current_xact_id(),
  constraint "settings_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "settings_pkey" primary key (arena_id, key)
);

comment on table public.settings is 'Per-arena key/value settings synced to devices. Writable through settings.save: business_hours and floor_options.';

comment on column public.settings.arena_id is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column public.settings.key is 'Setting name, unique per arena. Writable: business_hours, floor_options.';

comment on column public.settings.json is 'Setting value. business_hours: {"open": {...}} keyed by ISO weekday "1" (Monday) to "7", value {"start": m, "end": m} in minutes after IST midnight, or null when closed (a legacy "happy" key is ignored). floor_options: {"payment_methods": [...], "start_presets": [minutes...], "warn_minutes": n}.';

comment on column public.settings.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

alter table "public"."settings"
  enable row level security;

create index ix_settings_sync on public.settings using btree (arena_id, sync_xid);

create trigger t_settings_sync
  before insert or update on public.settings
  for each row
  execute function public.sync_stamp();

create trigger t_settings_tomb
  after delete on public.settings
  for each row
  execute function public.sync_record_delete();

create trigger t_settings_updated
  before update on public.settings
  for each row
  execute function public.set_updated_at();

create policy "p_sel_settings" on "public"."settings"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."settings"
  to "postgres", "service_role";

revoke all on table "public"."settings" from "anon";

revoke all on table "public"."settings" from "authenticated";

grant select on table "public"."settings" to "authenticated";