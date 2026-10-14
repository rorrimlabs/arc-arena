set local check_function_bodies = off;

drop trigger "t_same_arena" on "public"."controllers";

create table "public"."accessory_kinds" (
  "id"                   uuid                     not null default gen_random_uuid(),
  "arena_id"             uuid                     not null,
  "name"                 text                     not null,
  "counts_as_controller" boolean                  not null default false,
  "sort_order"           integer                  not null default 0,
  "active"               boolean                  not null default true,
  "created_at"           timestamp with time zone not null default now(),
  "updated_at"           timestamp with time zone not null default now(),
  "sync_xid"             xid8                     not null default pg_current_xact_id(),
  constraint "accessory_kinds_name_check"
    check (((char_length(name) >= 1) AND (char_length(name) <= 40))),
  constraint "accessory_kinds_pkey" primary key (id)
);

alter table "public"."accessory_kinds"
  enable row level security;

alter table "public"."controllers"
  add column "kind_id" uuid;

alter table "public"."controllers"
  add column "created_at" timestamp with time zone not null default now();

create or replace function public._free_pads_at (
  p_arena    uuid,
  p_resource uuid
)
  returns integer
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select count(*)::int from controllers c
   where c.arena_id = p_arena and c.current_resource_id = p_resource and c.status = 'usable'
     and _is_pad(c.kind_id)
     and not exists (select 1 from controller_allocations a
                      where a.controller_id = c.id and a.ended_at is null);
$function$;

create or replace function public._inventory_tracked (
  p_arena uuid
)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select exists (select 1 from controllers
                  where arena_id = p_arena and status <> 'retired' and _is_pad(kind_id));
$function$;

create or replace function public._is_pad (
  p_kind uuid
)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select p_kind is null
      or coalesce((select k.counts_as_controller from accessory_kinds k where k.id = p_kind), false);
$function$;

