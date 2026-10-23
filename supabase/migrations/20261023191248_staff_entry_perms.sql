set local check_function_bodies = off;

create or replace function private.invite_member (
  p_arena uuid,
  p_email text,
  p_name  text,
  p_role  text,
  p_perms text[]
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_email   text := lower(btrim(coalesce(p_email, '')));
  v_name    text := btrim(coalesce(p_name, ''));
  v_owner   boolean;
  v_perms   text[];
  v_token   text;
  v_id      uuid;
  v_expires timestamptz := statement_timestamp() + interval '7 days';
begin
  if auth.uid() is null then
    raise exception 'forbidden' using errcode = '42501', hint = 'sign in first';
  end if;
  if p_role is null or p_role not in ('staff', 'owner') then
    raise exception 'invalid_role' using hint = 'role must be staff or owner';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid_email' using hint = 'enter a valid e-mail address';
  end if;
  if length(v_name) < 1 or length(v_name) > 80 then
    raise exception 'invalid_name' using hint = 'the name must be 1 to 80 characters';
  end if;
  v_owner := exists (select 1 from staff_profiles where arena_id = p_arena
                       and user_id = auth.uid() and active and role = 'owner');
  if p_role = 'owner' then
    if not v_owner then
      raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can invite an owner';
    end if;
    v_perms := _known_perms();
  else
    perform _need(p_arena, 'settings');
    perform _assert_known_perms(p_perms);
    v_perms := coalesce(p_perms, '{}');
    if v_perms && array['money', 'reports', 'payroll', 'payroll_finalise', 'bill_edit', 'bill_record']
       and not private.app_is_owner(p_arena) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'only an owner can grant money, reports, payroll, or editing or adding bills';
    end if;
  end if;
  if exists (select 1 from auth.users where id = auth.uid() and lower(email) = v_email) then
    raise exception 'forbidden' using errcode = '42501', hint = 'you cannot invite yourself';
  end if;
  if not v_owner and exists (select 1 from staff_invites where arena_id = p_arena
       and email = v_email and role = 'owner' and accepted_at is null and revoked_at is null) then
    raise exception 'forbidden' using errcode = '42501',
      hint = 'an owner invited this address; only an owner can replace that invite';
  end if;
  update staff_invites set revoked_at = statement_timestamp()
   where arena_id = p_arena and email = v_email and accepted_at is null and revoked_at is null;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into staff_invites (arena_id, email, name, role, perms, token_hash, invited_by, expires_at)
    values (p_arena, v_email, v_name, p_role, v_perms,
            extensions.digest(v_token, 'sha256'), auth.uid(), v_expires)
    returning id into v_id;
  return jsonb_build_object('invite_id', v_id, 'token', v_token, 'expires_at', v_expires);
end;
$function$;

create or replace function private.my_bills (
  p_arena uuid,
  p_day   date
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_from timestamptz := p_day::timestamp at time zone 'Asia/Kolkata';
begin
  if auth.uid() is null or p_arena is null
     or not (private.app_has_perm(p_arena, 'bill_edit')
             or private.app_has_perm(p_arena, 'bill_record')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs bill_edit or bill_record';
  end if;
  if p_day is null then
    raise exception 'invalid_range' using hint = 'a day';
  end if;
  return coalesce((
    select jsonb_agg(b order by (b->>'at')::timestamptz desc, b->>'id')
      from _sales(p_arena, v_from, v_from + interval '1 day') b
     where (b->>'id')::uuid in (
             select id from sessions where arena_id = p_arena and created_by = auth.uid()
             union all
             select id from group_sessions where arena_id = p_arena and created_by = auth.uid())),
    '[]'::jsonb);
end;
$function$;

create or replace function private.session_quote (
  p_arena       uuid,
  p_resource    uuid,
  p_activity    text,
  p_controllers integer,
  p_from        timestamp with time zone,
  p_to          timestamp with time zone
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_snap jsonb; q jsonb; pol jsonb; v_sub bigint;
begin
  if auth.uid() is null or p_arena is null or not private.app_has_perm(p_arena, 'bill_record') then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs bill_record';
  end if;
  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > interval '24 hours' then
    raise exception 'invalid_time' using hint = 'the end must be after the start, at most 24 h later';
  end if;
  if not exists (select 1 from resources where id = p_resource and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'station';
  end if;
  v_snap := _pricing_snapshot(p_arena);
  perform _seg_priced(p_arena, p_resource, v_snap, p_activity, p_controllers);
  q := _pr_quote(v_snap, p_activity, p_controllers, p_from, p_to, p_from);
  pol := _pr_policy(v_snap);
  v_sub := coalesce((q->>'subtotal')::bigint, 0);
  return jsonb_build_object('subtotal', v_sub,
    'total', _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir'));
end;
$function$;

create or replace function public._known_perms()
  returns text[]
  language sql
  immutable
  set search_path to 'public'
  AS $function$
  select array['start','bill','discount','members','stations','money','reports','settings',
               'attendance_review','leave_approve','payroll','payroll_finalise','bill_edit',
               'bill_record','time_request'];
$function$;

create or replace function public.op_attendance_request (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now    timestamptz := statement_timestamp();
  v_id     uuid := (p->>'id')::uuid;
  v_kind   text := p->>'kind';
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_in     timestamptz := (p->>'in_at')::timestamptz;
  v_out    timestamptz := (p->>'out_at')::timestamptz;
  v_entry  attendance_entries;
  v_staff  uuid;
  v_day    date;
begin
  perform _need(p_arena, 'time_request');
  select id into v_staff from staff_profiles
    where arena_id = p_arena and user_id = auth.uid() and active;
  if not found then raise exception 'not_found' using hint = 'staff'; end if;
  if v_reason is null then raise exception 'reason_required'; end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long'; end if;
  if v_id is null or v_kind is null or v_kind not in ('add', 'fix_out') then
    raise exception 'invalid_payload' using hint = 'id; kind: add or fix_out';
  end if;

  if v_kind = 'fix_out' then
    select * into v_entry from attendance_entries
      where id = (p->>'entry_id')::uuid and arena_id = p_arena and staff_id = v_staff;
    if not found then raise exception 'not_found' using hint = 'entry'; end if;
    if v_entry.status <> 'active' then raise exception 'not_active'; end if;
    v_in := v_entry.in_at;
  end if;
  if v_in is null or v_out is null or v_out <= v_in or v_out > v_now
     or v_out - v_in > interval '24 hours' then
    raise exception 'invalid_times'
      using hint = 'clock-out after clock-in, not in the future, at most 24 h';
  end if;
  v_day := case when v_kind = 'fix_out' then v_entry.work_date else _att_work_date(v_staff, v_in) end;
  if _period_finalised(p_arena, v_day, v_day) then
    raise exception 'period_finalised' using hint = v_day::text;
  end if;
  if v_kind = 'add' and exists (
       select 1 from attendance_entries
        where staff_id = v_staff and status = 'active'
          and tstzrange(in_at, coalesce(out_at, 'infinity')) && tstzrange(v_in, v_out)) then
    raise exception 'overlap' using hint = 'you already have time recorded then';
  end if;

  insert into attendance_requests(id, arena_id, staff_id, kind, entry_id, in_at, out_at, reason,
      created_by, created_at)
    values (v_id, p_arena, v_staff, v_kind, v_entry.id, v_in, v_out, v_reason, auth.uid(), v_now);
  return jsonb_build_object('id', v_id);
end;
$function$;

create or replace function public.op_session_record (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now      timestamptz := statement_timestamp();
  v_id       uuid := (p->>'session_id')::uuid;
  v_pay_id   uuid := (p->>'payment_id')::uuid;
  v_customer uuid := (p->>'customer_id')::uuid;
  v_res      uuid := (p->>'resource_id')::uuid;
  v_act      text := p->>'activity_code';
  v_game     uuid := nullif(p->>'game_id', '')::uuid;
  v_cc       integer := nullif(p->>'controller_count', '')::int;
  v_start    timestamptz := (p->>'started_at')::timestamptz;
  v_end      timestamptz := (p->>'ended_at')::timestamptz;
  v_method   text := p->>'method';
  v_billed   bigint := (p->>'billed_amount_paise')::bigint;
  v_reason   text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_snap jsonb; v_seg uuid := gen_random_uuid(); q jsonb; l jsonb; v_bill jsonb;
  v_total bigint; v_pay text;
begin
  perform _need(p_arena, 'bill_record');
  if v_reason is null then
    raise exception 'reason_required' using hint = 'say why the bill is added later';
  end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long' using hint = 'at most 500 characters'; end if;
  if v_id is null or v_pay_id is null or v_customer is null or v_res is null or v_act is null
     or v_start is null or v_end is null or v_billed is null or v_billed < 0
     or (v_cc is not null and v_cc not between 1 and 4) then
    raise exception 'invalid_payload';
  end if;
  if v_method is null or v_method not in ('cash', 'upi', 'card', 'other') then
    raise exception 'invalid_method' using hint = 'how the bill was paid';
  end if;
  if v_end > v_now + interval '2 minutes' then
    raise exception 'time_in_future' using hint = 'ended_at';
  end if;
  if v_end <= v_start or v_end - v_start > interval '24 hours' then
    raise exception 'invalid_time' using hint = 'the end must be after the start, at most 24 h later';
  end if;
  if not exists (select 1 from customers where id = v_customer and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'customer';
  end if;
  -- Lock the station so two missed bills for the same time cannot both pass the overlap check.
  perform 1 from resources where id = v_res and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'station'; end if;
  if v_game is not null and not exists (select 1 from games where id = v_game and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'game';
  end if;
  if exists (select 1 from session_segments
              where resource_id = v_res and arena_id = p_arena
                and tstzrange(started_at, coalesce(ended_at, 'infinity')) && tstzrange(v_start, v_end))
     or exists (select 1 from group_assignments
              where resource_id = v_res and arena_id = p_arena
                and tstzrange(started_at, coalesce(ended_at, 'infinity')) && tstzrange(v_start, v_end)) then
    raise exception 'overlap' using hint = 'the station already has play recorded in that time';
  end if;

  v_snap := _pricing_snapshot(p_arena);
  perform _seg_priced(p_arena, v_res, v_snap, v_act, v_cc);

  insert into sessions(id, arena_id, customer_id, status, payment_status, started_at,
      scheduled_end_at, actual_ended_at, pricing_snapshot, policy_snapshot, billed_amount_paise,
      created_at, updated_at, created_by, ended_recorded_at)
    values (v_id, p_arena, v_customer, 'completed', 'unpaid', v_start, v_end, v_end, v_snap,
      v_snap->'policy', v_billed, v_now, v_now, auth.uid(), v_now);
  insert into session_segments(id, arena_id, session_id, idx, resource_id, activity_code, game_id,
      controller_count, started_at, ended_at, created_at)
    values (v_seg, p_arena, v_id, 0, v_res, v_act, v_game, v_cc, v_start, v_end, v_now);

  -- Charge rows straight from the server's quote (the same lines _pr_session_bill keys).
  q := _pr_quote(v_snap, v_act, v_cc, v_start, v_end, v_start);
  for l in select value from jsonb_array_elements(coalesce(q->'lines', '[]'::jsonb)) loop
    insert into session_charges(id, arena_id, session_id, segment_id, segment_index, band_code,
        activity_code, resource_id, controller_count, segment_start, segment_end, played_minutes,
        billed_minutes, unit_minutes, unit_price_paise, amount_paise, created_at)
      values (gen_random_uuid(), p_arena, v_id, v_seg, 0, l->>'band', v_act, v_res, v_cc,
        (l->>'start')::timestamptz, (l->>'end')::timestamptz,
        ((l->>'played_seconds')::bigint / 60)::int, (l->>'billed_minutes')::int,
        (l->>'unit_minutes')::int, (l->>'unit_price')::bigint, (l->>'amount')::bigint, v_now);
  end loop;
  v_bill := _pr_session_bill(v_id, v_end, true);
  v_total := (v_bill->>'total')::bigint;
  if v_total is distinct from v_billed then
    perform _price_mismatch('bill', v_total, v_billed);
  end if;

  if v_total > 0 then
    insert into payments(id, arena_id, session_id, amount_paise, method, kind, note, reason,
        created_by, created_at)
      values (v_pay_id, p_arena, v_id, v_total, v_method, 'payment', 'Added later', v_reason,
        auth.uid(), v_now);
  end if;
  v_pay := _payment_status(v_total, v_total);
  update sessions set payment_status = v_pay where id = v_id;

  update customers set last_visit_at = greatest(coalesce(last_visit_at, v_start), v_start)
    where id = v_customer;
  if v_game is not null then
    update games set last_played_at = greatest(coalesce(last_played_at, v_start), v_start)
      where id = v_game;
  end if;

  insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after,
      created_by, created_at)
    values (p_arena, 'session', v_id, 'record', v_reason, null,
      jsonb_build_object('billed_paise', v_total, 'method', v_method, 'resource_id', v_res,
        'started_at', v_start, 'ended_at', v_end),
      auth.uid(), v_now);
  return jsonb_build_object('session_id', v_id, 'billed_amount_paise', v_total,
    'payment_status', v_pay);
end;
$function$;

create or replace function public.op_staff_update (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  -- money / reports make a member "owner level" (app_is_owner, and the app's
  -- AppUser.isOwner). Only an owner-level member may hand them out or take them away.
  c_owner_perms constant text[] := array['money', 'reports'];
  v_user   uuid    := (p->>'user_id')::uuid;
  -- A field the op leaves out keeps its current value: a partial update must
  -- never wipe someone's permissions or silently reactivate them.
  v_perms  text[]  := case when p ? 'perms'
                        then array(select jsonb_array_elements_text(coalesce(p->'perms', '[]'::jsonb))) end;
  v_active boolean := (p->>'active')::boolean;
  v_role   text;
  v_old_perms  text[];
  v_old_active boolean;
  v_adj    boolean := false;
begin
  perform _need(p_arena, 'settings');
  select role, perms, active into v_role, v_old_perms, v_old_active from staff_profiles
    where arena_id = p_arena and user_id = v_user for update;
  if not found then raise exception 'not_found' using hint = 'staff'; end if;
  v_perms := coalesce(v_perms, v_old_perms);
  v_active := coalesce(v_active, v_old_active);
  perform _assert_known_perms(v_perms);

  if v_role = 'owner' then
    if not exists (select 1 from staff_profiles where arena_id = p_arena
         and user_id = auth.uid() and active and role = 'owner') then
      raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can change an owner';
    end if;
    -- The server already treats a role owner as holding everything
    -- (app_has_perm); the app reads the perms list. Keep the list complete and
    -- the profile active so both agree and the arena always has an owner.
    -- Removing an owner is an operator action on the database, not an op.
    v_adj := not (v_perms @> _known_perms()) or not v_active;
    v_perms := _known_perms();
    v_active := true;
  else
    -- Nobody changes their own access: a Settings holder could otherwise grant
    -- themselves money/reports and become owner level.
    if v_user = auth.uid()
       and (not (v_perms @> v_old_perms and v_old_perms @> v_perms) or v_active <> v_old_active) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'you cannot change your own permissions';
    end if;
    -- Owner-level perms, and owner-level members, are managed by owners only.
    if not private.app_is_owner(p_arena)
       and (v_old_perms && c_owner_perms
            or ('money' = any(v_perms)) <> ('money' = any(v_old_perms))
            or ('reports' = any(v_perms)) <> ('reports' = any(v_old_perms))) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'only an owner can grant money or reports, or change an owner-level member';
    end if;
    -- Pay is owner-level business too: only an owner-level member hands out or takes away
    -- payroll / payroll_finalise.
    if not private.app_is_owner(p_arena)
       and (('payroll' = any(v_perms)) <> ('payroll' = any(v_old_perms))
            or ('payroll_finalise' = any(v_perms)) <> ('payroll_finalise' = any(v_old_perms))) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'only an owner can grant or remove payroll permissions';
    end if;
    -- Editing closed bills or adding missed ones records money: owners only hand out
    -- bill_edit and bill_record.
    if not private.app_is_owner(p_arena)
       and (('bill_edit' = any(v_perms)) <> ('bill_edit' = any(v_old_perms))
            or ('bill_record' = any(v_perms)) <> ('bill_record' = any(v_old_perms))) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'only an owner can grant or remove editing or adding bills';
    end if;
  end if;

  update staff_profiles set name = coalesce(nullif(btrim(p->>'name'), ''), name),
      perms = v_perms, active = v_active,
      sort_order = coalesce((p->>'sort_order')::int, sort_order),
      updated_at = statement_timestamp()
    where arena_id = p_arena and user_id = v_user;
  perform _assert_settings_holder(p_arena);
  -- Access changes are audited with the before and after (permissions edit in place).
  insert into audit_log(arena_id, entity_type, entity_id, action, before, after, created_by, created_at)
    select p_arena, 'staff_profile', s.id, 'access',
           jsonb_build_object('perms', to_jsonb(v_old_perms), 'active', v_old_active),
           jsonb_build_object('perms', to_jsonb(s.perms), 'active', s.active),
           auth.uid(), statement_timestamp()
      from staff_profiles s
     where s.arena_id = p_arena and s.user_id = v_user
       and (s.perms is distinct from v_old_perms or s.active is distinct from v_old_active);
  -- adjusted = the device wrote something else: it refetches the staff list.
  return case when v_adj then '{"adjusted": true}'::jsonb else '{}'::jsonb end;
end;
$function$;

comment on column "public"."staff_profiles"."perms" is 'Permission codes from _known_perms(): start, bill, discount, members, stations, money, reports, settings, attendance_review, leave_approve, payroll, payroll_finalise, bill_edit, bill_record, time_request. Holding money or reports makes the member owner level (app_is_owner).';

comment on function "private"."my_bills"(uuid, date) is 'Client API (bill_edit or bill_record): the caller''s own closed bills (sessions and groups they started) that closed on the given IST day, newest first, as _sales summaries — the floor app''s My bills.';

comment on function "private"."session_quote"(uuid, uuid, text, integer, timestamp
  with time zone, timestamp with time zone) is 'Client API (bill_record): the price session.record would bill for a past single session on the current price list, {subtotal, total}.';

comment on function "public"."_known_perms"() is 'The permission codes a staff profile may hold: start, bill, discount, members, stations, money, reports, settings, attendance_review, leave_approve, payroll, payroll_finalise, bill_edit, bill_record, time_request.';

comment on function "public"."my_bills"(uuid, date) is 'Client API (bill_edit or bill_record): the caller''s own closed bills that closed on the given IST day, for the floor app''s My bills.';

comment on function "public"."op_attendance_request"(uuid, jsonb) is 'Sync op attendance.request: a member with time_request asks to add a missed stretch or fix a missed clock-out on their own attendance; pending until a reviewer decides.';

comment on function "public"."op_session_record"(uuid, jsonb) is 'Sync op session.record: add a missed single session after the fact (bill_record), already ended, priced on the current price list and paid in full; overlap-checked against the station''s recorded play; audited with the required reason.';

comment on function "public"."session_quote"(uuid, uuid, text, integer, timestamp
  with time zone, timestamp with time zone) is 'Client API (bill_record): the price of a missed single session before session.record adds it.';
