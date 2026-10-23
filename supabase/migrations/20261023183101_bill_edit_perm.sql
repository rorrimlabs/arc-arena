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
    if v_perms && array['money', 'reports', 'payroll', 'payroll_finalise', 'bill_edit']
       and not private.app_is_owner(p_arena) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'only an owner can grant money, reports, payroll or bill editing';
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
  if auth.uid() is null or p_arena is null or not private.app_has_perm(p_arena, 'bill_edit') then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs bill_edit';
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

create or replace function public._known_perms()
  returns text[]
  language sql
  immutable
  set search_path to 'public'
  AS $function$
  select array['start','bill','discount','members','stations','money','reports','settings',
               'attendance_review','leave_approve','payroll','payroll_finalise','bill_edit'];
$function$;

create or replace function public.my_bills (
  p_arena uuid,
  p_day   date
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.my_bills(p_arena, p_day);
$function$;

create or replace function public.op_bill_adjust (
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
  v_group  boolean := coalesce(p->>'scope', 'single') = 'group';
  v_parent uuid := (p->>'parent_id')::uuid;
  v_new    bigint := (p->>'billed_amount_paise')::bigint;
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_method text := p->>'method';
  v_pay_id uuid := coalesce(nullif(p->>'payment_id', '')::uuid, gen_random_uuid());
  v_entity text := case when coalesce(p->>'scope', 'single') = 'group' then 'group_session'
                        else 'session' end;
  v_status text; v_pay text; v_old bigint; v_paid bigint; v_diff bigint;
  v_by     uuid;
  v_money  boolean := private.app_has_perm(p_arena, 'money');
begin
  if not v_money then perform _need(p_arena, 'bill_edit'); end if;
  if v_reason is null then
    raise exception 'reason_required' using hint = 'say why the bill changes';
  end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long' using hint = 'at most 500 characters'; end if;
  if v_new is null or v_new < 0 then
    raise exception 'invalid_total' using hint = 'the new total in whole paise, 0 or more';
  end if;

  -- Lock the bill (as op_payment does), so payments on it queue behind the change.
  if v_group then
    select status, payment_status, billed_amount_paise, created_by into v_status, v_pay, v_old, v_by
      from group_sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'group'; end if;
    select coalesce(sum(amount_paise), 0) into v_paid from group_payments where group_id = v_parent;
  else
    select status, payment_status, billed_amount_paise, created_by into v_status, v_pay, v_old, v_by
      from sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'session'; end if;
    select coalesce(sum(amount_paise), 0) into v_paid from payments where session_id = v_parent;
  end if;
  if not v_money and v_by is distinct from auth.uid() then
    raise exception 'forbidden' using errcode = '42501', hint = 'not your bill';
  end if;
  if v_status = 'voided' then raise exception 'voided' using hint = 'a voided bill has no total'; end if;
  if v_status <> 'completed' or v_old is null then
    raise exception 'not_ended' using hint = 'end the session first';
  end if;
  if v_pay = 'waived' then raise exception 'waived' using hint = 'a waived bill owes nothing'; end if;
  if v_new = v_old and v_paid = v_new then
    raise exception 'same_total' using hint = 'the bill is already that amount and paid';
  end if;

  -- What the bill says is what was collected: the difference goes in (or back) now.
  v_diff := v_new - v_paid;
  if v_diff <> 0 then
    if v_method is null or v_method not in ('cash', 'upi', 'card', 'other') then
      raise exception 'invalid_method' using hint = 'how the difference was paid or given back';
    end if;
    if v_group then
      insert into group_payments(id, arena_id, group_id, amount_paise, method, is_refund, note,
          reason, created_by, created_at)
        values (v_pay_id, p_arena, v_parent, v_diff, v_method, v_diff < 0, 'Bill edited',
          v_reason, auth.uid(), v_now);
    else
      insert into payments(id, arena_id, session_id, amount_paise, method, kind, note, reason,
          created_by, created_at)
        values (v_pay_id, p_arena, v_parent, v_diff, v_method,
          case when v_diff < 0 then 'refund' else 'payment' end, 'Bill edited',
          v_reason, auth.uid(), v_now);
    end if;
  end if;
  if v_group then
    update group_sessions set billed_amount_paise = v_new, payment_status = 'paid', updated_at = v_now
      where id = v_parent;
  else
    update sessions set billed_amount_paise = v_new, payment_status = 'paid', updated_at = v_now
      where id = v_parent;
  end if;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after,
      created_by, created_at)
    values (p_arena, v_entity, v_parent, 'bill_adjust', v_reason,
      jsonb_build_object('billed_paise', v_old, 'paid_paise', v_paid),
      jsonb_build_object('billed_paise', v_new, 'paid_paise', v_new), auth.uid(), v_now);
  return jsonb_build_object('payment_status', 'paid');
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
    -- Editing closed bills changes money already taken: owners only hand out bill_edit.
    if not private.app_is_owner(p_arena)
       and ('bill_edit' = any(v_perms)) <> ('bill_edit' = any(v_old_perms)) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'only an owner can grant or remove bill editing';
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

comment on column "public"."staff_profiles"."perms" is 'Permission codes from _known_perms(): start, bill, discount, members, stations, money, reports, settings, attendance_review, leave_approve, payroll, payroll_finalise, bill_edit. Holding money or reports makes the member owner level (app_is_owner).';

comment on function "private"."my_bills"(uuid, date) is 'Client API (bill_edit): the caller''s own closed bills (sessions and groups they started) that closed on the given IST day, newest first, as _sales summaries — the floor app''s My bills.';

comment on function "public"."_known_perms"() is 'The permission codes a staff profile may hold: start, bill, discount, members, stations, money, reports, settings, attendance_review, leave_approve, payroll, payroll_finalise, bill_edit.';

comment on function "public"."my_bills"(uuid, date) is 'Client API (bill_edit): the caller''s own closed bills that closed on the given IST day, for the floor app''s My bills.';

comment on function "public"."op_bill_adjust"(uuid, jsonb) is 'Sync op bill.adjust: sets a closed bill''s total (money permission, or bill_edit on a bill the caller started; reason required) and records the difference as a payment or refund so collected matches it; audited; charges untouched.';

revoke all on function "private"."my_bills"(uuid, date) from public;

grant execute
  on function "private"."my_bills"(uuid, date)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."my_bills"(uuid, date) from public;

grant execute
  on function "public"."my_bills"(uuid, date)
  to "authenticated", "postgres", "service_role";