create or replace function public._pad_allocate (
  p_arena      uuid,
  p_allocs     jsonb,
  p_scope      text,
  p_session    uuid,
  p_group      uuid,
  p_segment    uuid,
  p_assignment uuid,
  p_player     integer,
  p_label      text,
  p_resource   uuid,
  p_activity   text,
  p_game       uuid,
  p_started    timestamp with time zone
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_a jsonb; v_cid uuid; v_status text; v_loc uuid; v_kind uuid;
  v_ids uuid[] := _pad_ids(p_allocs);
begin
  if coalesce(array_length(v_ids, 1), 0) = 0 then return; end if;
  if array_length(v_ids, 1) <> (select count(distinct x) from unnest(v_ids) x) then
    raise exception 'controller_duplicate';
  end if;
  for v_a in select value from jsonb_array_elements(p_allocs) loop
    v_cid := (v_a->>'controller_id')::uuid;
    select status, current_resource_id, kind_id into v_status, v_loc, v_kind
      from controllers where id = v_cid and arena_id = p_arena;
    if not found then raise exception 'controller_missing'; end if;
    if not _is_pad(v_kind) then raise exception 'not_a_controller'; end if;
    if v_status <> 'usable' then raise exception 'controller_unusable' using hint = v_status; end if;
    if v_loc <> p_resource then raise exception 'controller_elsewhere'; end if;
    if exists (select 1 from controller_allocations where controller_id = v_cid and ended_at is null) then
      raise exception 'controller_taken';
    end if;
    if _untracked_busy(p_arena, p_resource, array_remove(array[p_segment, p_assignment], null)) then
      raise exception 'controller_taken' using hint = 'untracked_player';
    end if;
  end loop;
  for v_a in select value from jsonb_array_elements(p_allocs) loop
    insert into controller_allocations(id, arena_id, controller_id, scope, session_id, group_id,
        segment_id, assignment_id, player_number, player_label, resource_id, activity_code,
        game_id, started_at, created_by, created_at)
      values (coalesce(nullif(v_a->>'id','')::uuid, gen_random_uuid()), p_arena,
        (v_a->>'controller_id')::uuid, p_scope, p_session, p_group, p_segment, p_assignment,
        p_player, p_label, p_resource, p_activity, p_game, p_started, auth.uid(), v_now);
  end loop;
end;
$function$;

create or replace function public._pad_borrow (
  p_arena       uuid,
  p_moves       jsonb,
  p_resource    uuid,
  p_session_ref text,
  p_at          timestamp with time zone
)
  returns integer
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now  timestamptz := statement_timestamp();
  v_m    jsonb;
  v_cid  uuid;
  v_status text; v_loc uuid; v_home uuid; v_kind uuid; v_return boolean;
  v_skipped int := 0;
begin
  for v_m in select value from jsonb_array_elements(coalesce(p_moves, '[]'::jsonb)) loop
    v_cid := (v_m->>'controller_id')::uuid;
    select status, current_resource_id, home_resource_id, kind_id into v_status, v_loc, v_home, v_kind
      from controllers where id = v_cid and arena_id = p_arena;
    if not found then raise exception 'controller_missing'; end if;
    if not _is_pad(v_kind) then raise exception 'not_a_controller'; end if;
    if v_loc = p_resource then v_skipped := v_skipped + 1; continue; end if;
    if v_status <> 'usable' then raise exception 'controller_unusable' using hint = v_status; end if;
    if exists (select 1 from controller_allocations where controller_id = v_cid and ended_at is null) then
      raise exception 'controller_taken';
    end if;
    if _untracked_busy(p_arena, v_loc) then
      raise exception 'controller_taken' using hint = 'station_in_use';
    end if;
    v_return := v_home = p_resource;
    update controllers
       set current_resource_id = p_resource,
           loan_return_to   = case when v_return then null else v_home::text end,
           loan_session_ref = case when v_return then null else p_session_ref end,
           updated_at = v_now
     where id = v_cid;
    insert into controller_moves(id, arena_id, controller_id, from_resource_id, to_resource_id,
        kind, session_ref, moved_at, created_by, created_at)
      values (coalesce(nullif(v_m->>'id','')::uuid, gen_random_uuid()), p_arena, v_cid, v_loc,
        p_resource, case when v_return then 'returnHome' else 'loan' end,
        case when v_return then null else p_session_ref end, p_at, auth.uid(), v_now);
  end loop;
  return v_skipped;
end;
$function$;

create or replace function public._sync_apply (
  p_arena uuid,
  p_kind  text,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_before jsonb; v_res jsonb;
begin
  -- A price-list change retires the previous catalog into
  -- pricing_catalog_history, so a session priced on it still validates.
  if p_kind in ('rate.upsert', 'rate.delete', 'policy.save', 'settings.save',
                'holiday.upsert', 'holiday.delete', 'activity.upsert', 'activity.remove') then
    v_before := _pricing_canon(_pricing_snapshot(p_arena));
  end if;

  -- Dispatch: one op kind -> one op_* function. Unknown kinds return null and
  -- sync_push rejects them.
  v_res := case p_kind
      when 'session.start'        then op_session_start(p_arena, p)
      when 'session.reconfigure'  then op_session_reconfigure(p_arena, p)
      when 'session.extend'       then op_session_extend(p_arena, p)
      when 'session.end'          then op_session_end(p_arena, p)
      when 'session.void'         then op_session_void(p_arena, p)
      when 'payment.record'       then op_payment(p_arena, p)
      when 'payment.correct'      then op_payment_correct(p_arena, p)
      when 'group.create'         then op_group_create(p_arena, p)
      when 'group.add'            then op_group_add(p_arena, p)
      when 'group.switch'         then op_group_switch(p_arena, p)
      when 'group.end_player'     then op_group_end_player(p_arena, p)
      when 'group.extend'         then op_group_extend(p_arena, p)
      when 'group.end'            then op_group_end(p_arena, p)
      when 'group.void'           then op_group_void(p_arena, p)
      when 'controller.move'      then op_controller_move(p_arena, p)
      when 'controller.upsert'    then op_controller_upsert(p_arena, p)
      when 'controller.set_status' then op_controller_set_status(p_arena, p)
      when 'accessory_kind.upsert' then op_accessory_kind_upsert(p_arena, p)
      when 'accessory_kind.remove' then op_accessory_kind_remove(p_arena, p)
      when 'customer.create'      then op_customer_create(p_arena, p)
      when 'customer.update'      then op_customer_update(p_arena, p)
      when 'booking.create'       then op_booking_create(p_arena, p)
      when 'booking.update'       then op_booking_update(p_arena, p)
      when 'booking.set_status'   then op_booking_set_status(p_arena, p)
      when 'game.upsert'          then op_game_upsert(p_arena, p)
      when 'game.set_active'      then op_game_set_active(p_arena, p)
      when 'game.delete'          then op_game_delete(p_arena, p)
      when 'game.replace_controls' then op_game_replace_controls(p_arena, p)
      when 'game.set_compat'      then op_game_set_compat(p_arena, p)
      when 'resource.upsert'      then op_resource_upsert(p_arena, p)
      when 'resource.set_status'  then op_resource_set_status(p_arena, p)
      when 'resource.set_mode'    then op_resource_set_mode(p_arena, p)
      when 'activity.upsert'      then op_activity_upsert(p_arena, p)
      when 'activity.remove'      then op_activity_remove(p_arena, p)
      when 'rate.upsert'          then op_rate_upsert(p_arena, p)
      when 'rate.delete'          then op_rate_delete(p_arena, p)
      when 'policy.save'          then op_policy_save(p_arena, p)
      when 'settings.save'        then op_settings_save(p_arena, p)
      when 'holiday.upsert'       then op_holiday_upsert(p_arena, p)
      when 'holiday.delete'       then op_holiday_delete(p_arena, p)
      when 'staff.update'         then op_staff_update(p_arena, p)
      when 'arena.update'         then op_arena_update(p_arena, p)
      else null
    end;

  if v_before is not null and v_before <> _pricing_canon(_pricing_snapshot(p_arena)) then
    insert into pricing_catalog_history(arena_id, canon, retired_at)
      values (p_arena, v_before, statement_timestamp())
    on conflict (arena_id, canon_md5) do update set retired_at = excluded.retired_at;
  end if;
  return v_res;
end;
$function$;

create or replace function public._sync_sources()
  returns table (
    name text,
    rel  text
  )
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  values
    ('arenas','sync_v_arenas'), ('staff_profiles','staff_profiles'),
    ('activities','activities'), ('resources','resources'),
    ('resource_activities','sync_v_resource_activities'), ('controllers','controllers'),
    ('customers','customers'), ('rates','sync_v_rates'),
    ('billing_policies','billing_policies'), ('holidays','holidays'),
    ('game_categories','game_categories'), ('games','games'),
    ('game_controls','game_controls'), ('game_resources','game_resources'),
    ('bookings','sync_v_bookings'), ('sessions','sessions'),
    ('session_segments','session_segments'), ('session_extensions','session_extensions'),
    ('session_charges','session_charges'), ('payments','payments'),
    ('group_sessions','group_sessions'), ('group_assignments','group_assignments'),
    ('group_extensions','group_extensions'), ('group_charges','group_charges'),
    ('group_payments','group_payments'), ('controller_allocations','controller_allocations'),
    ('controller_moves','controller_moves'), ('settings','settings'),
    ('accessory_kinds','accessory_kinds')
$function$;

create or replace function public._usable_pads_at (
  p_arena    uuid,
  p_resource uuid
)
  returns integer
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select count(*)::int from controllers
   where arena_id = p_arena and current_resource_id = p_resource and status = 'usable'
     and _is_pad(kind_id);
$function$;

create or replace function public.op_accessory_kind_remove (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_id uuid := (p->>'id')::uuid;
begin
  perform _need(p_arena, 'settings');
  if exists (select 1 from accessory_kinds where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'accessory_kind';
  end if;
  perform 1 from accessory_kinds where id = v_id and arena_id = p_arena for update;
  if not found then return jsonb_build_object('removed', 'deleted'); end if;

  if exists (select 1 from controllers where kind_id = v_id) then
    update accessory_kinds set active = false, updated_at = statement_timestamp() where id = v_id;
    return jsonb_build_object('removed', 'retired');
  end if;
  delete from accessory_kinds where id = v_id;
  return jsonb_build_object('removed', 'deleted');
end;
$function$;

create or replace function public.op_accessory_kind_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id   uuid := (p->>'id')::uuid;
  v_name text := btrim(coalesce(p->>'name', ''));
  v_pad  boolean := coalesce((p->>'counts_as_controller')::boolean, false);
  v_old  accessory_kinds%rowtype;
begin
  perform _need(p_arena, 'settings');
  if char_length(v_name) not between 1 and 40 then
    raise exception 'invalid_name' using hint = '1–40 characters';
  end if;
  if exists (select 1 from accessory_kinds where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'accessory_kind';
  end if;

  select * into v_old from accessory_kinds where id = v_id and arena_id = p_arena for update;
  if found and v_old.counts_as_controller <> v_pad and exists (
       select 1 from controller_allocations a join controllers c on c.id = a.controller_id
        where c.kind_id = v_id and a.ended_at is null) then
    raise exception 'accessory_kind_busy';
  end if;

  insert into accessory_kinds(id, arena_id, name, counts_as_controller, sort_order, active)
    values (v_id, p_arena, v_name, v_pad, coalesce((p->>'sort_order')::int, 0),
      coalesce((p->>'active')::boolean, true))
  on conflict (id) do update set
    name = excluded.name, counts_as_controller = excluded.counts_as_controller,
    sort_order = excluded.sort_order, active = excluded.active, updated_at = statement_timestamp()
  where accessory_kinds.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_activity_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id   uuid := (p->>'id')::uuid;
  v_code text := upper(btrim(coalesce(p->>'code', '')));
  v_name text := btrim(coalesce(p->>'name', ''));
  v_pads boolean := coalesce((p->>'uses_controllers')::boolean, false);
  v_old  activities%rowtype;
  v_base text;
  v_n    int := 1;
begin
  perform _need(p_arena, 'settings');
  if v_code = '' then
    select code into v_code from activities where id = v_id and arena_id = p_arena;
    if v_code is null then
      v_base := left(btrim(regexp_replace(upper(v_name), '[^A-Z0-9]+', '_', 'g'), '_'), 12);
      if v_base = '' then v_base := 'TYPE'; end if;
      v_code := v_base;
      while exists (select 1 from activities where arena_id = p_arena and code = v_code) loop
        v_n := v_n + 1;
        v_code := left(v_base, 12 - char_length(v_n::text) - 1) || '_' || v_n;
      end loop;
    end if;
  end if;
  if v_code !~ '^[A-Z0-9_]{1,12}$' then
    raise exception 'invalid_code' using hint = 'A–Z, 0–9 or _, up to 12';
  end if;
  if char_length(v_name) not between 1 and 40 then
    raise exception 'invalid_name' using hint = '1–40 characters';
  end if;
  if exists (select 1 from activities where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'activity';
  end if;

  select * into v_old from activities where id = v_id and arena_id = p_arena for update;
  if found then
    if v_old.code <> v_code then
      raise exception 'code_locked' using hint = v_old.code;
    end if;
    if v_old.uses_controllers <> v_pads and (
         exists (select 1 from session_segments
                  where arena_id = p_arena and activity_code = v_code and ended_at is null)
      or exists (select 1 from group_assignments
                  where arena_id = p_arena and activity_code = v_code and ended_at is null)) then
      raise exception 'activity_busy' using hint = v_code;
    end if;
  end if;

  insert into activities(id, arena_id, code, name, uses_controllers, uses_games, duration_model,
      happy_hour_eligible, sort_order, active)
    values (v_id, p_arena, v_code, v_name, v_pads,
      coalesce((p->>'uses_games')::boolean, false),
      coalesce(p->>'duration_model', 'hourly'),
      coalesce((p->>'happy_hour_eligible')::boolean, true),
      coalesce((p->>'sort_order')::int, 0),
      coalesce((p->>'active')::boolean, true))
  on conflict (id) do update set
    name = excluded.name, uses_controllers = excluded.uses_controllers,
    uses_games = excluded.uses_games, duration_model = excluded.duration_model,
    happy_hour_eligible = excluded.happy_hour_eligible, sort_order = excluded.sort_order,
    active = excluded.active, updated_at = statement_timestamp()
  where activities.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_controller_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id      uuid := (p->>'id')::uuid;
  v_has_kind boolean := p ? 'kind_id';
  v_kind    uuid := nullif(p->>'kind_id', '')::uuid;
  v_loc     uuid;
  v_oldkind uuid;
  v_held    boolean;
begin
  perform _need(p_arena, 'settings');
  -- An id that belongs to another arena is "not found" here, never a silent no-op.
  if exists (select 1 from controllers where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'controller';
  end if;
  select current_resource_id, kind_id into v_loc, v_oldkind
    from controllers where id = v_id and arena_id = p_arena for update;
  if found then
    if not v_has_kind then v_kind := v_oldkind; end if;
    v_held := exists (select 1 from controller_allocations where controller_id = v_id and ended_at is null);
    if v_held and (v_loc <> (p->>'current_resource_id')::uuid or not _is_pad(v_kind)) then
      raise exception 'controller_in_use';
    end if;
  end if;
  if v_kind is not null and v_kind is distinct from v_oldkind
     and not exists (select 1 from accessory_kinds where id = v_kind and active) then
    if exists (select 1 from accessory_kinds where id = v_kind) then
      raise exception 'kind_retired';
    end if;
  end if;
  insert into controllers(id, arena_id, label, home_resource_id, current_resource_id, status,
      notes, loan_return_to, loan_session_ref, kind_id)
    values (v_id, p_arena, p->>'label', (p->>'home_resource_id')::uuid,
      (p->>'current_resource_id')::uuid, coalesce(p->>'status', 'usable'), p->>'notes',
      p->>'loan_return_to', p->>'loan_session_ref', v_kind)
  on conflict (id) do update set label = excluded.label,
      home_resource_id = excluded.home_resource_id, current_resource_id = excluded.current_resource_id,
      status = excluded.status, notes = excluded.notes, loan_return_to = excluded.loan_return_to,
      loan_session_ref = excluded.loan_session_ref, kind_id = excluded.kind_id,
      updated_at = statement_timestamp()
    where controllers.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

alter table "public"."accessory_kinds"
  add constraint "accessory_kinds_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."controllers"
  add constraint "controllers_kind_id_fkey" foreign key (kind_id)
    references public.accessory_kinds(id);

create index ix_accessory_kinds_sync on public.accessory_kinds using btree (arena_id, sync_xid);

create index ix_controllers_kind_id on public.controllers using btree (kind_id);

create unique index ux_accessory_kinds_name on public.accessory_kinds
  using btree (arena_id, lower(name));

create trigger t_accessory_kinds_sync
  before insert or update on public.accessory_kinds
  for each row
  execute function public.sync_stamp();

create trigger t_accessory_kinds_tomb
  after delete on public.accessory_kinds
  for each row
  execute function public.sync_record_delete();

create trigger t_accessory_kinds_updated
  before update on public.accessory_kinds
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.controllers
  for each row
  execute function
    public._assert_same_arena('current_resource_id', 'resources', 'home_resource_id', 'resources',
    'kind_id', 'accessory_kinds');

create policy "p_sel_accessory_kinds" on "public"."accessory_kinds"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

comment on column "public"."accessory_kinds"."active" is 'False once retired (a kind some accessory still uses is retired, not deleted).';

comment on column "public"."accessory_kinds"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."accessory_kinds"."counts_as_controller" is 'True when accessories of this kind are game pads: allocated to players, counted for controller-count pricing and borrowed by session starts. Other kinds are only tracked physically.';

comment on column "public"."accessory_kinds"."name" is 'Display name, 1–40 characters, unique per arena ignoring case.';

comment on column "public"."accessory_kinds"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."controllers"."kind_id" is 'What the accessory is (accessory_kinds). Null = a game pad. Only pads (null, or a kind with counts_as_controller) can be allocated or borrowed by a session start.';

comment on function "private"."create_my_arena"(text, text) is 'Client API (self-serve sign-up): a confirmed login creates one empty arena and becomes its owner. Refuses unconfirmed logins, blank or over-long names, and a login that already owns an arena (arena_limit).';

comment on function "public"."_is_pad"(uuid) is 'True when an accessory of this kind (null = no kind) is a game pad.';

comment on function "public"."op_accessory_kind_remove"(uuid, jsonb) is 'Sync op accessory_kind.remove: deletes an accessory kind nothing uses, or retires one still in use.';

comment on function "public"."op_accessory_kind_upsert"(uuid, jsonb) is 'Sync op accessory_kind.upsert: creates or edits an accessory kind (Controller, VR headset …).';

comment on function "public"."op_controller_upsert"(uuid, jsonb) is 'Sync op controller.upsert: creates or edits a station accessory, refusing to relocate one that is in use.';

comment on table "public"."accessory_kinds" is 'Owner-defined kinds of station accessory (Controller, VR headset, Steering wheel …); counts_as_controller marks game pads.';

comment on table "public"."controllers" is 'Station accessories (pads, headsets, wheels …): label, kind, home station, current location, condition and any outstanding loan.';

revoke all on function "public"."_is_pad"(uuid) from public;

grant execute on function "public"."_is_pad"(uuid) to "postgres", "service_role";

revoke all on function "public"."op_accessory_kind_remove"(uuid, jsonb) from public;

grant execute
  on function "public"."op_accessory_kind_remove"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_accessory_kind_upsert"(uuid, jsonb) from public;

grant execute
  on function "public"."op_accessory_kind_upsert"(uuid, jsonb)
  to "postgres", "service_role";

grant select on table "public"."accessory_kinds" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."accessory_kinds"
  to "postgres", "service_role";
